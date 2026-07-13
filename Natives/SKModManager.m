#import "SKModManager.h"
#import "SKZipUtils.h"

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
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
      [request setValue:@"SKapsule-Launcher-iOS" forHTTPHeaderField:@"User-Agent"];

      NSError *error = nil;
      NSHTTPURLResponse *response = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
#pragma clang diagnostic pop

      if (error || !data || response.statusCode != 200) {
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

      for (NSDictionary *file in remoteFiles) {
          if ([file[@"type"] isEqualToString:@"file"]) {
              [modsToSync addObject:file];
              [remoteNames addObject:file[@"name"]];
          }
      }

      NSFileManager *fm = [NSFileManager defaultManager];
      NSArray *localFiles = [fm contentsOfDirectoryAtPath:modsPath error:nil];
      NSInteger deleted = 0;
      for (NSString *localFile in localFiles) {
          if (![remoteNames containsObject:localFile]) {
              [fm removeItemAtPath:[modsPath stringByAppendingPathComponent:localFile] error:nil];
              deleted++;
          }
      }

      NSInteger downloaded = 0;
      NSInteger skipped = 0;

      for (NSInteger i = 0; i < modsToSync.count; i++) {
          NSDictionary *mod = modsToSync[i];
          NSString *name = mod[@"name"];
          NSString *downloadUrlString = mod[@"download_url"];
          NSString *remoteSha = mod[@"sha"];

          NSString *destPath = [modsPath stringByAppendingPathComponent:name];

          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)(i) / modsToSync.count;
            NSString *msg =
                [NSString stringWithFormat:@"Checking (%ld/%ld): %@", (long)(i + 1), (long)modsToSync.count, name];
            progressBlock(prog, msg);
          });

          if ([fm fileExistsAtPath:destPath] && remoteSha.length > 0) {
              NSString *localSha = [SKZipUtils calculateGitBlobShaOfFile:destPath];
              if ([localSha isEqualToString:remoteSha]) {
                  skipped++;
                  continue;
              }
          }

          dispatch_async(dispatch_get_main_queue(), ^{
            float prog = (float)(i) / modsToSync.count;
            NSString *msg = [NSString stringWithFormat:@"[%ld/%ld]: %@", (long)(i + 1), (long)modsToSync.count, name];
            progressBlock(prog, msg);
          });

          NSData *modData = [NSData dataWithContentsOfURL:[NSURL URLWithString:downloadUrlString]];
          if (modData) {
              [modData writeToFile:destPath atomically:YES];
              downloaded++;
          }
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stats = [NSString stringWithFormat:@"Sync complete!\nDownloaded: %ld\nSkipped: %ld\nDeleted: %ld",
                                                     (long)downloaded, (long)skipped, (long)deleted];
        completionBlock(YES, stats, nil);
      });
    });
}

- (void)applyModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                   completion:(void (^)(BOOL success, NSString *_Nullable summary,
                                        NSArray<NSString *> *_Nullable warnings,
                                        NSError *_Nullable error))completionBlock {
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

      NSSet *protectedFiles = [NSSet
          setWithObjects:@"config/accessory.dat", @"config/accessory.xml", @"config/actor.dat", @"config/actor.xml",
                         @"config/area.dat", @"config/area.xml", @"config/attack.dat", @"config/attack.xml",
                         @"config/battle_sprite.dat", @"config/battle_sprite.xml", @"config/catalog.dat",
                         @"config/catalog.xml", @"config/conversation.dat", @"config/conversation.xml",
                         @"config/cursor.dat", @"config/cursor.xml", @"config/depot_catalog.dat",
                         @"config/depot_catalog.xml", @"config/depth_scale.dat", @"config/depth_scale.xml",
                         @"config/description.dat", @"config/description.xml", @"config/effect.dat",
                         @"config/effect.xml", @"config/emote.dat", @"config/emote.xml", @"config/event.dat",
                         @"config/event.xml", @"config/fire_action.dat", @"config/fire_action.xml", @"config/font.dat",
                         @"config/font.xml", @"config/forge_property.dat", @"config/forge_property.xml",
                         @"config/gift.dat", @"config/gift.xml", @"config/ground.dat", @"config/ground.xml",
                         @"config/harness.dat", @"config/harness.xml", @"config/interact.dat", @"config/interact.xml",
                         @"config/interface_script.dat", @"config/interface_script.xml", @"config/item.dat",
                         @"config/item.xml", @"config/item_depth_weight.dat", @"config/item_depth_weight.xml",
                         @"config/item_property.dat", @"config/item_property.xml", @"config/level_table.dat",
                         @"config/level_table.xml", @"config/material.dat", @"config/material.xml",
                         @"config/mission.dat", @"config/mission.xml", @"config/mission_group.dat",
                         @"config/mission_group.xml", @"config/mission_property.dat", @"config/mission_property.xml",
                         @"config/parameterized_handler.dat", @"config/parameterized_handler.xml", @"config/path.dat",
                         @"config/path.xml", @"config/placeable.dat", @"config/placeable.xml", @"config/recipe.dat",
                         @"config/recipe.xml", @"config/recipe_property.dat", @"config/recipe_property.xml",
                         @"config/render_effect.dat", @"config/render_effect.xml", @"config/render_queue.dat",
                         @"config/render_queue.xml", @"config/render_scheme.dat", @"config/render_scheme.xml",
                         @"config/scene_global.dat", @"config/scene_global.xml", @"config/shader.dat",
                         @"config/shader.xml", @"config/sounder.dat", @"config/sounder.xml",
                         @"config/status_condition.dat", @"config/status_condition.xml", @"config/status_effect.dat",
                         @"config/status_effect.xml", @"config/tileset.dat", @"config/tileset.xml", @"config/toy.dat",
                         @"config/toy.xml", @"config/vfx.dat", @"config/vfx.xml", @"config/view.dat",
                         @"config/view.xml", @"config/weapon.dat", @"config/weapon.xml", nil];

      NSString *codeDir = [skPath stringByAppendingPathComponent:@"code"];
      NSString *classChangesDir = [codeDir stringByAppendingPathComponent:@"class-changes"];
      NSString *localeChangesDir = [codeDir stringByAppendingPathComponent:@"locale-changes"];

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
          [SKZipUtils extractZipFile:jarPath toDirectory:rsrcDir checkProtected:NO protectedFiles:nil];
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

      NSMutableDictionary *globalLocaleChanges = [NSMutableDictionary dictionary];

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

          NSDictionary *json = [SKZipUtils readModMetadataFromZip:modPath];
          NSDictionary *modObj = json[@"mod"] ?: json;
          NSString *modType = nil;
          NSString *pxVersion = nil;
          NSString *modName = modFile;
          NSDictionary *localeChanges = nil;

          if ([modObj isKindOfClass:[NSDictionary class]]) {
              modName = modObj[@"name"] ?: modFile;
              modType = modObj[@"type"];
              pxVersion = modObj[@"pxVersion"];
              localeChanges = modObj[@"locale"];
          }

          BOOL isClassMod = (modType && [modType caseInsensitiveCompare:@"class"] == NSOrderedSame);

          if (isModpack) {
              NSString *tempPack = [modsPath stringByAppendingPathComponent:@".temp_pack"];
              [fm removeItemAtPath:tempPack error:nil];
              [fm createDirectoryAtPath:tempPack withIntermediateDirectories:YES attributes:nil error:nil];

              [SKZipUtils extractZipFile:modPath toDirectory:tempPack checkProtected:NO protectedFiles:nil];

              NSArray *innerFiles = [fm contentsOfDirectoryAtPath:tempPack error:nil];
              NSInteger innerApplied = 0;
              for (NSString *innerFile in innerFiles) {
                  if ([innerFile hasSuffix:@".zip"]) {
                      NSString *innerPath = [tempPack stringByAppendingPathComponent:innerFile];

                      NSDictionary *innerJson = [SKZipUtils readModMetadataFromZip:innerPath];
                      NSDictionary *innerModObj = innerJson[@"mod"] ?: innerJson;
                      NSString *innerType = nil;
                      NSString *innerPx = nil;
                      NSString *innerName = innerFile;
                      NSDictionary *innerLocale = nil;
                      if ([innerModObj isKindOfClass:[NSDictionary class]]) {
                          innerName = innerModObj[@"name"] ?: innerFile;
                          innerType = innerModObj[@"type"];
                          innerPx = innerModObj[@"pxVersion"];
                          innerLocale = innerModObj[@"locale"];
                      }

                      BOOL innerIsClass = (innerType && [innerType caseInsensitiveCompare:@"class"] == NSOrderedSame);
                      if (innerIsClass) {
                          if (!innerPx || !gameVersion ||
                              [innerPx caseInsensitiveCompare:gameVersion] == NSOrderedSame) {
                              [SKZipUtils extractZipFile:innerPath
                                             toDirectory:classChangesDir
                                          checkProtected:YES
                                          protectedFiles:protectedFiles];
                              classMods++;
                              hasClassMods = YES;
                              innerApplied++;
                          } else {
                              skipped++;
                              [warnings addObject:[NSString stringWithFormat:@"Class mod '%@' requires game version %@ "
                                                                             @"but current is %@ - SKIPPED",
                                                                             innerName, innerPx, gameVersion]];
                          }
                      } else {
                          [SKZipUtils extractZipFile:innerPath
                                         toDirectory:rsrcDir
                                      checkProtected:YES
                                      protectedFiles:protectedFiles];
                          resourceMods++;
                          innerApplied++;
                      }

                      if (innerLocale) {
                          for (NSString *bundle in innerLocale) {
                              NSMutableDictionary *bundleChanges = globalLocaleChanges[bundle];
                              if (!bundleChanges) {
                                  bundleChanges = [NSMutableDictionary dictionary];
                                  globalLocaleChanges[bundle] = bundleChanges;
                              }
                              [bundleChanges addEntriesFromDictionary:innerLocale[bundle]];
                          }
                      }
                  }
              }
              if (innerApplied > 0)
                  modpacks++;
              [fm removeItemAtPath:tempPack error:nil];
          } else if (isClassMod) {
              if (!pxVersion || !gameVersion || [pxVersion caseInsensitiveCompare:gameVersion] == NSOrderedSame) {
                  [SKZipUtils extractZipFile:modPath toDirectory:classChangesDir checkProtected:NO protectedFiles:nil];
                  classMods++;
                  hasClassMods = YES;
              } else {
                  skipped++;
                  [warnings
                      addObject:[NSString stringWithFormat:
                                              @"Class mod '%@' requires game version %@ but current is %@ - SKIPPED",
                                              modName, pxVersion, gameVersion]];
              }
          } else {
              [SKZipUtils extractZipFile:modPath toDirectory:rsrcDir checkProtected:NO protectedFiles:nil];
              resourceMods++;
          }

          if (localeChanges) {
              for (NSString *bundle in localeChanges) {
                  NSMutableDictionary *bundleChanges = globalLocaleChanges[bundle];
                  if (!bundleChanges) {
                      bundleChanges = [NSMutableDictionary dictionary];
                      globalLocaleChanges[bundle] = bundleChanges;
                  }
                  [bundleChanges addEntriesFromDictionary:localeChanges[bundle]];
              }
          }
      }

      if (hasClassMods) {
          dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(0.95f, @"Merging class changes into config.jar…");
          });
          NSString *configJar = [codeDir stringByAppendingPathComponent:@"config.jar"];
          if ([fm fileExistsAtPath:configJar]) {
              [SKZipUtils extractJarWithoutOverwrite:configJar toDirectory:classChangesDir];

              NSString *configNewJar = [codeDir stringByAppendingPathComponent:@"config-new.jar"];
              NSString *configOldJar = [codeDir stringByAppendingPathComponent:@"config-old.jar"];

              [SKZipUtils createZipFileFromDirectory:classChangesDir toZipPath:configNewJar];

              [fm removeItemAtPath:configOldJar error:nil];
              if ([fm moveItemAtPath:configJar toPath:configOldJar error:nil]) {
                  if ([fm moveItemAtPath:configNewJar toPath:configJar error:nil]) {
                      [fm removeItemAtPath:configOldJar error:nil];
                  } else {
                      [fm moveItemAtPath:configOldJar toPath:configJar error:nil];
                  }
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

              [SKZipUtils extractZipFile:projectxConfig
                             toDirectory:localeChangesDir
                          checkProtected:NO
                          protectedFiles:nil];

              for (NSString *bundlePath in globalLocaleChanges) {
                  NSString *propsPath = [localeChangesDir
                      stringByAppendingPathComponent:[@"rsrc/i18n/" stringByAppendingString:bundlePath]];
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
                      [newContent writeToFile:propsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                  }
              }

              NSString *newJar = [codeDir stringByAppendingPathComponent:@"projectx-config-new.jar"];
              NSString *oldJar = [codeDir stringByAppendingPathComponent:@"projectx-config-old.jar"];
              [SKZipUtils createZipFileFromDirectory:localeChangesDir toZipPath:newJar];

              [fm removeItemAtPath:oldJar error:nil];
              if ([fm moveItemAtPath:projectxConfig toPath:oldJar error:nil]) {
                  if ([fm moveItemAtPath:newJar toPath:projectxConfig error:nil]) {
                      [fm removeItemAtPath:oldJar error:nil];
                  } else {
                      [fm moveItemAtPath:oldJar toPath:projectxConfig error:nil];
                  }
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
                        (void (^)(BOOL success, NSString *_Nullable summary, NSError *_Nullable error))completionBlock {
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
          [SKZipUtils extractZipFile:jarPath toDirectory:rsrcDir checkProtected:NO protectedFiles:nil];
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
