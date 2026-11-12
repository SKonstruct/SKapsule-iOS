#import "SKBuiltinJIT.h"

#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netinet/in.h>
#import <stdatomic.h>
#import <sys/socket.h>
#import <unistd.h>

#import "SKJITAdvice.h"
#import "utils.h"

static NSString *const kMethodKey = @"jit_method";
// Before Automatic existed: YES chose built-in, NO chose the StikDebug app.
static NSString *const kLegacySelectedKey = @"jit_builtin_selected";
static NSString *const kHelperName = @"SKJITHelper.appex";
// Preparing may download and mount the Developer Disk Image, so this only has to be longer than
// a healthy run. It guards a helper that never answers, not one that is attached: an enable
// request lasts as long as the debugger does.
static const NSTimeInterval kHelperTimeout = 180;
// A pairing file is a few KB of keys and certificates.
static const NSUInteger kMaxPairingBytes = 1024 * 1024;

// The private NSExtension API (ExtensionFoundation) that lets an app start one of its own
// extensions and exchange items with it. There is no public way to launch the helper.
@protocol SKExtensionClass <NSObject>
+ (id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
@end
@protocol SKExtension <NSObject>
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *requestIdentifier))completion;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *requestIdentifier, NSArray *items))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *requestIdentifier, NSError *error))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *requestIdentifier))block;
@end

/// The interface traffic to the device's debug service (StikJIT's 10.7.0.1, LocalDevVPN's
/// side of the tunnel) would leave by, asked of the kernel with an unsent UDP connect: no
/// packets. NULL when there is no route at all.
static NSString *_Nullable skRouteInterfaceToDevice(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) return nil;
    struct sockaddr_in target = {.sin_len = sizeof(target), .sin_family = AF_INET, .sin_port = htons(62078)};
    inet_pton(AF_INET, "10.7.0.1", &target.sin_addr);
    struct sockaddr_in local = {0};
    socklen_t len = sizeof(local);
    BOOL ok = connect(fd, (struct sockaddr *)&target, sizeof(target)) == 0 &&
              getsockname(fd, (struct sockaddr *)&local, &len) == 0;
    close(fd);
    if (!ok) return nil;

    NSString *name = nil;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return nil;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (i->ifa_addr && i->ifa_addr->sa_family == AF_INET &&
            ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr == local.sin_addr.s_addr) {
            name = @(i->ifa_name);
            break;
        }
    }
    freeifaddrs(list);
    return name;
}

static BOOL skRouteIsVPN(void) {
    NSString *route = skRouteInterfaceToDevice();
    return route && ([route hasPrefix:@"utun"] || [route hasPrefix:@"ipsec"] || [route hasPrefix:@"ppp"]);
}

/// Polls off the main thread until traffic to the device routes through a VPN, for at most
/// `seconds`: LocalDevVPN can report connected a moment before its tunnel carries traffic.
static void skWaitForRoute(NSTimeInterval seconds, void (^done)(BOOL routed)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
      BOOL routed;
      while (!(routed = skRouteIsVPN()) && end.timeIntervalSinceNow > 0) usleep(500 * 1000);
      dispatch_async(dispatch_get_main_queue(), ^{
        done(routed);
      });
    });
}

/// Cellular data is up and no Wi-Fi or wired interface is: the one case where LocalDevVPN's
/// loopback fails even though it is connected.
static BOOL skOnlyCellular(void) {
    BOOL cellular = NO, other = NO;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return NO;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || !(i->ifa_flags & IFF_UP)) continue;
        if (strncmp(i->ifa_name, "pdp_ip", 6) == 0) cellular = YES;
        else if (strncmp(i->ifa_name, "en", 2) == 0) other = YES;
    }
    freeifaddrs(list);
    return cellular && !other;
}

static BOOL gDebuggedAtLaunch;

@implementation SKBuiltinJIT

+ (SKJITMethod)method {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kMethodKey]) return (SKJITMethod)[defaults integerForKey:kMethodKey];
    if ([defaults objectForKey:kLegacySelectedKey]) {
        return [defaults boolForKey:kLegacySelectedKey] ? SKJITMethodBuiltin : SKJITMethodStikDebug;
    }
    return SKJITMethodAutomatic;
}

+ (void)setMethod:(SKJITMethod)method {
    [NSUserDefaults.standardUserDefaults setInteger:method forKey:kMethodKey];
}

+ (BOOL)stikDebugInstalled {
    // Declared in LSApplicationQueriesSchemes.
    return [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"stikdebug://enable-jit"]];
}

+ (SKJITMethod)resolvedMethod {
    SKJITMethod method = self.method;
    if (method == SKJITMethodAutomatic) return self.stikDebugInstalled ? SKJITMethodStikDebug : SKJITMethodBuiltin;
    return method;
}

+ (BOOL)selected {
    return self.resolvedMethod == SKJITMethodBuiltin;
}

+ (BOOL)canGrantOwnJIT {
    if (@available(iOS 26.0, *)) return NO;
    return YES;
}

/// TrollStore leaves a marker file next to the app in its bundle container.
+ (BOOL)installedWithTrollStore {
    NSURL *container = [NSBundle.mainBundle.bundleURL URLByDeletingLastPathComponent];
    for (NSString *marker in @[ @"_TrollStore", @"_TrollStoreLite" ]) {
        if ([NSFileManager.defaultManager fileExistsAtPath:[container URLByAppendingPathComponent:marker].path]) return YES;
    }
    return NO;
}

/// A rootless jailbreak (Dopamine and its kin) keeps its files in /var/jb and lets apps see it.
+ (BOOL)jailbreakPresent {
    return [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb"];
}

+ (BOOL)debuggedAtLaunch {
    return gDebuggedAtLaunch;
}

+ (void)noteLaunchState {
    gDebuggedAtLaunch = skDebuggerAttached();
}

+ (nullable NSString *)pairingSource {
    return [NSUserDefaults.standardUserDefaults stringForKey:@"jit_pairing_source"];
}

/// In Library rather than Documents: Files and Finder can read Documents, and a pairing
/// file is a credential for the whole device.
+ (NSString *)pairingPath {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [library stringByAppendingPathComponent:@"StikJIT/pairingFile.plist"];
}

+ (nullable NSString *)helperIdentifier {
    NSURL *url = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:kHelperName];
    return url ? [NSBundle bundleWithURL:url].bundleIdentifier : nil;
}

+ (nullable NSString *)unavailableReason {
    if (getenv("LC_HOME_PATH")) return @"Built-in JIT is unavailable inside LiveContainer.";
    if (!self.helperIdentifier) return @"This build does not include the JIT helper.";
    // The debugger attaches to this process, so this is the entitlement that matters; the
    // helper's own is irrelevant.
    if (![getEntitlementValue(@"get-task-allow") boolValue]) {
        return @"This install lacks get-task-allow, so no debugger can attach. Reinstall it with a signing "
               @"method that keeps that entitlement.";
    }
    return nil;
}

+ (BOOL)hasPairingFile {
    [self adoptDroppedPairingFile];
    return [NSFileManager.defaultManager fileExistsAtPath:self.pairingPath];
}

/// Files left in Documents, which Finder, Files and sideloading tools can fill: StikJIT's own
/// documented `StikJIT/pairingFile.plist`, and the plain `pairingFile.plist` that iloader and
/// most JIT apps use. A file that imports is taken into Library and removed from Documents.
+ (void)adoptDroppedPairingFile {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    for (NSString *name in @[ @"StikJIT/pairingFile.plist", @"pairingFile.plist" ]) {
        NSString *dropped = [docs stringByAppendingPathComponent:name];
        if (![NSFileManager.defaultManager fileExistsAtPath:dropped]) continue;
        if (![self importPairingFileFromURL:[NSURL fileURLWithPath:dropped]]) {
            [NSFileManager.defaultManager removeItemAtPath:dropped error:nil];
        }
    }
}

+ (nullable NSString *)importPairingFileFromURL:(NSURL *)url {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSNumber *size = [url resourceValuesForKeys:@[NSURLFileSizeKey] error:nil][NSURLFileSizeKey];
    NSData *data = size.unsignedIntegerValue <= kMaxPairingBytes ? [NSData dataWithContentsOfURL:url] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];
    return [self savePairingData:data ?: NSData.data source:@"imported"];
}

+ (nullable NSString *)savePairingData:(NSData *)data source:(NSString *)source {
    // Only the shape is checked: its keys differ between pairing tools, and rejecting a valid
    // file is worse than the helper failing on a bad one with its own message.
    id plist = data.length == 0 ? nil : [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    if (![plist isKindOfClass:NSDictionary.class]) {
        return @"That isn't a pairing file.";
    }
    NSString *path = self.pairingPath;
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    skExcludeFromBackup(path.stringByDeletingLastPathComponent);
    if (![data writeToFile:path
                   options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication
                     error:nil]) {
        return @"Couldn't save the pairing file.";
    }
    // Importing one is the clearest statement of intent there is.
    [NSUserDefaults.standardUserDefaults setObject:source forKey:@"jit_pairing_source"];
    self.method = SKJITMethodBuiltin;
    return nil;
}

+ (void)perform:(NSString *)operation completion:(void (^)(BOOL ok, NSString *message))userCompletion {
    void (^completion)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
      userCompletion(ok, ok ? message : SKJITMessageWithAdvice(message, skOnlyCellular()));
    };
    // Without a VPN interface carrying the route the helper can only time out. LocalDevVPN is
    // what provides it, so open it to connect, wait for the user to come back, and carry on.
    // Another VPN's interface passes this check; its case is told from the helper's error.
    if (![operation isEqualToString:@"reset"] && !skRouteIsVPN()) {
        [self connectLocalDevVPNThen:^(NSString *_Nullable problem) {
          if (problem) return completion(NO, problem);
          [self performChecked:operation completion:completion];
        }];
        return;
    }
    [self performChecked:operation completion:completion];
}

/// Opens LocalDevVPN (`enable` connects it; `scheme` has it return here) and calls `then` with nil
/// once traffic to the device routes through a VPN, or with a message when that cannot happen.
+ (void)connectLocalDevVPNThen:(void (^)(NSString *_Nullable problem))then {
    UIApplication *app = UIApplication.sharedApplication;
    if (![app canOpenURL:[NSURL URLWithString:@"localdevvpn://"]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          then(@"LocalDevVPN is not installed. Get it from the App Store, connect it, then try again.");
        });
        return;
    }
    NSString *notRouting = @"LocalDevVPN is not routing to this device's debug service. Connect LocalDevVPN, then try again.";
    // The system's "Open LocalDevVPN?" prompt only makes the app inactive; leaving it for the
    // other app is what counts as going away, and coming back is the cue to carry on.
    __block BOOL left = NO, finished = NO;
    __block id didLeave = nil, willReturn = nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    void (^finish)(NSString *_Nullable) = ^(NSString *_Nullable problem) {
      if (finished) return;
      finished = YES;
      [center removeObserver:didLeave];
      [center removeObserver:willReturn];
      then(problem);
    };
    didLeave = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                   object:nil
                                    queue:NSOperationQueue.mainQueue
                               usingBlock:^(NSNotification *n) {
                                 left = YES;
                               }];
    willReturn = [center addObserverForName:UIApplicationWillEnterForegroundNotification
                                     object:nil
                                      queue:NSOperationQueue.mainQueue
                                 usingBlock:^(NSNotification *n) {
                                   if (!left || finished) return;
                                   skWaitForRoute(10, ^(BOOL routed) {
                                     finish(routed ? nil : notRouting);
                                   });
                                 }];
    [app openURL:[NSURL URLWithString:@"localdevvpn://enable?scheme=skapsule"]
          options:@{}
        completionHandler:^(BOOL success) {
          if (!success) finish(@"Couldn't open LocalDevVPN. Connect it yourself, then try again.");
        }];
    // Nobody came back: do not leave the request hanging.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      finish(notRouting);
    });
}

+ (void)performChecked:(NSString *)operation completion:(void (^)(BOOL ok, NSString *message))completion {
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithObject:operation forKey:@"op"];
    if (![operation isEqualToString:@"reset"]) {
        NSData *pairing = [NSData dataWithContentsOfFile:self.pairingPath];
        if (!pairing) {
            dispatch_async(dispatch_get_main_queue(), ^{
              completion(NO, @"Import a pairing file first.");
            });
            return;
        }
        request[@"pairing"] = pairing;
    }
    if ([operation isEqualToString:@"enable"]) {
        NSString *scriptPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"skapsule-jit.js"];
        NSData *script = [NSData dataWithContentsOfFile:scriptPath];
        if (!script) {
            dispatch_async(dispatch_get_main_queue(), ^{
              completion(NO, @"The bundled JIT script is missing.");
            });
            return;
        }
        request[@"pid"] = @(getpid());
        request[@"script"] = [script base64EncodedStringWithOptions:0];
    }
    [self send:request completion:completion];
}

+ (void)send:(NSDictionary *)request completion:(void (^)(BOOL ok, NSString *message))completion {
    void (^fail)(NSString *) = ^(NSString *message) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO, message);
      });
    };
    // One request at a time: the helper serializes them anyway, and a second attach to the same
    // process can only fail.
    static atomic_bool busy;
    if (atomic_exchange(&busy, true)) return fail(@"The JIT helper is still working. Try again in a moment.");
    void (^failFree)(NSString *) = ^(NSString *message) {
      atomic_store(&busy, false);
      fail(message);
    };
    NSString *identifier = self.helperIdentifier;
    if (!identifier) return failFree(@"This build does not include the JIT helper.");

    Class cls = NSClassFromString(@"NSExtension");
    if (!cls) {
        dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
        cls = NSClassFromString(@"NSExtension");
    }
    if (![cls respondsToSelector:@selector(extensionWithIdentifier:error:)]) {
        return failFree(@"iOS did not provide the extension API the JIT helper needs.");
    }
    NSError *error = nil;
    id<SKExtension> extension = [(Class<SKExtensionClass>)cls extensionWithIdentifier:identifier error:&error];
    if (!extension) {
        return failFree([NSString stringWithFormat:@"The JIT helper could not be found: %@",
                                                   error.localizedDescription ?: @"unknown error"]);
    }

    // The extension object has to outlive its request, and only the first outcome counts.
    static NSMutableSet *running;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      running = [NSMutableSet set];
    });
    __block BOOL finished = NO;
    void (^end)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (finished) return;
        finished = YES;
        atomic_store(&busy, false);
        [running removeObject:extension];
        completion(ok, message);
      });
    };
    dispatch_async(dispatch_get_main_queue(), ^{
      [running addObject:extension];
    });

    [extension setRequestCompletionBlock:^(NSUUID *requestIdentifier, NSArray *items) {
      id item = items.firstObject;
      NSDictionary *reply = [item isKindOfClass:NSExtensionItem.class] ? ((NSExtensionItem *)item).userInfo[@"reply"] : nil;
      if (![reply isKindOfClass:NSDictionary.class]) return end(NO, @"The JIT helper finished without an answer.");
      end([reply[@"ok"] boolValue], [reply[@"message"] isKindOfClass:NSString.class] ? reply[@"message"] : @"");
    }];
    [extension setRequestCancellationBlock:^(NSUUID *requestIdentifier, NSError *cancelError) {
      end(NO, [NSString stringWithFormat:@"The JIT helper stopped: %@",
                                         cancelError.localizedDescription ?: @"the request was cancelled"]);
    }];
    [extension setRequestInterruptionBlock:^(NSUUID *requestIdentifier) {
      end(NO, @"The JIT helper stopped unexpectedly.");
    }];

    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{@"request": request};
    [extension beginExtensionRequestWithInputItems:@[item]
                                        completion:^(NSUUID *requestIdentifier) {
                                          if (!requestIdentifier) end(NO, @"The JIT helper did not start.");
                                        }];
    BOOL isEnable = [request[@"op"] isEqual:@"enable"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHelperTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      // Attached and waiting for the VM to map its code cache is the healthy long case.
      if (isEnable && skDebuggerAttached()) return;
      end(NO, @"The JIT helper did not answer in time. Check that LocalDevVPN is connected, then try again.");
    });
}

+ (void)enableBuiltInWithFailure:(void (^)(NSString *message))failure {
    NSString *reason = self.unavailableReason;
    if (!reason && !self.hasPairingFile) reason = @"Set up a pairing first (JIT Setup in the sidebar).";
    if (reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
          failure(reason);
        });
        return;
    }
    // Reaching the debug service and mounting the disk image takes seconds; a second tap
    // in that window would start a second attach, which can only fail.
    static BOOL enabling;
    if (enabling) return;
    enabling = YES;
    // Completes only once the script detaches, after the JVM has its code cache; success
    // itself is observed through isJITEnabled().
    [self perform:@"enable"
       completion:^(BOOL ok, NSString *message) {
         enabling = NO;
         if (!ok) failure(message);
       }];
}

+ (void)requestJITWithFailure:(void (^)(NSString *message))failure {
    // Only the selected method runs: falling through to the other on failure would hide
    // why the chosen one failed.
    SKJITMethod method = self.resolvedMethod;
    if (method == SKJITMethodTrollStore) {
        // TrollStore opens the app again after it has attached for a moment and let go.
        NSString *url = [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier];
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:url]
                                         options:@{}
                               completionHandler:^(BOOL success) {
                                 if (success) return;
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                   failure(@"TrollStore didn't answer. Install SKapsule through TrollStore and turn on its URL Scheme setting.");
                                 });
                               }];
        return;
    }
    if (method == SKJITMethodJailbreak) {
        if (!isJITEnabled(NO)) {
            dispatch_async(dispatch_get_main_queue(), ^{
              failure(@"Turn on Allow JIT in Apps in your jailbreak's settings, then open SKapsule again.");
            });
        }
        return;
    }
    if (method == SKJITMethodBuiltin) {
        [self enableBuiltInWithFailure:failure];
        return;
    }

    [UIApplication.sharedApplication openURL:skJITEnableURL()
                                     options:@{}
                           completionHandler:^(BOOL success) {
                             if (success) return;
                             dispatch_async(dispatch_get_main_queue(), ^{
                               failure(@"StikDebug isn't installed. Install it with a paired device, or set up "
                                       @"built-in JIT (JIT Setup in the sidebar).");
                             });
                           }];
}

@end
