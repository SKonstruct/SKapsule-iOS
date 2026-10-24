#import "SKModManager.h"
#import "SKZipUtils.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>

/**
 * Entries no mod may replace, lowercased; archive entries are compared lowercased too, as
 * KnightLauncher matches them case-insensitively.
 *
 * Kept in step with KnightLauncher's ModManager.FILTER_LIST: configs that very often
 * collide with game updates.
 */
static NSSet<NSString *> *SKModFilteredFiles(void) {
    static NSSet<NSString *> *files;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSArray *protectedFiles = @[
          @"config/accessory.dat", @"config/accessory.xml",
          @"config/actor.dat", @"config/actor.xml",
          @"config/area.dat", @"config/area.xml",
          @"config/attack.dat", @"config/attack.xml",
          @"config/battle_sprite.dat", @"config/battle_sprite.xml",
          @"config/catalog.dat", @"config/catalog.xml",
          @"config/conversation.dat", @"config/conversation.xml",
          @"config/cursor.dat", @"config/cursor.xml",
          @"config/depot_catalog.dat", @"config/depot_catalog.xml",
          @"config/depth_scale.dat", @"config/depth_scale.xml",
          @"config/description.dat", @"config/description.xml",
          @"config/effect.dat", @"config/effect.xml",
          @"config/emote.dat", @"config/emote.xml",
          @"config/event.dat", @"config/event.xml",
          @"config/fire_action.dat", @"config/fire_action.xml",
          @"config/font.dat", @"config/font.xml",
          @"config/forge_property.dat", @"config/forge_property.xml",
          @"config/gift.dat", @"config/gift.xml",
          @"config/ground.dat", @"config/ground.xml",
          @"config/harness.dat", @"config/harness.xml",
          @"config/interact.dat", @"config/interact.xml",
          @"config/interface_script.dat", @"config/interface_script.xml",
          @"config/item.dat", @"config/item.xml",
          @"config/item_depth_weight.dat", @"config/item_depth_weight.xml",
          @"config/item_property.dat", @"config/item_property.xml",
          @"config/level_table.dat", @"config/level_table.xml",
          @"config/material.dat", @"config/material.xml",
          @"config/mission.dat", @"config/mission.xml",
          @"config/mission_group.dat", @"config/mission_group.xml",
          @"config/mission_property.dat", @"config/mission_property.xml",
          @"config/parameterized_handler.dat", @"config/parameterized_handler.xml",
          @"config/path.dat", @"config/path.xml",
          @"config/placeable.dat", @"config/placeable.xml",
          @"config/recipe.dat", @"config/recipe.xml",
          @"config/recipe_property.dat", @"config/recipe_property.xml",
          @"config/render_effect.dat", @"config/render_effect.xml",
          @"config/render_queue.dat", @"config/render_queue.xml",
          @"config/render_scheme.dat", @"config/render_scheme.xml",
          @"config/scene_global.dat", @"config/scene_global.xml",
          @"config/shader.dat", @"config/shader.xml",
          @"config/sounder.dat", @"config/sounder.xml",
          @"config/status_condition.dat", @"config/status_condition.xml",
          @"config/style.dat", @"config/style.xml",
          @"config/texture.dat", @"config/texture.xml",
          @"config/tile.dat", @"config/tile.xml",
          @"config/tile_replacement.dat", @"config/tile_replacement.xml",
          @"config/uplink.dat", @"config/uplink.xml",
          @"config/variant.dat", @"config/variant.xml",
          @"config/wall.dat", @"config/wall.xml",
      ];
      files = [NSSet setWithArray:protectedFiles];
    });
    return files;
}

/// `key = value` lines, as getdown writes getdown.txt and digest2.txt.
static NSDictionary<NSString *, NSString *> *SKReadGetdown(NSString *path) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@" = "];
        if (eq.location == NSNotFound || eq.location == 0 || [line hasPrefix:@"#"]) continue;
        out[[[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:ws]] =
          [[line substringFromIndex:NSMaxRange(eq)] stringByTrimmingCharactersInSet:ws];
    }
    return out;
}

/**
 * Getdown's version-2 jar digest: SHA-256 over every entry's contents in name order, so it
 * identifies the contents regardless of how the archive was written. Directory entries
 * contribute no bytes, so skipping them changes nothing.
 */
static NSString *SKGetdownDigest(NSString *jarPath) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSData *> *contents = [NSMutableDictionary dictionary];
    BOOL ok = [SKZipUtils enumerateZip:jarPath
                            usingBlock:^BOOL(NSString *name, NSData *data) {
                              [names addObject:name];
                              contents[name] = data;
                              return YES;
                            }];
    if (!ok) return nil;
    // Java's String.compareTo order, which is UTF-16 code-unit order: NSLiteralSearch.
    [names sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      return [a compare:b options:NSLiteralSearch];
    }];
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    for (NSString *name in names) {
        NSData *data = contents[name];
        CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

/**
 * Puts the game's own code/config.jar and code/projectx-config.jar back, which is where
 * class and locale mods are merged. KnightLauncher does this on every mount; merging into
 * last run's output keeps changes from mods that have since been removed.
 *
 * "The game's own" means matching the install's getdown digest2.txt. A jar that does not
 * is re-fetched for the installed version and only swapped in once it matches too, so the
 * host cannot hand us anything else. Untouched jars need no network. Call off the main
 * queue: it may block on the download.
 *
 * @return nil on success, otherwise a message for the user.
 */
static NSString *SKRestorePristineCodeJars(NSString *skPath) {
    NSDictionary *digests = SKReadGetdown([skPath stringByAppendingPathComponent:@"digest2.txt"]);
    NSDictionary *getdown = SKReadGetdown([skPath stringByAppendingPathComponent:@"getdown.txt"]);
    for (NSString *name in @[ @"config.jar", @"projectx-config.jar" ]) {
        NSString *path = [@"code" stringByAppendingPathComponent:name];
        NSString *expected = digests[path];
        if (!expected) return [NSString stringWithFormat:@"No digest for %@; launch the game once, then try again.", path];
        NSString *jar = [skPath stringByAppendingPathComponent:path];
        NSString *pristine = [jar stringByAppendingString:@".pristine"];
        NSFileManager *fm = NSFileManager.defaultManager;
        // Keep a verified copy before mods touch the jar, so later applies and removes can
        // restore it offline; the download below is only the fallback.
        if ([SKGetdownDigest(jar) isEqualToString:expected]) {
            if (![SKGetdownDigest(pristine) isEqualToString:expected]) {
                [fm removeItemAtPath:pristine error:nil];
                [fm copyItemAtPath:jar toPath:pristine error:nil];
            }
            continue;
        }
        if ([SKGetdownDigest(pristine) isEqualToString:expected]) {
            [fm removeItemAtPath:jar error:nil];
            if ([fm copyItemAtPath:pristine toPath:jar error:nil]) continue;
            return [NSString stringWithFormat:@"Couldn't replace %@.", path];
        }

        NSString *version = getdown[@"version"], *appbase = getdown[@"appbase"];
        if (!version || !appbase) return [NSString stringWithFormat:@"Can't find the game server to restore %@.", path];
        NSString *base = [appbase stringByReplacingOccurrencesOfString:@"%VERSION%" withString:version];
        if ([base hasPrefix:@"http://"]) base = [@"https://" stringByAppendingString:[base substringFromIndex:7]];
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", base, path]];

        __block NSData *data = nil;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        NSURLRequest *request = [NSURLRequest requestWithURL:url
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:30];
        NSURLSessionDataTask *task =
          [NSURLSession.sharedSession dataTaskWithRequest:request
                                        completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
                                          if (!error && ((NSHTTPURLResponse *)response).statusCode == 200) data = body;
                                          dispatch_semaphore_signal(done);
                                        }];
        [task resume];
        // The request's own timeout only covers idle time; bound the whole transfer too.
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) != 0) {
            [task cancel];
            data = nil;
        }
        if (!data) return [NSString stringWithFormat:@"Couldn't download the original %@. Check your connection.", path];

        NSString *tmp = [jar stringByAppendingString:@".download"];
        [data writeToFile:tmp atomically:YES];
        BOOL verified = [SKGetdownDigest(tmp) isEqualToString:expected];
        if (verified) {
            [NSFileManager.defaultManager removeItemAtPath:pristine error:nil];
            [NSFileManager.defaultManager copyItemAtPath:tmp toPath:pristine error:nil];
        }
        BOOL replaced = verified && rename(tmp.fileSystemRepresentation, jar.fileSystemRepresentation) == 0;
        [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
        if (!verified) return [NSString stringWithFormat:@"The original %@ failed verification.", path];
        if (!replaced) return [NSString stringWithFormat:@"Couldn't replace %@.", path];
        NSLog(@"[SKModManager] Restored original %@", path);
    }
    return nil;
}

/// Keeps the app running for a few seconds after a backgrounding, so an apply or remove is not
/// killed halfway through rewriting the game's files. The returned block ends the task; call it once.
static dispatch_block_t SKBeginBackgroundWork(NSString *name) {
    NSObject *lock = [NSObject new];
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    dispatch_block_t end = ^{
      @synchronized(lock) {
          if (task == UIBackgroundTaskInvalid) return;
          [UIApplication.sharedApplication endBackgroundTask:task];
          task = UIBackgroundTaskInvalid;
      }
    };
    task = [UIApplication.sharedApplication beginBackgroundTaskWithName:name expirationHandler:end];
    return end;
}

/// mod.json is third-party input: each value is type-checked and anything off-type is ignored.
/// Reads the top-level object, or its `mod` object when there is one.
static void SKParseModMeta(NSDictionary *json, NSString *fallbackName, NSString **name, NSString **type,
                           NSString **pxVersion, NSDictionary **locale) {
    *name = fallbackName;
    *type = nil;
    *pxVersion = nil;
    *locale = nil;
    if (![json isKindOfClass:NSDictionary.class]) return;
    id mod = json[@"mod"];
    NSDictionary *obj = [mod isKindOfClass:NSDictionary.class] ? mod : json;
    id v = obj[@"name"];
    if ([v isKindOfClass:NSString.class] && [v length] > 0) *name = v;
    v = obj[@"type"];
    if ([v isKindOfClass:NSString.class]) *type = v;
    v = obj[@"pxVersion"];
    if ([v isKindOfClass:NSString.class]) *pxVersion = v;
    v = obj[@"locale"];
    if ([v isKindOfClass:NSDictionary.class]) *locale = v;
}

/// Folds a mod's `locale` ({bundle: {key: value}}) into the running total, dropping off-type entries.
static void SKMergeLocale(NSMutableDictionary<NSString *, NSMutableDictionary *> *total, NSDictionary *locale) {
    for (id bundle in locale) {
        id changes = locale[bundle];
        if (![bundle isKindOfClass:NSString.class] || ![changes isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *merged = total[bundle];
        if (!merged) {
            merged = [NSMutableDictionary dictionary];
            total[bundle] = merged;
        }
        for (id key in changes) {
            id value = changes[key];
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) merged[key] = value;
        }
    }
}

/// Moves `replacement` over `path`, keeping `path` if anything fails.
static BOOL SKReplaceFile(NSFileManager *fm, NSString *path, NSString *replacement, NSString *backup) {
    [fm removeItemAtPath:backup error:nil];
    if (![fm moveItemAtPath:path toPath:backup error:nil]) return NO;
    if ([fm moveItemAtPath:replacement toPath:path error:nil]) {
        [fm removeItemAtPath:backup error:nil];
        return YES;
    }
    [fm moveItemAtPath:backup toPath:path error:nil];
    return NO;
}

/// A name from the remote listing or the sync manifest: one visible path component.
static BOOL SKValidModFileName(id name) {
    return [name isKindOfClass:NSString.class] && [name length] > 0 && ![name hasPrefix:@"."] &&
           [name rangeOfString:@"/"].location == NSNotFound && [name rangeOfString:@"\\"].location == NSNotFound;
}

/// The only place mod files come from; the listing's own sha, not the host, is what is trusted.
static NSURL *SKModDownloadURL(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] ||
        ![url.host.lowercaseString isEqualToString:@"raw.githubusercontent.com"]) {
        return nil;
    }
    return url;
}

/// Downloads to a temp file beside `destPath`, and only renames it into place once its git blob
/// SHA matches `expectedSha`. Blocks. @return nil on success, otherwise why not.
static NSString *SKDownloadVerified(NSURL *url, NSString *destPath, NSString *expectedSha) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tmp = [destPath stringByAppendingString:@".download"];
    [fm removeItemAtPath:tmp error:nil];

    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:60];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSInteger status = 0;
    __block NSError *error = nil;
    __block BOOL stored = NO;
    NSURLSessionDownloadTask *task = [NSURLSession.sharedSession
        downloadTaskWithRequest:request
              completionHandler:^(NSURL *location, NSURLResponse *response, NSError *err) {
                error = err;
                if ([response isKindOfClass:NSHTTPURLResponse.class]) status = ((NSHTTPURLResponse *)response).statusCode;
                // The system deletes `location` when this returns.
                if (!err && status == 200 && location) {
                    stored = [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:tmp] error:nil];
                }
                dispatch_semaphore_signal(done);
              }];
    [task resume];
    // The request's own timeout only covers idle time; bound the whole transfer too.
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC)) != 0) {
        [task cancel];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        [fm removeItemAtPath:tmp error:nil];
        return @"timed out";
    }
    if (error) return error.localizedDescription;
    if (status != 200) return [NSString stringWithFormat:@"HTTP %ld", (long)status];
    if (!stored) return @"couldn't store the download";

    NSString *sha = [SKZipUtils calculateGitBlobShaOfFile:tmp];
    if (![sha isEqualToString:expectedSha.lowercaseString]) {
        [fm removeItemAtPath:tmp error:nil];
        return @"failed verification";
    }
    if (rename(tmp.fileSystemRepresentation, destPath.fileSystemRepresentation) != 0) {
        [fm removeItemAtPath:tmp error:nil];
        return @"couldn't move into place";
    }
    return nil;
}

@implementation SKModManager

+ (instancetype)sharedManager {
    static SKModManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)downloadModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                      completion:(void (^)(BOOL success, NSString *_Nullable summary,
                                           NSError *_Nullable error))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      const char *homeEnv = getenv("SKAPSULE_HOME");
      if (!homeEnv) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err =
                [NSError errorWithDomain:@"SKModManagerDomain"
                                    code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"SKapsule home directory is not set."}];
            completionBlock(NO, nil, err);
          });
          return;
      }

      NSString *home = [NSString stringWithUTF8String:homeEnv];
      NSString *modsPath = [home stringByAppendingPathComponent:@"sk/mods"];
      [[NSFileManager defaultManager] createDirectoryAtPath:modsPath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];

      NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/SirDank/Spiral-Knights-Modpack/contents/mods"];
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:30];
      [request setValue:@"SKapsule-Launcher-iOS" forHTTPHeaderField:@"User-Agent"];

      dispatch_semaphore_t sem = dispatch_semaphore_create(0);
      __block NSData *data = nil;
      __block NSError *error = nil;
      __block NSInteger statusCode = 0;
      NSURLSessionDataTask *task =
          [NSURLSession.sharedSession dataTaskWithRequest:request
                                       completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
                                         data = d;
                                         error = err;
                                         if ([resp isKindOfClass:NSHTTPURLResponse.class]) {
                                             statusCode = ((NSHTTPURLResponse *)resp).statusCode;
                                         }
                                         dispatch_semaphore_signal(sem);
                                       }];
      [task resume];
      dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

      if (error || !data || statusCode != 200) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err = error;
            if (!err) {
                err = [NSError errorWithDomain:@"SKModManagerDomain"
                                          code:2
                                      userInfo:@{
                                          NSLocalizedDescriptionKey:
                                              @"Failed to connect to GitHub. Check your internet connection."
                                      }];
            }
            completionBlock(NO, nil, err);
          });
          return;
      }

      NSArray *remoteFiles = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (![remoteFiles isKindOfClass:[NSArray class]] || remoteFiles.count == 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err = [NSError errorWithDomain:@"SKModManagerDomain"
                                               code:3
                                           userInfo:@{NSLocalizedDescriptionKey: @"No mods found in the repository."}];
            completionBlock(NO, nil, err);
          });
          return;
      }

      NSMutableArray *modsToSync = [NSMutableArray array];
      NSMutableSet *remoteNames = [NSMutableSet set];

      for (id file in remoteFiles) {
          if (![file isKindOfClass:NSDictionary.class] || ![file[@"type"] isEqual:@"file"] ||
              !SKValidModFileName(file[@"name"])) {
              continue;
          }
          [modsToSync addObject:file];
          [remoteNames addObject:file[@"name"]];
      }

      // Only files an earlier sync wrote are ever removed: the mods folder also holds the
      // user's own mods, which are not in the remote listing.
      NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
      NSMutableSet *tracked = [NSMutableSet set];
      for (id name in [defaults arrayForKey:@"mod_sync_files"]) {
          if (SKValidModFileName(name)) [tracked addObject:name];
      }

      NSFileManager *fm = [NSFileManager defaultManager];
      NSInteger deleted = 0;
      for (NSString *name in tracked) {
          if ([remoteNames containsObject:name]) continue;
          if ([fm removeItemAtPath:[modsPath stringByAppendingPathComponent:name] error:nil]) deleted++;
      }
      NSMutableSet *synced = [NSMutableSet set];

      NSInteger downloaded = 0;
      NSInteger skipped = 0;
      NSInteger failed = 0;

      for (NSInteger i = 0; i < modsToSync.count; i++) {
          NSDictionary *mod = modsToSync[i];
          NSString *name = mod[@"name"];
          id shaValue = mod[@"sha"];
          NSString *remoteSha = [shaValue isKindOfClass:NSString.class] && [shaValue length] == 40 ? shaValue : nil;

          NSString *destPath = [modsPath stringByAppendingPathComponent:name];

          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)(i) / modsToSync.count;
            NSString *msg =
                [NSString stringWithFormat:@"Checking (%ld/%ld): %@", (long)(i + 1), (long)modsToSync.count, name];
            progressBlock(prog, msg);
          });

          // Without a sha there is nothing to verify the download against.
          NSURL *downloadURL = SKModDownloadURL(mod[@"download_url"]);
          if (!remoteSha || !downloadURL) {
              NSLog(@"[SKModManager] Skipping %@: no usable sha or download URL", name);
              failed++;
              continue;
          }

          if ([fm fileExistsAtPath:destPath]) {
              NSString *localSha = [SKZipUtils calculateGitBlobShaOfFile:destPath];
              if ([localSha isEqualToString:remoteSha.lowercaseString]) {
                  skipped++;
                  [synced addObject:name];
                  continue;
              }
          }

          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)(i) / modsToSync.count;
            NSString *msg = [NSString stringWithFormat:@"[%ld/%ld]: %@", (long)(i + 1), (long)modsToSync.count, name];
            progressBlock(prog, msg);
          });

          NSString *why = SKDownloadVerified(downloadURL, destPath, remoteSha);
          if (why) {
              NSLog(@"[SKModManager] Download of %@ failed: %@", name, why);
              failed++;
          } else {
              downloaded++;
              [synced addObject:name];
          }
      }

      // A file whose update failed stays tracked if it already was.
      NSMutableArray *manifest = [NSMutableArray array];
      for (NSString *name in remoteNames) {
          if ([synced containsObject:name] || [tracked containsObject:name]) [manifest addObject:name];
      }
      [defaults setObject:manifest forKey:@"mod_sync_files"];

      dispatch_async(dispatch_get_main_queue(), ^{
        if (failed > 0 && downloaded + skipped == 0) {
            completionBlock(NO, nil,
                            [NSError errorWithDomain:@"SKModManagerDomain"
                                                code:8
                                            userInfo:@{
                                                NSLocalizedDescriptionKey:
                                                    @"No mods could be downloaded. Check your connection and try again."
                                            }]);
            return;
        }
        NSMutableString *stats = [NSMutableString
            stringWithFormat:@"Sync complete!\nDownloaded: %ld\nSkipped: %ld\nDeleted: %ld", (long)downloaded,
                             (long)skipped, (long)deleted];
        if (failed > 0) [stats appendFormat:@"\nFailed: %ld (try again)", (long)failed];
        completionBlock(YES, stats, nil);
      });
    });
}

- (void)applyModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                   completion:(void (^)(BOOL success, NSString *_Nullable summary,
                                        NSArray<NSString *> *_Nullable warnings,
                                        NSError *_Nullable error))callerCompletion {
    dispatch_block_t endBackground = SKBeginBackgroundWork(@"Apply mods");
    void (^completionBlock)(BOOL, NSString *, NSArray<NSString *> *, NSError *) =
        ^(BOOL success, NSString *summary, NSArray<NSString *> *warnings, NSError *error) {
          endBackground();
          callerCompletion(success, summary, warnings, error);
        };
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      const char *homeEnv = getenv("SKAPSULE_HOME");
      if (!homeEnv) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err =
                [NSError errorWithDomain:@"SKModManagerDomain"
                                    code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"SKapsule home directory is not set."}];
            completionBlock(NO, nil, nil, err);
          });
          return;
      }

      NSString *home = [NSString stringWithUTF8String:homeEnv];
      NSString *skPath = [home stringByAppendingPathComponent:@"sk"];
      NSString *rsrcDir = [skPath stringByAppendingPathComponent:@"rsrc"];
      NSFileManager *fm = [NSFileManager defaultManager];

      if (![fm fileExistsAtPath:rsrcDir]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err =
                [NSError errorWithDomain:@"SKModManagerDomain"
                                    code:4
                                userInfo:@{
                                    NSLocalizedDescriptionKey:
                                        @"Game is not installed yet. Launch the game first to install game files."
                                }];
            completionBlock(NO, nil, nil, err);
          });
          return;
      }

      NSString *modsPath = [home stringByAppendingPathComponent:@"sk/mods"];
      NSArray *modFiles = [fm contentsOfDirectoryAtPath:modsPath error:nil];
      NSMutableArray *zipsOrModpacks = [NSMutableArray array];
      for (NSString *file in modFiles) {
          if ([file hasSuffix:@".zip"] || [file hasSuffix:@".modpack"]) {
              [zipsOrModpacks addObject:file];
          }
      }

      if (zipsOrModpacks.count == 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err = [NSError
                errorWithDomain:@"SKModManagerDomain"
                           code:5
                       userInfo:@{NSLocalizedDescriptionKey: @"No mods found in mods folder. Download mods first."}];
            completionBlock(NO, nil, nil, err);
          });
          return;
      }

      NSSet<NSString *> *protectedFiles = SKModFilteredFiles();

      NSString *codeDir = [skPath stringByAppendingPathComponent:@"code"];
      NSString *classChangesDir = [codeDir stringByAppendingPathComponent:@"class-changes"];
      NSString *localeChangesDir = [codeDir stringByAppendingPathComponent:@"locale-changes"];
      NSString *tempPack = [modsPath stringByAppendingPathComponent:@".temp_pack"];

      // Stops the apply, leaving the previous code jars as they are.
      void (^fail)(NSString *) = ^(NSString *message) {
        [fm removeItemAtPath:classChangesDir error:nil];
        [fm removeItemAtPath:localeChangesDir error:nil];
        [fm removeItemAtPath:tempPack error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
          completionBlock(NO, nil, nil,
                          [NSError errorWithDomain:@"SKModManagerDomain"
                                              code:8
                                          userInfo:@{NSLocalizedDescriptionKey: message}]);
        });
      };

      dispatch_async(dispatch_get_main_queue(), ^{
        progressBlock(0.0f, @"Restoring original code jars…");
      });
      NSString *restoreError = SKRestorePristineCodeJars(skPath);
      if (restoreError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(NO, nil, nil,
                            [NSError errorWithDomain:@"SKModManagerDomain"
                                                code:7
                                            userInfo:@{NSLocalizedDescriptionKey: restoreError}]);
          });
          return;
      }

      // Purge everything in rsrcDir except jar, zip, jarv files
      NSArray *rsrcContents = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
      for (NSString *contentFile in rsrcContents) {
          NSString *extension = [contentFile pathExtension].lowercaseString;
          if ([extension isEqualToString:@"jar"] || [extension isEqualToString:@"zip"] ||
              [extension isEqualToString:@"jarv"]) {
              continue;
          }
          NSString *contentPath = [rsrcDir stringByAppendingPathComponent:contentFile];
          [fm removeItemAtPath:contentPath error:nil];
      }

      NSArray *rsrcFiles = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
      NSMutableArray *jarFiles = [NSMutableArray array];
      for (NSString *file in rsrcFiles) {
          if ([file hasSuffix:@".jar"]) {
              [jarFiles addObject:file];
          }
      }

      NSInteger totalJars = jarFiles.count;
      NSInteger jarsUnpacked = 0;
      for (NSInteger i = 0; i < totalJars; i++) {
          NSString *file = jarFiles[i];
          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)i / totalJars;
            NSString *msg =
                [NSString stringWithFormat:@"Extracting resource [%ld/%ld]: %@", (long)(i + 1), (long)totalJars, file];
            progressBlock(prog, msg);
          });

          NSString *jarPath = [rsrcDir stringByAppendingPathComponent:file];
          if (![SKZipUtils extractZipFile:jarPath toDirectory:rsrcDir checkProtected:NO protectedFiles:nil]) {
              fail([NSString stringWithFormat:@"Couldn't unpack %@. Check free space, then try again.", file]);
              return;
          }
          jarsUnpacked++;
      }

      [fm removeItemAtPath:classChangesDir error:nil];
      [fm createDirectoryAtPath:classChangesDir withIntermediateDirectories:YES attributes:nil error:nil];

      NSString *getdownPath = [skPath stringByAppendingPathComponent:@"getdown.txt"];
      NSString *gameVersion = nil;
      if ([fm fileExistsAtPath:getdownPath]) {
          NSString *gdContent = [NSString stringWithContentsOfFile:getdownPath encoding:NSUTF8StringEncoding error:nil];
          NSArray *lines = [gdContent componentsSeparatedByString:@"\n"];
          for (NSString *line in lines) {
              if ([line hasPrefix:@"version = "]) {
                  gameVersion = [[line substringFromIndex:@"version = ".length]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                  break;
              }
          }
      }

      NSInteger resourceMods = 0;
      NSInteger classMods = 0;
      NSInteger modpacks = 0;
      NSInteger skipped = 0;
      NSMutableArray *warnings = [NSMutableArray array];
      BOOL hasClassMods = NO;

      NSMutableDictionary<NSString *, NSMutableDictionary *> *globalLocaleChanges = [NSMutableDictionary dictionary];

      for (NSInteger i = 0; i < zipsOrModpacks.count; i++) {
          NSString *modFile = zipsOrModpacks[i];
          NSString *modPath = [modsPath stringByAppendingPathComponent:modFile];

          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)(i) / zipsOrModpacks.count;
            NSString *msg =
                [NSString stringWithFormat:@"[%ld/%ld]: %@", (long)(i + 1), (long)zipsOrModpacks.count, modFile];
            progressBlock(prog, msg);
          });

          BOOL isModpack = [modFile hasSuffix:@".modpack"];

          NSString *modName, *modType, *pxVersion;
          NSDictionary *localeChanges;
          SKParseModMeta([SKZipUtils readModMetadataFromZip:modPath], modFile, &modName, &modType, &pxVersion,
                         &localeChanges);

          BOOL isClassMod = (modType && [modType caseInsensitiveCompare:@"class"] == NSOrderedSame);

          if (isModpack) {
              [fm removeItemAtPath:tempPack error:nil];
              [fm createDirectoryAtPath:tempPack withIntermediateDirectories:YES attributes:nil error:nil];

              if (![SKZipUtils extractZipFile:modPath toDirectory:tempPack checkProtected:NO protectedFiles:nil]) {
                  skipped++;
                  [warnings addObject:[NSString stringWithFormat:@"Modpack '%@' could not be read - SKIPPED", modName]];
                  [fm removeItemAtPath:tempPack error:nil];
                  continue;
              }

              NSArray *innerFiles = [fm contentsOfDirectoryAtPath:tempPack error:nil];
              NSInteger innerApplied = 0;
              for (NSString *innerFile in innerFiles) {
                  if ([innerFile hasSuffix:@".zip"]) {
                      NSString *innerPath = [tempPack stringByAppendingPathComponent:innerFile];

                      NSString *innerName, *innerType, *innerPx;
                      NSDictionary *innerLocale;
                      SKParseModMeta([SKZipUtils readModMetadataFromZip:innerPath], innerFile, &innerName, &innerType,
                                     &innerPx, &innerLocale);

                      BOOL innerIsClass = (innerType && [innerType caseInsensitiveCompare:@"class"] == NSOrderedSame);
                      BOOL innerOK = YES;
                      if (innerIsClass) {
                          if (!innerPx || !gameVersion ||
                              [innerPx caseInsensitiveCompare:gameVersion] == NSOrderedSame) {
                              innerOK = [SKZipUtils extractZipFile:innerPath
                                                       toDirectory:classChangesDir
                                                    checkProtected:YES
                                                    protectedFiles:protectedFiles];
                              if (innerOK) {
                                  classMods++;
                                  hasClassMods = YES;
                                  innerApplied++;
                              }
                          } else {
                              skipped++;
                              [warnings addObject:[NSString stringWithFormat:@"Class mod '%@' requires game version %@ "
                                                                             @"but current is %@ - SKIPPED",
                                                                             innerName, innerPx, gameVersion]];
                          }
                      } else {
                          innerOK = [SKZipUtils extractZipFile:innerPath
                                                   toDirectory:rsrcDir
                                                checkProtected:YES
                                                protectedFiles:protectedFiles];
                          if (innerOK) {
                              resourceMods++;
                              innerApplied++;
                          }
                      }
                      if (!innerOK) {
                          skipped++;
                          [warnings addObject:[NSString stringWithFormat:@"'%@' could not be fully applied", innerName]];
                      }

                      SKMergeLocale(globalLocaleChanges, innerLocale);
                  }
              }
              if (innerApplied > 0)
                  modpacks++;
              [fm removeItemAtPath:tempPack error:nil];
          } else if (isClassMod) {
              if (!pxVersion || !gameVersion || [pxVersion caseInsensitiveCompare:gameVersion] == NSOrderedSame) {
                  if ([SKZipUtils extractZipFile:modPath
                                     toDirectory:classChangesDir
                                  checkProtected:YES
                                  protectedFiles:protectedFiles]) {
                      classMods++;
                      hasClassMods = YES;
                  } else {
                      skipped++;
                      [warnings addObject:[NSString stringWithFormat:@"'%@' could not be fully applied", modName]];
                  }
              } else {
                  skipped++;
                  [warnings
                      addObject:[NSString stringWithFormat:
                                              @"Class mod '%@' requires game version %@ but current is %@ - SKIPPED",
                                              modName, pxVersion, gameVersion]];
              }
          } else if ([SKZipUtils extractZipFile:modPath
                                    toDirectory:rsrcDir
                                 checkProtected:YES
                                 protectedFiles:protectedFiles]) {
              resourceMods++;
          } else {
              skipped++;
              [warnings addObject:[NSString stringWithFormat:@"'%@' could not be fully applied", modName]];
          }

          SKMergeLocale(globalLocaleChanges, localeChanges);
      }

      if (hasClassMods) {
          dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(0.95f, @"Merging class changes into config.jar…");
          });
          NSString *configJar = [codeDir stringByAppendingPathComponent:@"config.jar"];
          if ([fm fileExistsAtPath:configJar]) {
              NSString *configNewJar = [codeDir stringByAppendingPathComponent:@"config-new.jar"];
              NSString *configOldJar = [codeDir stringByAppendingPathComponent:@"config-old.jar"];

              if (![SKZipUtils extractJarWithoutOverwrite:configJar toDirectory:classChangesDir] ||
                  ![SKZipUtils createZipFileFromDirectory:classChangesDir toZipPath:configNewJar]) {
                  [fm removeItemAtPath:configNewJar error:nil];
                  fail(@"Couldn't build the modded config.jar. Check free space, then try again.");
                  return;
              }
              if (!SKReplaceFile(fm, configJar, configNewJar, configOldJar)) {
                  [fm removeItemAtPath:configNewJar error:nil];
                  fail(@"Couldn't replace config.jar.");
                  return;
              }
          }
      }
      [fm removeItemAtPath:classChangesDir error:nil];

      if (globalLocaleChanges.count > 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(0.98f, @"Applying locale changes…");
          });
          NSString *projectxConfig = [codeDir stringByAppendingPathComponent:@"projectx-config.jar"];
          if ([fm fileExistsAtPath:projectxConfig]) {
              [fm removeItemAtPath:localeChangesDir error:nil];
              [fm createDirectoryAtPath:localeChangesDir withIntermediateDirectories:YES attributes:nil error:nil];

              BOOL localeOK = [SKZipUtils extractZipFile:projectxConfig
                                             toDirectory:localeChangesDir
                                          checkProtected:NO
                                          protectedFiles:nil];

              for (NSString *bundlePath in globalLocaleChanges) {
                  if (!localeOK) break;
                  // Bundle names come from mod.json and must stay inside the extracted i18n folder.
                  NSString *propsPath =
                      [bundlePath hasPrefix:@"/"] || [bundlePath containsString:@"\\"]
                          ? nil
                          : [SKZipUtils safeDestinationForEntry:[@"rsrc/i18n/" stringByAppendingString:bundlePath]
                                                    inDirectory:localeChangesDir];
                  if (!propsPath) {
                      NSLog(@"[SKModManager] Ignoring locale bundle with an unsafe path: %@", bundlePath);
                      continue;
                  }
                  if ([fm fileExistsAtPath:propsPath]) {
                      NSString *propsContent = [NSString stringWithContentsOfFile:propsPath
                                                                         encoding:NSUTF8StringEncoding
                                                                            error:nil];
                      NSMutableDictionary *properties = [NSMutableDictionary dictionary];
                      NSArray *lines = [propsContent componentsSeparatedByString:@"\n"];
                      for (NSString *line in lines) {
                          NSString *trimmed =
                              [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                          if ([trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"!"] || trimmed.length == 0)
                              continue;
                          NSRange range = [trimmed rangeOfString:@"="];
                          if (range.location != NSNotFound) {
                              NSString *key = [[trimmed substringToIndex:range.location]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                              NSString *val = [[trimmed substringFromIndex:range.location + 1]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                              properties[key] = val;
                          }
                      }

                      NSDictionary *overrides = globalLocaleChanges[bundlePath];
                      for (NSString *key in overrides) {
                          properties[key] = overrides[key];
                      }

                      NSMutableString *newContent = [NSMutableString string];
                      for (NSString *key in properties) {
                          [newContent appendFormat:@"%@=%@\n", key, properties[key]];
                      }
                      if (![newContent writeToFile:propsPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
                          localeOK = NO;
                      }
                  }
              }

              NSString *newJar = [codeDir stringByAppendingPathComponent:@"projectx-config-new.jar"];
              NSString *oldJar = [codeDir stringByAppendingPathComponent:@"projectx-config-old.jar"];
              if (!localeOK || ![SKZipUtils createZipFileFromDirectory:localeChangesDir toZipPath:newJar]) {
                  [fm removeItemAtPath:newJar error:nil];
                  fail(@"Couldn't build the modded projectx-config.jar. Check free space, then try again.");
                  return;
              }
              if (!SKReplaceFile(fm, projectxConfig, newJar, oldJar)) {
                  [fm removeItemAtPath:newJar error:nil];
                  fail(@"Couldn't replace projectx-config.jar.");
                  return;
              }
          }
          [fm removeItemAtPath:localeChangesDir error:nil];
      }

      [fm removeItemAtPath:[rsrcDir stringByAppendingPathComponent:@"mod.json"] error:nil];
      [fm removeItemAtPath:[rsrcDir stringByAppendingPathComponent:@"mod.png"] error:nil];

      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *msg = [NSString
            stringWithFormat:@"Applied: %ld mods (%ld resource, %ld class, %ld modpacks).\nUnpacked %ld resources.",
                             (long)(resourceMods + classMods + modpacks), (long)resourceMods, (long)classMods,
                             (long)modpacks, (long)jarsUnpacked];
        completionBlock(YES, msg, warnings, nil);
      });
    });
}

- (void)removeModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                    completion:
                        (void (^)(BOOL success, NSString *_Nullable summary, NSError *_Nullable error))callerCompletion {
    dispatch_block_t endBackground = SKBeginBackgroundWork(@"Remove mods");
    void (^completionBlock)(BOOL, NSString *, NSError *) = ^(BOOL success, NSString *summary, NSError *error) {
      endBackground();
      callerCompletion(success, summary, error);
    };
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      const char *homeEnv = getenv("SKAPSULE_HOME");
      if (!homeEnv) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err =
                [NSError errorWithDomain:@"SKModManagerDomain"
                                    code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"SKapsule home directory is not set."}];
            completionBlock(NO, nil, err);
          });
          return;
      }

      NSString *home = [NSString stringWithUTF8String:homeEnv];
      NSString *skPath = [home stringByAppendingPathComponent:@"sk"];
      NSString *rsrcDir = [skPath stringByAppendingPathComponent:@"rsrc"];
      NSFileManager *fm = [NSFileManager defaultManager];

      if (![fm fileExistsAtPath:rsrcDir]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err = [NSError errorWithDomain:@"SKModManagerDomain"
                                               code:6
                                           userInfo:@{NSLocalizedDescriptionKey: @"Game is not installed yet."}];
            completionBlock(NO, nil, err);
          });
          return;
      }

      // Class and locale mods live in the code jars, not rsrc/.
      dispatch_async(dispatch_get_main_queue(), ^{
        progressBlock(0.0f, @"Restoring original code jars…");
      });
      NSString *restoreError = SKRestorePristineCodeJars(skPath);
      if (restoreError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(NO, nil,
                            [NSError errorWithDomain:@"SKModManagerDomain"
                                                code:7
                                            userInfo:@{NSLocalizedDescriptionKey: restoreError}]);
          });
          return;
      }

      // Purge everything in rsrcDir except jar, zip, jarv files
      NSArray *rsrcContents = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
      for (NSString *contentFile in rsrcContents) {
          NSString *extension = [contentFile pathExtension].lowercaseString;
          if ([extension isEqualToString:@"jar"] || [extension isEqualToString:@"zip"] ||
              [extension isEqualToString:@"jarv"]) {
              continue;
          }
          NSString *contentPath = [rsrcDir stringByAppendingPathComponent:contentFile];
          [fm removeItemAtPath:contentPath error:nil];
      }

      NSArray *rsrcFiles = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
      NSMutableArray *jarFiles = [NSMutableArray array];
      for (NSString *file in rsrcFiles) {
          if ([file hasSuffix:@".jar"]) {
              [jarFiles addObject:file];
          }
      }

      NSInteger totalJars = jarFiles.count;
      NSInteger jarsUnpacked = 0;
      for (NSInteger i = 0; i < totalJars; i++) {
          NSString *file = jarFiles[i];
          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)i / totalJars;
            NSString *msg =
                [NSString stringWithFormat:@"Extracting resource [%ld/%ld]: %@", (long)(i + 1), (long)totalJars, file];
            progressBlock(prog, msg);
          });

          NSString *jarPath = [rsrcDir stringByAppendingPathComponent:file];
          if (![SKZipUtils extractZipFile:jarPath toDirectory:rsrcDir checkProtected:NO protectedFiles:nil]) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(NO, nil,
                                [NSError errorWithDomain:@"SKModManagerDomain"
                                                    code:8
                                                userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString
                                                        stringWithFormat:@"Couldn't unpack %@. Check free space, "
                                                                         @"then try again.",
                                                                         file]
                                                }]);
              });
              return;
          }
          jarsUnpacked++;
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *msg =
            [NSString stringWithFormat:@"Mods removed successfully!\nUnpacked %ld resources.", (long)jarsUnpacked];
        completionBlock(YES, msg, nil);
      });
    });
}

@end
