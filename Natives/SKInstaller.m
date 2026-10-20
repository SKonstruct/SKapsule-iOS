#import "SKInstaller.h"
#import "SKZipUtils.h"
#import "config.h"

#define fm NSFileManager.defaultManager
#define SK_MANIFEST_URL @"https://gamemedia2.spiralknights.com/spiral/latest/getdown.txt"
#define VERSION_MARKER @".skapsule_installed_v2"

@implementation SKInstaller

+ (BOOL)isInstalled {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home)
        return NO;

    NSString *manifest = [NSString stringWithFormat:@"%s/sk/getdown.txt", home];
    if (![fm fileExistsAtPath:manifest])
        return NO;

    NSString *marker = [NSString stringWithFormat:@"%s/%@", home, VERSION_MARKER];
    if (![fm fileExistsAtPath:marker])
        return NO;

    // Verify version/commit matches current build to trigger re-staging on updates
    NSString *markerContent = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil];
    NSString *currentVersion =
        [NSString stringWithFormat:@"%@-%s", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"], CONFIG_COMMIT];

    return [markerContent isEqualToString:currentVersion];
}

/**
 * Copies the bundle's jars over the staged ones whenever they differ.
 *
 * Runs on every launch, not just when the version marker moves: an app update that
 * rebuilt frenchpress or cacio from the same commit leaves the marker untouched, and
 * the game would keep loading last month's jar. Each file is compared first, so the
 * steady-state cost is a handful of stat() calls.
 */
/**
 * Drops a getdown-managed jar that no longer yields its resources, so getdown re-downloads
 * it on this launch.
 *
 * Getdown decides a resource is valid purely from "the file and its .jarv marker exist"
 * (Resource.isMarkedValid) -- it never re-hashes. So a jar that our own mod path rewrote
 * into something java.util.zip cannot read stays broken forever, and the game dies with
 * "Unable to locate resource [path=config/manager.txt]" followed by a NullPointerException
 * deep in its config code, with the boot overlay still showing the last download status.
 */
+ (void)repairGameJars {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) return;

    // Canary: this entry lives in projectx-config.jar and is the first thing SK's
    // ConfigManager asks for. If it is unreachable nothing else in that jar loads either,
    // and the client dies in its config code long before it draws a frame.
    NSString *jar = [NSString stringWithFormat:@"%s/sk/code/projectx-config.jar", homeEnv];
    if (![fm fileExistsAtPath:jar]) return;
    if ([SKZipUtils zipFile:jar containsEntry:@"rsrc/config/manager.properties"]) return;

    // Refetching replaces the jar wholesale, so any locale mod baked into it is lost. That
    // is the right trade only because the alternative is a client that cannot start -- say
    // so in the log, since the user will see their mods revert.
    NSLog(@"[SKInstaller] projectx-config.jar yields no resources; refetching (mods in it "
          @"will need re-applying)");
    [self dropGetdownResource:jar];
}

/**
 * Forces getdown to re-unpack the rsrc bundles when their unpacked tree has gone missing.
 *
 * The bundles are "uresource" entries: getdown unpacks them as a side effect the first
 * time it validates them, then writes a ".jarv" marker and never looks again. Our own mod
 * apply/remove purges the unpacked tree and rebuilds it by hand, so an interrupted run
 * leaves the jars and their markers in place with nothing extracted -- and the client dies
 * looking for its UI descriptors and sounds.
 *
 * Deleting only the markers is deliberate: the jars themselves still match digest.txt, so
 * getdown re-validates them without re-downloading half a gigabyte, and the unpack runs
 * as part of that. (Do not do this to a jar we have rewritten ourselves -- there the
 * digest will not match and getdown replaces it, silently undoing the mods.)
 */
+ (void)repairUnpackedResources {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) return;

    NSString *rsrcDir = [NSString stringWithFormat:@"%s/sk/rsrc", homeEnv];
    // Canary: one of the UI descriptors the client loads before it can draw anything.
    NSString *canary = [rsrcDir stringByAppendingPathComponent:@"ui/hud/default/chatoverlay.dat"];
    if ([fm fileExistsAtPath:canary]) return;

    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
    NSUInteger dropped = 0;
    for (NSString *name in entries) {
        if (![name.pathExtension isEqualToString:@"jarv"]) continue;
        [fm removeItemAtPath:[rsrcDir stringByAppendingPathComponent:name] error:nil];
        dropped++;
    }
    // crucible.jar is a uresource too, and it sits beside rsrc rather than inside it.
    NSString *crucibleMarker = [NSString stringWithFormat:@"%s/sk/crucible.jarv", homeEnv];
    if ([fm fileExistsAtPath:crucibleMarker]) {
        [fm removeItemAtPath:crucibleMarker error:nil];
        dropped++;
    }

    if (dropped > 0) {
        NSLog(@"[SKInstaller] rsrc bundles are not unpacked; cleared %lu marker(s) to force it",
              (unsigned long)dropped);
    }
}

/// Removes a resource and the ".jarv" marker that makes getdown skip re-validating it.
+ (void)dropGetdownResource:(NSString *)path {
    [fm removeItemAtPath:path error:nil];
    [fm removeItemAtPath:[path stringByAppendingString:@"v"] error:nil];
}

+ (void)refreshStagedJars {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home)
        return;
    [self stageBundledJarsInto:home progress:^(NSString *status){}];
}

+ (BOOL)installWithProgress:(void (^)(NSString *))progress {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home) {
        NSLog(@"[SKInstaller] SKAPSULE_HOME unset; cannot install");
        return NO;
    }

    [self stageBundledJarsInto:home progress:progress];

    // Download SK manifest if not present
    NSString *manifestPath = [NSString stringWithFormat:@"%s/sk/getdown.txt", home];
    if (![fm fileExistsAtPath:manifestPath]) {
        progress(@"Fetching SK manifest…");
        [self downloadManifest:manifestPath];
        if (![fm fileExistsAtPath:manifestPath]) {
            NSLog(@"[SKInstaller] Installation failed: manifest not available");
            return NO;
        }
    }

    // Write version marker with current build info
    NSString *marker = [NSString stringWithFormat:@"%s/%@", home, VERSION_MARKER];
    NSString *currentVersion =
        [NSString stringWithFormat:@"%@-%s", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"], CONFIG_COMMIT];
    [currentVersion writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];

    progress(@"Runtime ready.");
    NSLog(@"[SKInstaller] Installation complete");
    return YES;
}

+ (void)stageBundledJarsInto:(const char *)home progress:(void (^)(NSString *))progress {
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;

    // 1. Stage JARs from the app bundle to SKAPSULE_HOME
    progress(@"Staging bootstrap JARs…");
    [self stageDir:[bundlePath stringByAppendingPathComponent:@"libs"]
             toDir:[NSString stringWithFormat:@"%s/sk/code", home]
              exts:@[@"jar"]];

    // 2. Stage cacio JARs
    progress(@"Staging cacio AWT bridge…");
    NSString *cacioSrc = [bundlePath stringByAppendingPathComponent:@"libs_cacio"];
    NSString *cacioDst = [NSString stringWithFormat:@"%s/cacio", home];
    [self stageDir:cacioSrc toDir:cacioDst exts:@[@"jar"]];

    // 3. Stage frenchpress
    progress(@"Staging frenchpress…");
    NSString *fpSrc = [bundlePath stringByAppendingPathComponent:@"libs/frenchpress.jar"];
    NSString *fpDst = [NSString stringWithFormat:@"%s/frenchpress/frenchpress.jar", home];
    [fm createDirectoryAtPath:[fpDst stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    if ([fm fileExistsAtPath:fpSrc] && ![self staged:fpDst matchesSource:fpSrc]) {
        [fm removeItemAtPath:fpDst error:nil];
        [fm copyItemAtPath:fpSrc toPath:fpDst error:nil];
    }

    // 4. Stage LWJGL module JARs
    progress(@"Staging LWJGL…");
    NSString *lwjglSrc = [bundlePath stringByAppendingPathComponent:@"libs_lwjgl"];
    NSString *lwjglDst = [NSString stringWithFormat:@"%s/lwjgl/jars", home];
    [self stageDir:lwjglSrc toDir:lwjglDst exts:@[@"jar"]];
}

/// @return YES when the staged copy is byte-for-byte current with the bundle's.
+ (BOOL)staged:(NSString *)dst matchesSource:(NSString *)src {
    NSDictionary *dstAttrs = [fm attributesOfItemAtPath:dst error:nil];
    if (!dstAttrs)
        return NO;
    NSDictionary *srcAttrs = [fm attributesOfItemAtPath:src error:nil];
    if (!srcAttrs)
        return NO;
    if ([dstAttrs[NSFileSize] unsignedLongLongValue] != [srcAttrs[NSFileSize] unsignedLongLongValue])
        return NO;
    // Equal, not newer-or-equal: a downgrade (or any build that preserves timestamps)
    // must still replace what is staged, and bundle mtimes move with every build anyway.
    NSDate *srcDate = srcAttrs[NSFileModificationDate];
    NSDate *dstDate = dstAttrs[NSFileModificationDate];
    return srcDate && dstDate && [dstDate compare:srcDate] == NSOrderedSame;
}

+ (void)stageDir:(NSString *)srcDir toDir:(NSString *)dstDir exts:(NSArray<NSString *> *)exts {
    if (![fm fileExistsAtPath:srcDir]) {
        NSLog(@"[SKInstaller] Source dir missing: %@", srcDir);
        return;
    }

    [fm createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray *files = [fm contentsOfDirectoryAtPath:srcDir error:nil];
    for (NSString *file in files) {
        BOOL match = (exts == nil);
        for (NSString *ext in exts) {
            if ([file hasSuffix:[@"." stringByAppendingString:ext]]) {
                match = YES;
                break;
            }
        }
        if (!match)
            continue;

        NSString *src = [srcDir stringByAppendingPathComponent:file];
        NSString *dst = [dstDir stringByAppendingPathComponent:file];
        // Compare against the bundle copy rather than trusting a build stamp: an app
        // update that rebuilt a jar without moving the version marker would otherwise
        // keep serving the stale one forever.
        if ([self staged:dst matchesSource:src])
            continue;
        [fm removeItemAtPath:dst error:nil];
        NSError *error;
        [fm copyItemAtPath:src toPath:dst error:&error];
        if (error) {
            NSLog(@"[SKInstaller] Failed to stage %@: %@", file, error.localizedDescription);
        } else {
            NSLog(@"[SKInstaller] Staged %@", file);
        }
    }
}

+ (BOOL)downloadManifest:(NSString *)destPath {
    NSURL *url = [NSURL URLWithString:SK_MANIFEST_URL];
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:30];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *resultData = nil;
    __block NSError *resultError = nil;
    __block NSInteger statusCode = 0;

    NSURLSessionDataTask *task =
        [NSURLSession.sharedSession dataTaskWithRequest:request
                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                        resultData = data;
                                        resultError = error;
                                        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                                            statusCode = ((NSHTTPURLResponse *)response).statusCode;
                                        }
                                        dispatch_semaphore_signal(sem);
                                      }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (resultError || statusCode < 200 || statusCode >= 300) {
        NSLog(@"[SKInstaller] Manifest download failed: %@ (HTTP %ld)", resultError.localizedDescription,
              (long)statusCode);
        return NO;
    }

    [resultData writeToFile:destPath atomically:YES];
    NSLog(@"[SKInstaller] Fetched getdown.txt (%lu bytes)", (unsigned long)resultData.length);
    return YES;
}

+ (NSString *)credFilePath {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home)
        return @"";
    return [NSString stringWithFormat:@"%s/home/.local/share/frenchpress/steam.creds", home];
}

@end
