#import "SKInstaller.h"

#define fm NSFileManager.defaultManager

@implementation SKInstaller

+ (BOOL)isInstalled {
    // Phase 0: check if bootstrap.jar and getdown-pro.jar are staged in the app bundle
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSString *bootstrapJar = [bundlePath stringByAppendingPathComponent:@"libs/bootstrap.jar"];
    NSString *getdownJar = [bundlePath stringByAppendingPathComponent:@"libs/getdown-pro.jar"];

    BOOL hasBootstrap = [fm fileExistsAtPath:bootstrapJar];
    BOOL hasGetdown = [fm fileExistsAtPath:getdownJar];

    NSLog(@"[SKInstaller] isInstalled check: bootstrap=%d getdown=%d", hasBootstrap, hasGetdown);

    // In Phase 0 we consider the runtime "installed" if the key JARs exist in the bundle.
    // Phase 1 will add JRE extraction, LWJGL unpacking, and cacio staging.
    return hasBootstrap && hasGetdown;
}

+ (void)installWithProgress:(void (^)(NSString *))progress {
    progress(@"Checking bundled assets…");

    // Phase 0 stub: the Makefile stages assets into the .app bundle at build time.
    // Phase 1 will handle first-launch JRE extraction from compressed archives,
    // LWJGL native unpacking, and cacio/frenchpress JAR staging.

    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSLog(@"[SKInstaller] Bundle path: %@", bundlePath);

    progress(@"Runtime ready.");
    NSLog(@"[SKInstaller] Installation complete (Phase 0 stub)");
}

+ (NSString *)credFilePath {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home) return @"";
    return [NSString stringWithFormat:@"%s/home/.local/share/frenchpress/steam.creds", home];
}

@end
