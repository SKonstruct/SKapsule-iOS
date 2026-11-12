#import "SKCredentials.h"
#import <Security/Security.h>

static NSString *const kService = @"com.skonstruct.skapsule.server-login";

static NSMutableDictionary *SKQuery(NSString *serverId) {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kService,
        (__bridge id)kSecAttrAccount: serverId,
    } mutableCopy];
}

@implementation SKCredentials

+ (BOOL)saveUsername:(NSString *)username password:(NSString *)password forServerId:(NSString *)serverId {
    // Neither field can hold a newline (the form is single-line), so one separates them.
    NSData *data = [[NSString stringWithFormat:@"%@\n%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
    [self deleteLoginForServerId:serverId];
    NSMutableDictionary *item = SKQuery(serverId);
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

+ (NSDictionary<NSString *, NSString *> *)loginForServerId:(NSString *)serverId {
    NSMutableDictionary *query = SKQuery(serverId);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return nil;
    NSString *text = [[NSString alloc] initWithData:(__bridge_transfer NSData *)result encoding:NSUTF8StringEncoding];
    NSRange split = [text rangeOfString:@"\n"];
    if (split.location == NSNotFound || split.location == 0 || NSMaxRange(split) == text.length) return nil;
    return @{@"username": [text substringToIndex:split.location], @"password": [text substringFromIndex:NSMaxRange(split)]};
}

+ (void)deleteLoginForServerId:(NSString *)serverId {
    SecItemDelete((__bridge CFDictionaryRef)SKQuery(serverId));
}

@end
