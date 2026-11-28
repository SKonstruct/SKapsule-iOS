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

// The username/password sign-in (JVM → UI). kind is @"credentials", @"guard-device" or @"guard-email";
// detail is why the last credentials were refused (@"password" or another reason) for credentials and
// the masked address for guard-email; retry is YES when the previous Steam Guard code was refused.
typedef void (^SKShowSignInFormBlock)(NSString *kind, NSString *_Nullable detail, BOOL retry);

@interface SKNativeBridge : NSObject

// Register callbacks from GameViewController
+ (void)setBootStatusHandler:(SKBootStatusBlock)handler;
+ (void)setRenderReadyHandler:(SKRenderReadyBlock)handler;
+ (void)setShowSignInHandler:(nullable SKShowSignInBlock)handler;
+ (void)setHideSignInHandler:(nullable SKHideSignInBlock)handler;
+ (void)setShowSignInFormHandler:(nullable SKShowSignInFormBlock)handler;

// Called from JVM thread (via JNI registered natives in SkBootstrap)
+ (void)onLaunchStatus:(NSString *)message;
+ (void)onRenderReady;
+ (void)onShowSignIn:(NSString *)challengeUrl modules:(NSString *)qrModules;
+ (void)onHideSignIn;
+ (BOOL)signInCancelled;

// Called from UI thread when the user cancels the sign-in
+ (void)cancelSignIn;

// Called from JVM thread: the username/password forms. Nothing here is persisted; a submitted
// credential or code is handed over once and dropped.
+ (void)onShowSignInForm:(NSString *)kind detail:(nullable NSString *)detail retry:(BOOL)retry;
+ (BOOL)signInPasswordRequested;
+ (nullable NSString *)takeSignInCredentials;  // @"username\npassword", once
+ (nullable NSString *)takeSignInGuardCode;    // once

// Called from UI thread: the user chose the form (YES) or went back to the QR code (NO), then
// submitted the form or the code. Not a cancel.
+ (void)setPasswordSignInRequested:(BOOL)requested;
+ (void)submitSignInUsername:(NSString *)username password:(NSString *)password;
+ (void)submitSignInGuardCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
