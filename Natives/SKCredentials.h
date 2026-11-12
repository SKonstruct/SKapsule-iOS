#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The optional login saved for a custom server, for quick sign-in. Kept in the Keychain, readable only
/// while the device is unlocked and never copied to backups or other devices.
@interface SKCredentials : NSObject

+ (BOOL)saveUsername:(NSString *)username password:(NSString *)password forServerId:(NSString *)serverId;
/// @return a dictionary with @"username" and @"password", or nil if none is saved.
+ (nullable NSDictionary<NSString *, NSString *> *)loginForServerId:(NSString *)serverId;
+ (void)deleteLoginForServerId:(NSString *)serverId;

@end

NS_ASSUME_NONNULL_END
