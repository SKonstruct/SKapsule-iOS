// JavaLauncher — boots the embedded JRE 25 to run Spiral Knights via SkBootstrap.
// Translates sklauncher.c's JVM args to JLI_Launch for iOS.

#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "utils.h"
#import "JavaLauncher.h"
#import "NativeBridge.h"

#define fm NSFileManager.defaultManager

JLI_Launch_func *pJLI_Launch = NULL;

static void init_loadSKEnv(void) {
    // GL4ES environment
    setenv("LD_LIBRARY_PATH", "", 1);
    setenv("LIBGL_NOINTOVLHACK", "1", 1);
    setenv("LIBGL_NORMALIZE", "1", 1);

    // Run JVM on its own thread (iOS requires main thread for UI)
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
}

int launchJVM(NSString *steamUser, NSString *steamPass, BOOL isSteam, int width, int height) {
    NSLog(@"[JavaLauncher] Beginning JVM launch");

    init_loadSKEnv();

    // The JRE and native libraries are now properly codesigned at build-time.
    // Dyld validation bypass is no longer required and corrupts dyld4 memory on iOS 17.

    NSString *javaHome = getSelectedJavaHome(25);
    if (!javaHome) {
        NSLog(@"[JavaLauncher] No JRE 25 found; cannot launch");
        [SKNativeBridge onLaunchStatus:@"Error: JRE 25 not found"];
        return 1;
    }

    setenv("JAVA_HOME", javaHome.UTF8String, 1);
    NSLog(@"[JavaLauncher] JAVA_HOME = %@", javaHome);

    const char *home = getenv("SKAPSULE_HOME");
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;

    // Load JLI
    NSString *libjliPath = [NSString stringWithFormat:@"%@/lib/libjli.dylib", javaHome];
    setenv("INTERNAL_JLI_PATH", libjliPath.UTF8String, 1);

    [SKNativeBridge onLaunchStatus:@"Loading JVM…"];
    void *libjli = dlopen(libjliPath.UTF8String, RTLD_GLOBAL);
    if (!libjli) {
        const char *err = dlerror();
        NSLog(@"[JavaLauncher] dlopen libjli failed: %s", err);
        [SKNativeBridge onLaunchStatus:[NSString stringWithFormat:@"JVM load failed: %s", err]];
        return 1;
    }

    pJLI_Launch = (JLI_Launch_func *)dlsym(libjli, "JLI_Launch");
    if (!pJLI_Launch) {
        NSLog(@"[JavaLauncher] JLI_Launch symbol not found");
        [SKNativeBridge onLaunchStatus:@"JLI_Launch not found in JRE"];
        return 1;
    }

    // Build JVM args — translated from sklauncher.c
    int margc = -1;
    const char *margv[200];

    margv[++margc] = [NSString stringWithFormat:@"%@/bin/java", javaHome].UTF8String;

    // Memory: auto-allocate 25% of physical RAM (no increased-memory entitlement assumed)
    int allocMB = (int)((NSProcessInfo.processInfo.physicalMemory >> 20) * 0.25);
    if (allocMB < 256) allocMB = 256;
    if (allocMB > 2048) allocMB = 2048;
    NSLog(@"[JavaLauncher] Max RAM: %d MB", allocMB);
    margv[++margc] = "-Xms128M";
    margv[++margc] = [NSString stringWithFormat:@"-Xmx%dM", allocMB].UTF8String;

    // Paths — match sklauncher.c layout
    margv[++margc] = [NSString stringWithFormat:@"-Djava.library.path=%@/Frameworks", bundlePath].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Dappdir=%s/sk", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Dresource_dir=%s/sk/rsrc", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Dcrucible.dir=%s/sk/crucible", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Djava.io.tmpdir=%s/sk/tmp", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.home=%s/home", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Djava.util.prefs.userRoot=%s/home/.userPrefs", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Djava.util.prefs.systemRoot=%s/home/.systemPrefs", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.dir=%s/sk", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.timezone=%@", NSTimeZone.localTimeZone.name].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-DUIScreen.maximumFramesPerSecond=%d",
        (int)UIScreen.mainScreen.maximumFramesPerSecond].UTF8String;

    // LWJGL / OpenGL
    margv[++margc] = "-Dorg.lwjgl.glfw.checkThread0=false";
    margv[++margc] = "-Dorg.lwjgl.system.allocator=system";
    margv[++margc] = "-Dorg.lwjgl.util.NoChecks=true";
    margv[++margc] = [NSString stringWithFormat:@"-Dorg.lwjgl.opengl.libname=%@/Frameworks/libgl4es.dylib",
        bundlePath].UTF8String;

    // SK-specific
    margv[++margc] = "-Dcom.threerings.froth.disable_steam_api=true";
    margv[++margc] = "-Dno_log_redir=true";
    margv[++margc] = "-Dsilent=launch";

    // Frenchpress (Steam login)
    NSString *frenchpressJar = [NSString stringWithFormat:@"%s/frenchpress/frenchpress.jar", home];
    if (isSteam && [fm fileExistsAtPath:frenchpressJar]) {
        margv[++margc] = [NSString stringWithFormat:@"-Dfrenchpress.jar=%@", frenchpressJar].UTF8String;
        margv[++margc] = "-Dfrenchpress.credentialPrompt=com.skarm.launcher.bootstrap.NativeBridgePrompt";

        if (steamUser.length > 0) {
            setenv("FRENCHPRESS_STEAM_USER", steamUser.UTF8String, 1);
        }
        if (steamPass.length > 0) {
            setenv("FRENCHPRESS_STEAM_PASS", steamPass.UTF8String, 1);
        }

        NSString *credFile = [NSString stringWithFormat:@"%s/home/.local/share/frenchpress/steam.creds", home];
        setenv("FRENCHPRESS_CRED_FILE", credFile.UTF8String, 1);
        // Ensure cred directory exists
        [fm createDirectoryAtPath:[credFile stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Module opens/exports for LWJGL + cacio
    margv[++margc] = "--add-opens=java.base/java.lang=ALL-UNNAMED";
    margv[++margc] = "--add-opens=java.base/java.util=ALL-UNNAMED";
    margv[++margc] = "--enable-native-access=ALL-UNNAMED";

    // HotSpot options
    margv[++margc] = "-XX:-CreateCoredumpOnCrash";
    margv[++margc] = "-XX:+SuppressFatalErrorMessage";
    margv[++margc] = "-XX:+UnlockExperimentalVMOptions";
    margv[++margc] = "-XX:+DisablePrimordialThreadGuardPages";

    // Caciocavallo AWT bridge
    NSString *cacioDir = [NSString stringWithFormat:@"%s/cacio", home];
    if ([fm fileExistsAtPath:cacioDir]) {
        NSString *cacioBootcp = [NSString stringWithFormat:@"-Xbootclasspath/a:%@/cacio-shared.jar:%@/cacio-tta.jar",
            cacioDir, cacioDir];
        margv[++margc] = cacioBootcp.UTF8String;
        margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/cacio-tta.jar", cacioDir].UTF8String;
        margv[++margc] = "-Djava.awt.headless=false";
        margv[++margc] = "-Dawt.toolkit=com.github.caciocavallosilano.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=com.github.caciocavallosilano.cacio.ctc.CTCGraphicsEnvironment";
        int sw = width > 0 ? width : 1280;
        int sh = height > 0 ? height : 720;
        margv[++margc] = [NSString stringWithFormat:@"-Dcacio.managed.screensize=%dx%d", sw, sh].UTF8String;
        margv[++margc] = "-Dcacio.font.fontmanager=sun.awt.X11FontManager";
        margv[++margc] = "-Dcacio.font.fontscaler=sun.font.FreetypeFontScaler";

        // Module exports for cacio
        margv[++margc] = "--add-exports=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.peer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.image=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.event=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.datatransfer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.java2d.pipe=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.font=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.dnd.peer=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.font=ALL-UNNAMED";

        NSLog(@"[JavaLauncher] cacio AWT bridge enabled (dir=%@)", cacioDir);
    }

    // Classpath: bootstrap + getdown JARs
    NSString *libsPath = [NSString stringWithFormat:@"%@/libs", bundlePath];
    NSString *classpath = [NSString stringWithFormat:@"%@/*", libsPath];
    margv[++margc] = "-cp";
    margv[++margc] = classpath.UTF8String;

    // Main class: SkBootstrap
    margv[++margc] = "com.skarm.launcher.bootstrap.SkBootstrap";

    // SkBootstrap args: appdir
    margv[++margc] = [NSString stringWithFormat:@"%s/sk", home].UTF8String;

    NSLog(@"[JavaLauncher] JLI_Launch with %d args", margc + 1);
    for (int i = 0; i <= margc; i++) {
        NSLog(@"[JavaLauncher]   argv[%d] = %s", i, margv[i]);
    }

    // Reset signal handlers before handing control to the JVM
    signal(SIGSEGV, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGFPE, SIG_DFL);

    [SKNativeBridge onLaunchStatus:@"Launching Spiral Knights…"];

    return pJLI_Launch(++margc, margv,
        0, NULL,
        0, NULL,
        "25-internal",
        "25",
        "java", "openjdk",
        0,  // javaargs
        1,  // cpwildcard
        0,  // javaw
        1); // ergo
}
