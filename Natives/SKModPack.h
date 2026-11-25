#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SKModPackState) {
    SKModPackStateNotInstalled,
    SKModPackStateUpdate,
    SKModPackStateCurrent,
};

/// Whether the modpack in the mods folder matches the published one, decided as SKradle and Android's
/// `ModsDownloader.packStatus` decide it. Foundation only, so it builds in a plain macOS test.
@interface SKModPackStatus : NSObject
@property (nonatomic, readonly) SKModPackState state;
/// Files a sync would fetch, and files a sync would drop.
@property (nonatomic, readonly) NSInteger toDownload;
@property (nonatomic, readonly) NSInteger toDelete;

/// The pack counts as installed when any of its files is here. With a file to fetch or to drop it is an
/// update, with none it is current, and with nothing installed yet it is "not installed". `exists` says
/// whether a name is in the mods folder at all, `isCurrent` whether that file matches the listing. Only
/// names in `synced` (written by an earlier sync) are ever dropped: the folder also holds the player's own mods.
+ (instancetype)statusForRemoteNames:(NSArray<NSString *> *)remoteNames
                              synced:(NSSet<NSString *> *)synced
                              exists:(BOOL (^)(NSString *name))exists
                           isCurrent:(BOOL (^)(NSString *name))isCurrent;

+ (instancetype)currentStatus;
@end

NS_ASSUME_NONNULL_END
