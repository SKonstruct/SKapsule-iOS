#pragma once

#import <Foundation/Foundation.h>
#import "SKModPack.h"
#import "SKModSync.h"

NS_ASSUME_NONNULL_BEGIN

@interface SKModManager : NSObject

+ (instancetype)sharedManager;

/// What the last check or download found since the app started; nil until then. The launcher asks
/// GitHub once per start and shows Download, Update or "up to date" from this.
@property (nonatomic, strong, nullable) SKModPackStatus *modpackStatus;

/**
 Reads the modpack listing and compares it with the mods folder without changing anything: a file whose
 size differs from the listing's is out of date without being read, only the others are hashed.
 Calls completion on the main queue with the status, or nil when it could not be found out (offline,
 rate-limited): that is not an error, the button just keeps its default.
 */
- (void)checkModpackStatusWithCompletion:(void (^)(SKModPackStatus *_Nullable status))completion;

/**
 Downloads mods from the remote mod repository on GitHub, checking local SHA hashes.
 Calls progress block with float values from 0.0 to 1.0.
 */
- (void)downloadModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                      completion:(void (^)(BOOL success, NSString *_Nullable summary,
                                           NSError *_Nullable error))completionBlock;

/**
 Extracts resources, merges class overrides into config.jar, and patches locale files in projectx-config.jar.
 Calls progress block with float values from 0.0 to 1.0.
 */
- (void)applyModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                   completion:(void (^)(BOOL success, NSString *_Nullable summary,
                                        NSArray<NSString *> *_Nullable warnings,
                                        NSError *_Nullable error))completionBlock;

/// What the launcher should do by itself now (SKModSync.h): apply after the mods folder changed, restore after every
/// mod was removed, else nothing. Cheap, reads only file attributes; main thread.
- (SKModSyncAction)pendingSyncAction;
/// The fingerprint that decision rests on. The launcher remembers a failed one, so it reports once, not on every return.
- (NSString *)syncKey;

/**
 Restores the original game files by removing all applied mod overrides ("Reset Game Files").
 */
- (void)removeModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                    completion:
                        (void (^)(BOOL success, NSString *_Nullable summary, NSError *_Nullable error))completionBlock;

/**
 Keeps a verified copy of a code jar ("config.jar") before something other than the game edits it,
 so a later restore needs no network. Does nothing if the jar isn't the game's own. Call off the main queue.
 */
+ (void)preservePristineCodeJarNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
