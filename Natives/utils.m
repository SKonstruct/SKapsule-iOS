#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/mman.h>
#import <mach-o/dyld.h>

#include "utils.h"

BOOL isJailbroken = NO;
BOOL debugLogEnabled = NO;

#define CS_OPS_STATUS   0
#define CS_DEBUGGED     0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

static NSDictionary *_entitlements = nil;

BOOL isJITEnabled(BOOL checkCSFlags) {
    if (checkCSFlags) {
        uint32_t flags;
        csops(0, CS_OPS_STATUS, &flags, sizeof(flags));
        return (flags & CS_DEBUGGED) != 0;
    }
    void *ptr = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
    if (ptr != MAP_FAILED) {
        munmap(ptr, getpagesize());
        return YES;
    }
    return NO;
}

id getEntitlementValue(NSString *key) {
    if (_entitlements) {
        return _entitlements[key];
    }
    return nil;
}

NSString *getSelectedJavaHome(int minVersion) {
    NSString *bundledJRE = [NSString stringWithFormat:@"%@/jre25",
        NSBundle.mainBundle.bundlePath];
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
