#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Boot-phase status callbacks (JVM → UI)
typedef void (^SKBootStatusBlock)(NSString *message);
typedef void (^SKRenderReadyBlock)(void);

// Steam sign-in callbacks (JVM → UI). qrModules is rows separated by "\n", '1' dark and '0' light,
// without a quiet zone.
typedef void (^SKShowSignInBlock)(NSString *challengeUrl, NSString *qrModules);
typedef void (^SKHideSignInBlock)(void);

@interface SKNativeBridge : NSObject

// Register callbacks from GameViewController
+ (void)setBootStatusHandler:(SKBootStatusBlock)handler;
+ (void)setRenderReadyHandler:(SKRenderReadyBlock)handler;
+ (void)setShowSignInHandler:(nullable SKShowSignInBlock)handler;
+ (void)setHideSignInHandler:(nullable SKHideSignInBlock)handler;

// Called from JVM thread (via JNI registered natives in SkBootstrap)
+ (void)onLaunchStatus:(NSString *)message;
+ (void)onRenderReady;
+ (void)onShowSignIn:(NSString *)challengeUrl modules:(NSString *)qrModules;
+ (void)onHideSignIn;
+ (BOOL)signInCancelled;

// Called from UI thread when the user cancels the sign-in
+ (void)cancelSignIn;

@end

NS_ASSUME_NONNULL_END
