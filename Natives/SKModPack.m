#import "SKModPack.h"

@interface SKModPackStatus ()
- (instancetype)initWithState:(SKModPackState)state toDownload:(NSInteger)toDownload toDelete:(NSInteger)toDelete;
@end

@implementation SKModPackStatus

- (instancetype)initWithState:(SKModPackState)state toDownload:(NSInteger)toDownload toDelete:(NSInteger)toDelete {
    self = [super init];
    if (self) {
        _state = state;
        _toDownload = toDownload;
        _toDelete = toDelete;
    }
    return self;
}

+ (instancetype)currentStatus {
    return [[self alloc] initWithState:SKModPackStateCurrent toDownload:0 toDelete:0];
}

+ (instancetype)statusForRemoteNames:(NSArray<NSString *> *)remoteNames
                              synced:(NSSet<NSString *> *)synced
                              exists:(BOOL (^)(NSString *name))exists
                           isCurrent:(BOOL (^)(NSString *name))isCurrent {
    NSSet<NSString *> *remote = [NSSet setWithArray:remoteNames];
    NSInteger toDownload = 0;
    BOOL installed = NO;
    for (NSString *name in remoteNames) {
        if (!isCurrent(name)) toDownload++;
        if (exists(name)) installed = YES;
    }
    NSInteger toDelete = 0;
    for (NSString *name in synced) {
        if (!exists(name)) continue;
        installed = YES;
        if (![remote containsObject:name]) toDelete++;
    }
    SKModPackState state = SKModPackStateCurrent;
    if (installed && toDownload + toDelete > 0) {
        state = SKModPackStateUpdate;
    } else if (!installed && toDownload > 0) {
        state = SKModPackStateNotInstalled;
    }
    return [[self alloc] initWithState:state toDownload:toDownload toDelete:toDelete];
}

@end
