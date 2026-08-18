#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <sys/sysctl.h>
#import <unistd.h>

#include "utils.h"

BOOL isJailbroken = NO;
BOOL debugLogEnabled = NO;

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

static NSDictionary *_entitlements = nil;

// --- iOS 26 / Trusted Execution Monitor JIT detection --------------------
// Ported from AngelAuraMC / Amethyst-iOS. On iOS 26 the process can no longer
// create executable pages itself (W^X, enforced in hardware by the TXM on
// A17+/M-series). JIT then requires a debugger (StikJIT) running a script that
// services the VM's brk-based codegen syscalls — see assets/UniversalJIT26.js.

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

JITFlags DeviceGetJITFlags(BOOL refresh) {
    static JITFlags cachedFlags = 0;
    static dispatch_once_t onceToken;
    if (refresh) onceToken = 0;
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
    return (DeviceGetJITFlags(NO) & flags) == flags;
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
    // StikJIT's enable-jit URL only honors bundle-id/pid. On TXM devices the JIT
    // script must be imported into StikJIT and assigned to this app's bundle id
    // (see skStageJITScriptToDocuments) — it can't be passed inline here.
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return [NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d", bundleID,
                                                           getpid()]];
}

NSString *skStageJITScriptToDocuments(void) {
    NSString *src = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs) {
        return nil;
    }
    NSString *dst = [docs stringByAppendingPathComponent:@"UniversalJIT26.js"];
    NSData *data = [NSData dataWithContentsOfFile:src];
    if (!data) {
        NSLog(@"[JIT] Bundled UniversalJIT26.js missing; cannot stage to Documents");
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
    if (_entitlements) {
        return _entitlements[key];
    }
    return nil;
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
