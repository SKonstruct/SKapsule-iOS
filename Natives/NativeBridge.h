#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Boot-phase status callbacks (JVM → UI)
typedef void (^SKBootStatusBlock)(NSString *message);
typedef void (^SKRenderReadyBlock)(void);

// Steam Guard credential prompt callbacks (JVM → UI, blocking)
typedef void (^SKPromptDeviceCodeBlock)(BOOL prevWrong);
typedef void (^SKPromptEmailCodeBlock)(NSString *email, BOOL prevWrong);

@interface SKNativeBridge : NSObject

// Register callbacks from GameViewController
+ (void)setBootStatusHandler:(SKBootStatusBlock)handler;
+ (void)setRenderReadyHandler:(SKRenderReadyBlock)handler;
+ (void)setPromptDeviceCodeHandler:(SKPromptDeviceCodeBlock)handler;
+ (void)setPromptEmailCodeHandler:(SKPromptEmailCodeBlock)handler;

// Called from JVM thread (via JNI registered natives in SkBootstrap)
+ (void)onLaunchStatus:(NSString *)message;
+ (void)onRenderReady;
+ (NSString *)promptForDeviceCode:(BOOL)prevWrong;
+ (NSString *)promptForEmailCode:(NSString *)email prevWrong:(BOOL)prevWrong;

// Called from UI thread to unblock a parked prompt
+ (void)submitCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
