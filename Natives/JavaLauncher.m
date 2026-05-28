// JavaLauncher — boots the embedded JRE 25 to run Spiral Knights via SkBootstrap.
// Phase 0: stub implementation. Phase 1 will implement the full JVM launch.

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "utils.h"
#import "JavaLauncher.h"

#define fm NSFileManager.defaultManager

int launchJVM(NSString *steamUser, NSString *steamPass, BOOL isSteam, int width, int height) {
    NSLog(@"[JavaLauncher] Beginning JVM launch (Phase 0 stub)");

    NSString *javaHome = getSelectedJavaHome(25);
    if (!javaHome) {
        NSLog(@"[JavaLauncher] No JRE 25 found; cannot launch");
        return 1;
    }

    NSLog(@"[JavaLauncher] JAVA_HOME = %@", javaHome);
    NSLog(@"[JavaLauncher] Steam mode = %@, user = %@",
        isSteam ? @"YES" : @"NO",
        steamUser.length > 0 ? steamUser : @"(web)");

    // Phase 1 will:
    // 1. dlopen libjli.dylib from the JRE
    // 2. Set up all JVM options (cacio, frenchpress, getdown paths)
    // 3. Call JLI_Launch to boot SkBootstrap
    NSLog(@"[JavaLauncher] JVM launch not yet implemented — awaiting Phase 1");
    return 0;
}
