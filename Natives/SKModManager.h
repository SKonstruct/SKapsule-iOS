#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SKModManager : NSObject

+ (instancetype)sharedManager;

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

/**
 Restores the original game files by removing all applied mod overrides.
 */
- (void)removeModsWithProgress:(void (^)(float progress, NSString *status))progressBlock
                    completion:
                        (void (^)(BOOL success, NSString *_Nullable summary, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
