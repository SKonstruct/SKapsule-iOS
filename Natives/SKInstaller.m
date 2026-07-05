#import "SKInstaller.h"
#import "config.h"

#define fm NSFileManager.defaultManager
#define SK_MANIFEST_URL @"https://gamemedia2.spiralknights.com/spiral/latest/getdown.txt"
#define VERSION_MARKER @".skapsule_installed_v2"

@implementation SKInstaller

+ (BOOL)isInstalled {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home) return NO;

    NSString *manifest = [NSString stringWithFormat:@"%s/sk/getdown.txt", home];
    if (![fm fileExistsAtPath:manifest]) return NO;

    NSString *marker = [NSString stringWithFormat:@"%s/%@", home, VERSION_MARKER];
    if (![fm fileExistsAtPath:marker]) return NO;

    // Verify version/commit matches current build to trigger re-staging on updates
    NSString *markerContent = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil];
    NSString *currentVersion = [NSString stringWithFormat:@"%@-%s",
        NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"], CONFIG_COMMIT];

    return [markerContent isEqualToString:currentVersion];
}

+ (void)installWithProgress:(void (^)(NSString *))progress {
    const char *home = getenv("SKAPSULE_HOME");
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
        withIntermediateDirectories:YES attributes:nil error:nil];
    if ([fm fileExistsAtPath:fpSrc]) {
        [fm copyItemAtPath:fpSrc toPath:fpDst error:nil];
    }

    // 4. Stage LWJGL module JARs
    progress(@"Staging LWJGL…");
    NSString *lwjglSrc = [bundlePath stringByAppendingPathComponent:@"libs_lwjgl"];
    NSString *lwjglDst = [NSString stringWithFormat:@"%s/lwjgl/jars", home];
    [self stageDir:lwjglSrc toDir:lwjglDst exts:@[@"jar"]];

    // 5. Download SK manifest if not present
    NSString *manifestPath = [NSString stringWithFormat:@"%s/sk/getdown.txt", home];
    if (![fm fileExistsAtPath:manifestPath]) {
        progress(@"Fetching SK manifest…");
        [self downloadManifest:manifestPath];
    }

    // 6. Write version marker with current build info
    NSString *marker = [NSString stringWithFormat:@"%s/%@", home, VERSION_MARKER];
    NSString *currentVersion = [NSString stringWithFormat:@"%@-%s",
        NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"], CONFIG_COMMIT];
    [currentVersion writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];

    progress(@"Runtime ready.");
    NSLog(@"[SKInstaller] Installation complete");
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
        if (!match) continue;

        NSString *src = [srcDir stringByAppendingPathComponent:file];
        NSString *dst = [dstDir stringByAppendingPathComponent:file];
        // Always overwrite so app updates take effect
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

+ (void)downloadManifest:(NSString *)destPath {
    NSURL *url = [NSURL URLWithString:SK_MANIFEST_URL];
    NSURLRequest *request = [NSURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *resultData = nil;
    __block NSError *resultError = nil;
    __block NSInteger statusCode = 0;

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
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
        NSLog(@"[SKInstaller] Manifest download failed: %@ (HTTP %ld)",
            resultError.localizedDescription, (long)statusCode);
        return;
    }

    [resultData writeToFile:destPath atomically:YES];
    NSLog(@"[SKInstaller] Fetched getdown.txt (%lu bytes)", (unsigned long)resultData.length);
}

+ (NSString *)credFilePath {
    const char *home = getenv("SKAPSULE_HOME");
    if (!home) return @"";
    return [NSString stringWithFormat:@"%s/home/.local/share/frenchpress/steam.creds", home];
}

@end
