#import "NativeBridge.h"

// The handlers are set from the main thread and read from the JVM's threads.
static SKBootStatusBlock _bootStatusHandler;
static SKRenderReadyBlock _renderReadyHandler;
static SKShowSignInBlock _showSignInHandler;
static SKHideSignInBlock _hideSignInHandler;

// _signInActive spans first show to hide, so a re-show for a rotated challenge keeps a Cancel
// that raced it. Guarded by @synchronized(self).
static BOOL _signInActive;
static BOOL _signInCancelled;

@implementation SKNativeBridge

+ (void)setBootStatusHandler:(SKBootStatusBlock)handler {
    @synchronized(self) {
        _bootStatusHandler = [handler copy];
    }
}

+ (void)setRenderReadyHandler:(SKRenderReadyBlock)handler {
    @synchronized(self) {
        _renderReadyHandler = [handler copy];
    }
}

+ (void)setShowSignInHandler:(SKShowSignInBlock)handler {
    @synchronized(self) {
        _showSignInHandler = [handler copy];
    }
}

+ (void)setHideSignInHandler:(SKHideSignInBlock)handler {
    @synchronized(self) {
        _hideSignInHandler = [handler copy];
    }
}

+ (void)onLaunchStatus:(NSString *)message {
    NSLog(@"[NativeBridge] launchStatus: %@", message);
    SKBootStatusBlock handler;
    @synchronized(self) {
        handler = _bootStatusHandler;
    }
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
          handler(message);
        });
    }
}

+ (void)onRenderReady {
    NSLog(@"[NativeBridge] renderReady");
    SKRenderReadyBlock handler;
    @synchronized(self) {
        handler = _renderReadyHandler;
    }
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
          handler();
        });
    }
}

+ (void)onShowSignIn:(NSString *)challengeUrl modules:(NSString *)qrModules {
    SKShowSignInBlock handler;
    @synchronized(self) {
        handler = _showSignInHandler;
        if (!_signInActive) {
            _signInActive = YES;
            _signInCancelled = NO;
        }
        // Nothing to show it with: report it as cancelled so the login falls back at once
        // rather than waiting out the whole approval window.
        if (!handler) _signInCancelled = YES;
    }
    if (!handler) {
        NSLog(@"[NativeBridge] no sign-in handler; cancelling");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(challengeUrl, qrModules);
    });
}

+ (void)onHideSignIn {
    SKHideSignInBlock handler;
    @synchronized(self) {
        _signInActive = NO;
        handler = _hideSignInHandler;
    }
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
          handler();
        });
    }
}

+ (BOOL)signInCancelled {
    @synchronized(self) {
        return _signInCancelled;
    }
}

+ (void)cancelSignIn {
    @synchronized(self) {
        _signInCancelled = YES;
    }
}

@end
