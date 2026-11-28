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

// The username/password sign-in: whether the user chose it over the QR code, and what they submitted
// that the JVM has not taken yet. In memory only, dropped when taken, shown anew or the sign-in ends.
static SKShowSignInFormBlock _showSignInFormHandler;
static BOOL _passwordRequested;
static NSString *_pendingCredentials;
static NSString *_pendingGuardCode;

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

+ (void)setShowSignInFormHandler:(SKShowSignInFormBlock)handler {
    @synchronized(self) {
        _showSignInFormHandler = [handler copy];
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
            _passwordRequested = NO;
            _pendingCredentials = nil;
            _pendingGuardCode = nil;
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
        _passwordRequested = NO;
        _pendingCredentials = nil;
        _pendingGuardCode = nil;
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
        _pendingCredentials = nil;
        _pendingGuardCode = nil;
    }
}

#pragma mark - Username and password

+ (void)onShowSignInForm:(NSString *)kind detail:(NSString *)detail retry:(BOOL)retry {
    SKShowSignInFormBlock handler;
    @synchronized(self) {
        handler = _showSignInFormHandler;
        // A new form asks for new input; whatever was typed for the last one is stale.
        _pendingCredentials = nil;
        _pendingGuardCode = nil;
        if (!_signInActive) {
            _signInActive = YES;
            _signInCancelled = NO;
        }
        if (!handler) _signInCancelled = YES;
    }
    if (!handler) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(kind, detail, retry);
    });
}

+ (BOOL)signInPasswordRequested {
    @synchronized(self) {
        return _passwordRequested;
    }
}

+ (NSString *)takeSignInCredentials {
    @synchronized(self) {
        NSString *taken = _pendingCredentials;
        _pendingCredentials = nil;
        return taken;
    }
}

+ (NSString *)takeSignInGuardCode {
    @synchronized(self) {
        NSString *taken = _pendingGuardCode;
        _pendingGuardCode = nil;
        return taken;
    }
}

+ (void)setPasswordSignInRequested:(BOOL)requested {
    @synchronized(self) {
        _passwordRequested = requested;
        _pendingCredentials = nil;
        _pendingGuardCode = nil;
    }
}

+ (void)submitSignInUsername:(NSString *)username password:(NSString *)password {
    @synchronized(self) {
        _pendingCredentials = [NSString stringWithFormat:@"%@\n%@", username, password];
    }
}

+ (void)submitSignInGuardCode:(NSString *)code {
    @synchronized(self) {
        _pendingGuardCode = [code copy];
    }
}

@end
