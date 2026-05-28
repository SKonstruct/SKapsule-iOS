#pragma once

#import <Foundation/Foundation.h>

@interface SKInstaller : NSObject
+ (BOOL)isInstalled;
+ (void)installWithProgress:(void (^)(NSString *status))progress;
+ (NSString *)credFilePath;
@end
