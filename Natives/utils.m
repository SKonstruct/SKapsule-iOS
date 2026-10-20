#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <os/proc.h>
#import <sys/sysctl.h>
#import <unistd.h>

#include "utils.h"

BOOL isJailbroken = NO;
BOOL debugLogEnabled = NO;

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

// SecTask lives in Security.framework on iOS but isn't in the public headers. This is the
// same approach Amethyst-iOS uses; the project already relies on comparable API for the
// dyld bypass and ptrace paths.
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement,
                                                CFErrorRef *error);

static NSMutableDictionary *_entitlements = nil;

// --- iOS 26 / Trusted Execution Monitor JIT detection --------------------
// Ported from AngelAuraMC / Amethyst-iOS. On iOS 26 the process can no longer
// create executable pages itself (W^X, enforced in hardware by the TXM on
// A17+/M-series). JIT then requires a debugger (StikJIT) running a script that
// services the VM's brk-based codegen syscalls — see assets/skapsule-jit.js.

// Can this process turn writable memory into executable memory on its own?
static BOOL DeviceCanCreateRXMap(void) {
    uint32_t *map = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0);
    if (map == MAP_FAILED) {
        return NO;
    }
    *map = 0xFFFFFFFF;
    int ret = mprotect(map, getpagesize(), PROT_READ | PROT_EXEC);
    munmap(map, getpagesize());
    return ret == 0;
}

// Deterministically detect a Trusted Execution Monitor by looking for its
// firmware image under /private/preboot; fall back to chip-ID heuristics.
static BOOL DeviceHasTXMReal(void) {
    DIR *d = opendir("/private/preboot");
    if (!d) {
        NSUInteger (*MGGetSInt64Answer)(NSString *) = dlsym(RTLD_DEFAULT, "MGGetSInt64Answer");
        if (!MGGetSInt64Answer) {
            if (@available(iOS 19.0, *)) return YES;
            return NO;
        }
        NSUInteger chipID = MGGetSInt64Answer(@"ChipID");
        switch (chipID) {
            case 0x8020:  // A12
            case 0x8027:  // A12X/Z
                return NO;
            case 0x8030:  // A13
            case 0x8101:  // A14
            case 0x8103:  // M1
                if (@available(iOS 27.0, *)) return YES;
                return NO;
            default:
                if (@available(iOS 19.0, *)) return YES;
                return NO;
        }
    }
    struct dirent *dir;
    char txmPath[PATH_MAX] = {0};
    while ((dir = readdir(d)) != NULL) {
        if (strlen(dir->d_name) == 96) {
            snprintf(txmPath, sizeof(txmPath),
                     "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
            break;
        }
    }
    closedir(d);
    return txmPath[0] != '\0' && access(txmPath, F_OK) == 0;
}

JITFlags DeviceGetJITFlags(void) {
    static JITFlags cachedFlags = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      const char *override = getenv("JIT_FLAGS");
      if (override) {
          cachedFlags = (JITFlags)strtoul(override, NULL, 0);
          NSLog(@"[JIT] Using overridden JIT flags: 0x%X", cachedFlags);
          return;
      }
      cachedFlags = 0;
      if (@available(iOS 26.0, *)) {
          cachedFlags |= JIT_FLAG_IS_IOS_26;
          if (!DeviceCanCreateRXMap()) {
              cachedFlags |= JIT_FLAG_FORCE_MIRRORED;
          }
      }
      if (DeviceHasTXMReal()) {
          cachedFlags |= JIT_FLAG_HAS_TXM;
      }
      NSLog(@"[JIT] Computed JIT flags: 0x%X", cachedFlags);
    });
    return cachedFlags;
}

BOOL DeviceHasJITFlags(JITFlags flags) {
    return (DeviceGetJITFlags() & flags) == flags;
}

// Exported (default visibility) so the AngelAuraMC libjvm can dlsym this to
// decide whether to use its TXM/mirror-mapped codegen path.
__attribute__((visibility("default"))) BOOL DeviceHasTXM(void) {
    return DeviceHasJITFlags(JIT_FLAG_HAS_TXM);
}

BOOL JIT26IsLikelyDebuggerKeepAttached(void) {
    // getppid() is launchd (1) unless a debugger (StikDebug) is actively attached.
    return getppid() != 1;
}

NSURL *skJITEnableURL(void) {
    NSURLComponents *url = [NSURLComponents componentsWithString:@"stikjit://enable-jit"];
    NSMutableArray<NSURLQueryItem *> *query = [NSMutableArray arrayWithObjects:
        [NSURLQueryItem queryItemWithName:@"bundle-id" value:NSBundle.mainBundle.bundleIdentifier ?: @""],
        [NSURLQueryItem queryItemWithName:@"pid" value:@(getpid()).stringValue], nil];
    // StikDebug runs a script handed over inline, so nothing has to be imported or assigned
    // to this app first; builds that predate script-data ignore it and use the script
    // assigned to the bundle id. Without a TXM, an attached debugger alone is enough, and
    // StikJIT's guide says to send no script then.
    NSString *scriptPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"skapsule-jit.js"];
    NSData *script = DeviceHasTXM() ? [NSData dataWithContentsOfFile:scriptPath] : nil;
    if (script) {
        // base64url, which StikDebug converts back; plain base64's '+' would arrive as a space.
        NSString *encoded = [[[[script base64EncodedStringWithOptions:0]
            stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
            stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
            stringByReplacingOccurrencesOfString:@"=" withString:@""];
        [query addObject:[NSURLQueryItem queryItemWithName:@"script-data" value:encoded]];
    }
    url.queryItems = query;
    return url.URL;
}

NSString *skStageJITScriptToDocuments(void) {
    NSString *src = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"skapsule-jit.js"];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs) {
        return nil;
    }
    NSString *dst = [docs stringByAppendingPathComponent:@"skapsule-jit.js"];
    // The script used to ship as UniversalJIT26.js; drop the stale copy so Files does not
    // offer two scripts to import, only one of which we keep up to date.
    [NSFileManager.defaultManager removeItemAtPath:[docs stringByAppendingPathComponent:@"UniversalJIT26.js"]
                                             error:nil];
    NSData *data = [NSData dataWithContentsOfFile:src];
    if (!data) {
        NSLog(@"[JIT] Bundled skapsule-jit.js missing; cannot stage to Documents");
        return nil;
    }
    [data writeToFile:dst atomically:YES];  // overwrite each launch so updates propagate
    NSLog(@"[JIT] Staged JIT script for StikJIT import: %@", dst);
    return dst;
}

BOOL isJITEnabled(BOOL checkCSFlags) {
    (void)checkCSFlags;
    uint32_t flags = 0;
    csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
    if ((flags & CS_DEBUGGED) == 0) {
        return NO;
    }
    // Pre-iOS-26 / non-TXM: an attached debugger (CS_DEBUGGED) is sufficient.
    if (!DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
        return YES;
    }
    // iOS 26 TXM: JIT works only while the debugger running the JIT script stays
    // attached to service the VM's brk-based codegen syscalls.
    return JIT26IsLikelyDebuggerKeepAttached();
}

id getEntitlementValue(NSString *key) {
    // Was previously a lookup into a dictionary nothing ever populated, so it always
    // returned nil -- which silently disabled the TrollStore PT_TRACE_ME JIT path in
    // main.m and pinned -XX:-UseCompressedClassPointers on in JavaLauncher.m.
    if (!key) return nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      _entitlements = [NSMutableDictionary dictionary];
    });

    @synchronized(_entitlements) {
        id cached = _entitlements[key];
        if (cached) return (cached == NSNull.null) ? nil : cached;

        id value = nil;
        SecTaskRef task = SecTaskCreateFromSelf(NULL);
        if (task) {
            CFTypeRef raw = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef)key, NULL);
            if (raw) {
                value = CFBridgingRelease(raw);
            }
            CFRelease(task);
        }
        // Negative results are cached too: an unsigned/unentitled build would otherwise
        // pay for the lookup on every call.
        _entitlements[key] = value ?: NSNull.null;
        return value;
    }
}

NSString *getSelectedJavaHome(int minVersion) {
    NSString *bundledJRE = [NSString stringWithFormat:@"%@/jre25", [[NSBundle mainBundle] bundlePath]];
    if ([NSFileManager.defaultManager fileExistsAtPath:bundledJRE]) {
        return bundledJRE;
    }

    const char *home = getenv("SKAPSULE_HOME");
    if (home) {
        NSString *extractedJRE = [NSString stringWithFormat:@"%s/jre25", home];
        if ([NSFileManager.defaultManager fileExistsAtPath:extractedJRE]) {
            return extractedJRE;
        }
    }

    NSLog(@"[Utils] No JRE 25 found for iOS");
    return nil;
}

// --- Java heap cap ------------------------------------------------------------

static NSString *const kMaxRamKey = @"max_ram_mb";

int sk_ram_max_mb(void) {
    int half = (int)((NSProcessInfo.processInfo.physicalMemory >> 20) / 2);
    int stepped = half / SK_RAM_STEP_MB * SK_RAM_STEP_MB;
    if (stepped < SK_RAM_MIN_MB) return SK_RAM_MIN_MB;
    if (stepped > 4096) return 4096;
    return stepped;
}

int sk_ram_available_mb(void) {
    // os_proc_available_memory is what actually bounds us: the app's remaining jetsam
    // allowance, not the device's free page count.
    size_t available = os_proc_available_memory();
    if (available > 0) return (int)(available >> 20);
    return (int)(NSProcessInfo.processInfo.physicalMemory >> 20);
}

int sk_ram_total_mb(void) {
    return (int)(NSProcessInfo.processInfo.physicalMemory >> 20);
}

int sk_ram_get_mb(void) {
    id val = [NSUserDefaults.standardUserDefaults objectForKey:kMaxRamKey];
    int mb = val ? [val intValue] : SK_RAM_DEFAULT_MB;
    int max = sk_ram_max_mb();
    if (mb < SK_RAM_MIN_MB) mb = SK_RAM_MIN_MB;
    if (mb > max) mb = max;
    return mb;
}

void sk_ram_set_mb(int mb) {
    int max = sk_ram_max_mb();
    if (mb < SK_RAM_MIN_MB) mb = SK_RAM_MIN_MB;
    if (mb > max) mb = max;
    [NSUserDefaults.standardUserDefaults setInteger:mb forKey:kMaxRamKey];
}

UIEdgeInsets SKGameSafeAreaInsets(UIView *view) {
    // Along an edge's middle the display curve clips nothing -- only the corners do -- so
    // the long edges can be inset far less than the short ones. 8pt on the sides matches
    // what looks right on device; 2pt top and bottom keeps the corners from eating HUD
    // while reclaiming the strip that was going to waste.
    static const CGFloat kSideAllowance = 8.0f;
    static const CGFloat kEndAllowance = 2.0f;

    // UIKit's inset on the sensor-housing side clears the housing *and* adds its own
    // margin, which shows up as a visible gap between the Dynamic Island and the game.
    // That margin is ~11pt on Island devices (portrait: island ends ~48pt down, safe area
    // is 59pt). Give it back. Clamped so a device with a smaller inset can't go negative.
    static const CGFloat kHousingMargin = 11.0f;

    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *))
        insets = view.safeAreaInsets;

    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    if (@available(iOS 13.0, *))
        orientation = view.window.windowScene.interfaceOrientation;

    // UIInterfaceOrientation is defined against the *device* orientation it corresponds to,
    // which inverts the reading its name suggests: LandscapeRight == UIDeviceOrientation-
    // LandscapeLeft == home-button edge on the right, so the top of the device -- and with
    // it the sensor housing -- is on the LEFT. Confirmed on device; getting this backwards
    // paints the game under the Dynamic Island, which is the whole thing this avoids.
    CGFloat housing = MAX(MAX(insets.left, insets.right) - kHousingMargin, 0.0f);
    CGFloat left = kSideAllowance, right = kSideAllowance;
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        left = housing;
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        right = housing;
    } else {
        // Orientation not known yet (first layout pass): keep both sides clear rather than
        // guessing wrong and painting under the island.
        left = right = housing;
    }

    return UIEdgeInsetsMake(MAX(insets.top, kEndAllowance), left, kEndAllowance, right);
}
