#import "SKBuiltinJIT.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <unistd.h>

#import "utils.h"

static NSString *const kSelectedKey = @"jit_builtin_selected";
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

@implementation SKBuiltinJIT

+ (BOOL)selected {
    return [NSUserDefaults.standardUserDefaults boolForKey:kSelectedKey];
}

+ (void)setSelected:(BOOL)selected {
    [NSUserDefaults.standardUserDefaults setBool:selected forKey:kSelectedKey];
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

/// StikJIT documents Documents/StikJIT/pairingFile.plist, which users can fill through
/// Finder; take a file left there into Library.
+ (void)adoptDroppedPairingFile {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dropped = [docs stringByAppendingPathComponent:@"StikJIT/pairingFile.plist"];
    if (![NSFileManager.defaultManager fileExistsAtPath:dropped]) return;
    if (![self importPairingFileFromURL:[NSURL fileURLWithPath:dropped]]) {
        [NSFileManager.defaultManager removeItemAtPath:dropped error:nil];
    }
}

+ (nullable NSString *)importPairingFileFromURL:(NSURL *)url {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSNumber *size = [url resourceValuesForKeys:@[NSURLFileSizeKey] error:nil][NSURLFileSizeKey];
    NSData *data = size.unsignedIntegerValue <= kMaxPairingBytes ? [NSData dataWithContentsOfURL:url] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];

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
    self.selected = YES;
    return nil;
}

+ (void)perform:(NSString *)operation completion:(void (^)(BOOL ok, NSString *message))completion {
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

+ (void)requestJITWithFailure:(void (^)(NSString *message))failure {
    // Only the selected method runs: falling through to the other on failure would hide
    // why the chosen one failed.
    if (self.selected) {
        NSString *reason = self.unavailableReason;
        if (!reason && !self.hasPairingFile) reason = @"Import a pairing file first (JIT Setup in the sidebar).";
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
