// JavaLauncher — boots the embedded JRE 25 to run Spiral Knights via SkBootstrap.
// Translates sklauncher.c's JVM args to JLI_Launch for iOS.

#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#import <mach-o/dyld.h>
#include "utils.h"

#include <dlfcn.h>
#include <pthread.h>
#import "JavaLauncher.h"
#import "NativeBridge.h"
#include "jni.h"

extern void register_glfw_natives(JNIEnv *env, jclass glfwClass);
void register_sk_natives_if_needed(void);

#define fm NSFileManager.defaultManager

JLI_Launch_func *pJLI_Launch = NULL;

static void init_loadSKEnv(void) {
    // GL4ES environment
    setenv("LD_LIBRARY_PATH", "", 1);
    setenv("LIBGL_NOINTOVLHACK", "1", 1);
    setenv("LIBGL_NORMALIZE", "1", 1);

    // Run JVM on its own thread (iOS requires main thread for UI)
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);

    // iOS 26+ Trusted Execution Monitor. The AngelAuraMC libjvm probes for TXM by
    // dlsym'ing DeviceHasTXM() from the host app (exported in utils.m) and, failing
    // that, reading XNU_HAS_TXM. We set the env var too as a belt-and-suspenders
    // fallback so the VM takes its mirror-mapped codegen path on real TXM devices.
    if (DeviceHasJITFlags(JIT_FLAG_HAS_TXM)) {
        setenv("XNU_HAS_TXM", "1", 1);
    }
}

int launchJVM(NSString *steamUser, NSString *steamPass, BOOL isSteam, int width, int height) {
    NSLog(@"[JavaLauncher] Beginning JVM launch");

    init_loadSKEnv();

    // The JRE and native libraries are now properly codesigned at build-time.
    // Dyld validation bypass is no longer required and corrupts dyld4 memory on iOS 17.

    NSString *javaHome = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"jre25"];
    if (![fm fileExistsAtPath:[javaHome stringByAppendingPathComponent:@"lib/libjli.dylib"]]) {
        NSLog(@"[JavaLauncher] No JRE found in bundle; cannot launch");
        [SKNativeBridge onLaunchStatus:@"Error: JRE not found"];
        return 1;
    }

    setenv("JAVA_HOME", javaHome.UTF8String, 1);
    NSLog(@"[JavaLauncher] JAVA_HOME = %@", javaHome);
    // What the VM needs to start is <java.home>/lib/modules; log what is actually installed,
    // since a signing service can alter the bundle and an early VM failure leaves no other trace.
    for (NSString *rel in @[ @"lib/modules", @"lib/libjimage.dylib", @"lib/server/libjvm.dylib" ]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:[javaHome stringByAppendingPathComponent:rel] error:nil];
        NSLog(@"[JavaLauncher] %@: %@", rel,
              attrs ? [NSString stringWithFormat:@"%llu bytes, %@", [attrs fileSize], attrs[NSFileType]] : @"MISSING");
    }

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

    // Register SkBootstrap JNI natives on a background thread once the VM is up.
    // main() no longer parks the libjli re-entry (it forwards into JLI_Launch), so
    // registration can't happen there anymore.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      register_sk_natives_if_needed();
    });

    // Build JVM args — translated from sklauncher.c
    int margc = -1;
    const char *margv[200];

    margv[++margc] = [NSString stringWithFormat:@"%@/bin/java", javaHome].UTF8String;

    int allocMB = sk_ram_get_mb();
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
    margv[++margc] = @"-Djava.util.prefs.PreferencesFactory=java.util.prefs.FileSystemPreferencesFactory".UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.dir=%s/sk", home].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.timezone=%@", NSTimeZone.localTimeZone.name].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-DUIScreen.maximumFramesPerSecond=%d",
                                                (int)UIScreen.mainScreen.maximumFramesPerSecond]
                         .UTF8String;

    // LWJGL / OpenGL
    margv[++margc] = "-Dorg.lwjgl.glfw.checkThread0=false";
    margv[++margc] = "-Dorg.lwjgl.system.allocator=system";
    margv[++margc] =
        [NSString stringWithFormat:@"-Dorg.lwjgl.system.SharedLibraryExtractPath=%@/Frameworks", bundlePath].UTF8String;
    margv[++margc] = "-Dorg.lwjgl.util.NoChecks=true";

    // SK-specific
    margv[++margc] = "-Dcom.threerings.froth.disable_steam_api=true";
    margv[++margc] = "-Dno_log_redir=true";
    // Re-drives getdown's resource unpack from unpacked.dat rather than depending on the
    // one-time side effect at install; without it a wiped sk/rsrc is never repopulated.
    margv[++margc] = "-Dcheck_unpacked=true";
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
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:nil];
    }

    // Module opens/exports for LWJGL + cacio
    margv[++margc] = "--add-opens=java.base/java.lang=ALL-UNNAMED";
    margv[++margc] = "--add-opens=java.base/java.util=ALL-UNNAMED";
    margv[++margc] = "--enable-native-access=ALL-UNNAMED";

    // HotSpot options
    // NOTE: -XstartOnFirstThread is intentionally NOT passed. On this JIT JRE it
    // drives the macOS launcher's first-thread marshaling; SK's GL runs off the
    // main thread (org.lwjgl.glfw.checkThread0=false), and the libjli main()
    // re-entry is forwarded back into JLI_Launch (see main.m) rather than parked.
    margv[++margc] = "-XX:-CreateCoredumpOnCrash";
    // Write the HotSpot crash report into SKAPSULE_HOME (Documents) so it can be
    // retrieved via Files / Share Logs — the default lands in the container tmp,
    // which isn't user-accessible.
    margv[++margc] = [NSString stringWithFormat:@"-XX:ErrorFile=%s/hs_err_pid%%p.log", home].UTF8String;
    // The VM's own output, written straight to a file. A failure during VM init prints its
    // reason and then _exit()s before main.m's pipe reader can copy it to latestlog.txt, so
    // that log only ever showed "Error occurred during initialization of VM".
    margv[++margc] = "-XX:+UnlockDiagnosticVMOptions";
    margv[++margc] = "-XX:+LogVMOutput";
    margv[++margc] = [NSString stringWithFormat:@"-XX:LogFile=%s/vmout-%%p.log", home].UTF8String;
    // NMT brackets every os::malloc with canaries and validates them on free. The
    // 2026-08-19 12:14 crash tripped over a corrupted free block from inside a JVM
    // os::malloc, so a stray write into JVM C-heap gets caught here with the block's own
    // allocation site instead of taking down a random later victim.
    margv[++margc] = "-XX:NativeMemoryTracking=summary";
    // The JIT mapping is sized from this, and StikDebug maps the whole thing RW+RX as
    // file-backed memory -- so every code-cache write is counted against iOS's daily
    // disk-write allowance. The app was dirtying 1073 MB in 66s and tripping the cap
    // (which throttles it) while vmlog reported max_used=15MB. 64M is 4x observed peak.
    margv[++margc] = "-XX:ReservedCodeCacheSize=64M";
    margv[++margc] = "-XX:+UnlockExperimentalVMOptions";
    margv[++margc] = "-XX:+DisablePrimordialThreadGuardPages";
    // SerialGC, matching KnightLauncher's default for this same game (it exposes
    // G1/Parallel/ZGC only as opt-in). Two reasons:
    //  1. G1 crashed on this JRE when entering Haven — SIGSEGV on a GC worker in
    //     G1CodeRootSetHashTable::bulk_remove, walking a corrupt bucket chain in the
    //     per-region nmethod table. That path is only reached from
    //     unload_classes_and_code -> bulk_unregister_nmethods, which G1 runs after
    //     unloading LambdaForm hidden classes during zone load. Serial/Parallel have
    //     no G1CodeRootSet at all (nmethods live on one global ScavengableNMethods
    //     list), so those frames cannot execute. Class unloading still works, so the
    //     code cache and metaspace are still reclaimed.
    //  2. SK's live set is small (~200MB in Haven), which is what Serial suits.
    margv[++margc] = "-XX:+UseSerialGC";
    // Also from KnightLauncher. SK holds textures/models behind soft references and
    // the default (1000 ms per MB of free heap) retains them far too long for a phone.
    margv[++margc] = "-XX:SoftRefLRUPolicyMSPerMB=10";
    // GC / class-unload / code-cache log next to the hs_err file, so Share Logs picks
    // it up. Cheap, and it is how we confirm the GC change above behaves on-device.
    margv[++margc] = [NSString stringWithFormat:@"-Xlog:gc,class+unload=info,codecache=info:file=%s/vmlog-%%p.log:uptime,level,tags:filecount=3,filesize=4M", home].UTF8String;
    // iOS 26+ Trusted Execution Monitor forbids plain RWX JIT pages. This JRE
    // build's mirror-mapped CodeCache (separate RW-write / RX-execute views of the
    // same physical pages) is the W^X-compliant path it needs. Matches Amethyst-iOS.
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26) {
        margv[++margc] = "-XX:+MirrorMappedCodeCache";
    }
    // UseCompressedClassPointers is broken on Java 25 in a jailed iOS address
    // space: without the extended-virtual-addressing entitlement the compressed
    // class space lands too high to encode with shift 0 and the VM aborts at
    // compressedKlass.cpp. Disable it unless that entitlement is present. Matches
    // Amethyst-iOS.
    if (!getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")) {
        margv[++margc] = "-XX:-UseCompressedClassPointers";
    }
    // -XX:+SuppressFatalErrorMessage intentionally omitted while bringing up the
    // JIT VM so HotSpot's crash report reaches the console. Re-add once stable.

    // Caciocavallo AWT bridge
    NSString *cacioDir = [NSString stringWithFormat:@"%s/cacio", home];
    if ([fm fileExistsAtPath:cacioDir]) {
        NSString *cacioBootcp =
            [NSString stringWithFormat:@"-Xbootclasspath/a:%@/cacio-shared.jar:%@/cacio-tta.jar", cacioDir, cacioDir];
        margv[++margc] = cacioBootcp.UTF8String;
        margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/cacio-tta.jar", cacioDir].UTF8String;
        margv[++margc] = "-Djava.awt.headless=false";
        margv[++margc] = "-Dawt.toolkit=com.github.caciocavallosilano.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=com.github.caciocavallosilano.cacio.ctc.CTCGraphicsEnvironment";
        int sw = width > 0 ? width : 1280;
        int sh = height > 0 ? height : 720;
        margv[++margc] = [NSString stringWithFormat:@"-Dcacio.managed.screensize=%dx%d", sw, sh].UTF8String;
        // Force the use of cacio's custom CTCFontManager instead of macOS default CFontManager
        margv[++margc] = "-Dsun.font.fontmanager=com.github.caciocavallosilano.cacio.ctc.CTCFontManager";
        margv[++margc] = "-Dcacio.font.fontmanager=com.github.caciocavallosilano.cacio.ctc.CTCFontManager";
        margv[++margc] = "-Dcacio.font.fontscaler=sun.font.FreetypeFontScaler";
        margv[++margc] = [NSString stringWithFormat:@"-Dsun.java2d.fontpath=%@/jre25/lib/fonts", bundlePath].UTF8String;
    // JDK 25's text shaping defaults to an FFM HarfBuzz binding (sun.font.HBShaper) whose static
    // initialiser builds upcall stubs, and those crash this mirror-mapped code cache (SIGBUS in
    // CodeBlob::CodeBlob from UpcallStub::create). false selects the older JNI path, which
    // libfontmanager still exports (Java_sun_font_SunLayoutEngine_shape) and which needs none.
    margv[++margc] = "-Dsun.font.layout.ffm=false";

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

    // Set LWJGL library paths for OpenGL (gl4es) and OpenAL
    margv[++margc] =
        [NSString stringWithFormat:@"-Dorg.lwjgl.opengl.libname=%@/Frameworks/libgl4es.dylib", bundlePath].UTF8String;
    margv[++margc] =
        [NSString stringWithFormat:@"-Dorg.lwjgl.openal.libname=%@/Frameworks/libopenal.dylib", bundlePath].UTF8String;
    setenv("BUNDLE_PATH", bundlePath.UTF8String, 1);

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

    return pJLI_Launch(++margc, margv, 0, NULL, 0, NULL, "25-internal", "25", "java", "openjdk",
                       0,   // javaargs
                       1,   // cpwildcard
                       0,   // javaw
                       1);  // ergo
}


JNIEXPORT void JNICALL Java_com_skarm_launcher_bootstrap_SkBootstrap_nativeLaunchStatus(JNIEnv *env, jclass clazz,
                                                                                        jstring status_text) {
    const char *text = (*env)->GetStringUTFChars(env, status_text, NULL);
    if (text != NULL) {
        NSString *nsText = [NSString stringWithUTF8String:text];
        [SKNativeBridge onLaunchStatus:nsText];
        (*env)->ReleaseStringUTFChars(env, status_text, text);
    }
}

JNIEXPORT void JNICALL Java_com_skarm_launcher_bootstrap_SkBootstrap_nativeSteamKeepAlive(JNIEnv *env, jclass clazz,
                                                                                          jboolean active) {
    // iOS doesn't strictly need a keep-alive foreground service like Android, but we stub it here
    // so frenchpress doesn't crash.
}

JNIEXPORT jstring JNICALL Java_com_skarm_launcher_bootstrap_SkBootstrap_nativePromptDeviceCode(JNIEnv *env,
                                                                                               jclass clazz,
                                                                                               jboolean prev_wrong) {
    NSString *code = [SKNativeBridge promptForDeviceCode:(BOOL)prev_wrong];
    return (*env)->NewStringUTF(env, code.UTF8String ?: "");
}

JNIEXPORT jstring JNICALL Java_com_skarm_launcher_bootstrap_SkBootstrap_nativePromptEmailCode(JNIEnv *env, jclass clazz,
                                                                                              jstring email_str,
                                                                                              jboolean prev_wrong) {
    NSString *email = @"";
    if (email_str != NULL) {
        const char *email_c = (*env)->GetStringUTFChars(env, email_str, NULL);
        if (email_c != NULL) {
            email = [NSString stringWithUTF8String:email_c];
            (*env)->ReleaseStringUTFChars(env, email_str, email_c);
        }
    }
    NSString *code = [SKNativeBridge promptForEmailCode:email prevWrong:(BOOL)prev_wrong];
    return (*env)->NewStringUTF(env, code.UTF8String ?: "");
}

JNIEXPORT void JNICALL Java_com_skarm_launcher_bootstrap_SkBootstrap_registerGlfwNatives(JNIEnv *env, jclass clazz,
                                                                                         jclass glfwClass) {
    extern void register_glfw_natives(JNIEnv * env, jclass glfwClass);
    register_glfw_natives(env, glfwClass);
}

void register_sk_natives_if_needed(void) {
    static BOOL registered = NO;
    if (registered)
        return;

    typedef jint (*JNI_GetCreatedJavaVMs_func)(JavaVM **, jsize, jsize *);
    JNI_GetCreatedJavaVMs_func getVMs = NULL;

    // Poll until libjvm is loaded and JNI_GetCreatedJavaVMs is available. Bounded so a
    // JVM that never comes up fails loudly here instead of spinning this thread forever.
    const int kPollIntervalUs = 10000;
    const int kMaxPolls = 120 * (1000000 / kPollIntervalUs);  // 120 s
    int polls = 0;
    while (!getVMs) {
        getVMs = (JNI_GetCreatedJavaVMs_func)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
        if (!getVMs) {
            if (++polls > kMaxPolls) {
                NSLog(@"[JavaLauncher] Timed out waiting for libjvm; natives not registered");
                return;
            }
            usleep(kPollIntervalUs);
        }
    }

    JavaVM *jvm = NULL;
    jsize count = 0;

    // Poll until JVM is fully created
    polls = 0;
    while (count == 0 || jvm == NULL) {
        getVMs(&jvm, 1, &count);
        if (count == 0 || jvm == NULL) {
            if (++polls > kMaxPolls) {
                NSLog(@"[JavaLauncher] Timed out waiting for the JVM; natives not registered");
                return;
            }
            usleep(kPollIntervalUs);
        }
    }

    JNIEnv *env = NULL;
    if ((*jvm)->AttachCurrentThread(jvm, &env, NULL) != JNI_OK) {
        NSLog(@"[JavaLauncher] Failed to attach thread for JNI registration");
        return;
    }

    if (env) {
        jclass cls = NULL;
        // Poll until SkBootstrap is loaded by the classloader
        polls = 0;
        while (!cls) {
            cls = (*env)->FindClass(env, "com/skarm/launcher/bootstrap/SkBootstrap");
            if (!cls) {
                (*env)->ExceptionClear(env);
                if (++polls > kMaxPolls) {
                    NSLog(@"[JavaLauncher] Timed out waiting for SkBootstrap");
                    (*jvm)->DetachCurrentThread(jvm);
                    return;
                }
                usleep(kPollIntervalUs);
            }
        }

        JNINativeMethod methods[] = {
            {"nativeLaunchStatus", "(Ljava/lang/String;)V",
             (void *)&Java_com_skarm_launcher_bootstrap_SkBootstrap_nativeLaunchStatus},
            {"nativeSteamKeepAlive", "(Z)V",
             (void *)&Java_com_skarm_launcher_bootstrap_SkBootstrap_nativeSteamKeepAlive},
            {"nativePromptDeviceCode", "(Z)Ljava/lang/String;",
             (void *)&Java_com_skarm_launcher_bootstrap_SkBootstrap_nativePromptDeviceCode},
            {"nativePromptEmailCode", "(Ljava/lang/String;Z)Ljava/lang/String;",
             (void *)&Java_com_skarm_launcher_bootstrap_SkBootstrap_nativePromptEmailCode},
            {"registerGlfwNatives", "(Ljava/lang/Class;)V",
             (void *)&Java_com_skarm_launcher_bootstrap_SkBootstrap_registerGlfwNatives},
        };
        (*env)->RegisterNatives(env, cls, methods, sizeof(methods) / sizeof(methods[0]));
        registered = YES;
        NSLog(@"[JavaLauncher] Successfully registered JNI natives for SkBootstrap!");

        // Force load libawt_headless and libprefs into the Bootstrap ClassLoader
        // By calling System.loadLibrary from JNI, Reflection.getCallerClass() is null,
        // which makes it use the Bootstrap ClassLoader. This fixes the iOS two-level
        // namespace issue natively by ensuring our stubs are available to all core Java classes.
        jclass sysCls = (*env)->FindClass(env, "java/lang/System");
        if (sysCls) {
            jmethodID loadLib = (*env)->GetStaticMethodID(env, sysCls, "loadLibrary", "(Ljava/lang/String;)V");
            if (loadLib) {
                jstring awt = (*env)->NewStringUTF(env, "awt_headless");
                (*env)->CallStaticVoidMethod(env, sysCls, loadLib, awt);
                if ((*env)->ExceptionCheck(env)) {
                    (*env)->ExceptionDescribe(env);
                    (*env)->ExceptionClear(env);
                }
                (*env)->DeleteLocalRef(env, awt);

                jstring prefs = (*env)->NewStringUTF(env, "prefs");
                (*env)->CallStaticVoidMethod(env, sysCls, loadLib, prefs);
                if ((*env)->ExceptionCheck(env)) {
                    (*env)->ExceptionDescribe(env);
                    (*env)->ExceptionClear(env);
                }
                (*env)->DeleteLocalRef(env, prefs);
                NSLog(@"[JavaLauncher] Pre-loaded awt_headless and prefs into Bootstrap ClassLoader");
            }
        }

        // Steam credentials were passed to frenchpress through the environment. Force Java
        // to capture it into ProcessEnvironment (the same trick as the Android port), then
        // unset the variables so the password is no longer readable from the process
        // environment for the rest of the session.
        if (sysCls) {
            jmethodID getenvAll = (*env)->GetStaticMethodID(env, sysCls, "getenv",
                                                            "()Ljava/util/Map;");
            if (getenvAll) {
                jobject envMap = (*env)->CallStaticObjectMethod(env, sysCls, getenvAll);
                if ((*env)->ExceptionCheck(env)) {
                    (*env)->ExceptionClear(env);
                } else if (envMap) {
                    (*env)->DeleteLocalRef(env, envMap);
                    unsetenv("FRENCHPRESS_STEAM_USER");
                    unsetenv("FRENCHPRESS_STEAM_PASS");
                }
            }
            (*env)->DeleteLocalRef(env, sysCls);
        }

        (*jvm)->DetachCurrentThread(jvm);
    }
}
