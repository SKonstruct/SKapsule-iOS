#import "NativeBridge.h"
#import <errno.h>
#import <pthread.h>
#import <time.h>

// The handlers are set from the main thread and read from the JVM's threads.
static SKBootStatusBlock _bootStatusHandler;
static SKRenderReadyBlock _renderReadyHandler;
static SKPromptDeviceCodeBlock _promptDeviceCodeHandler;
static SKPromptEmailCodeBlock _promptEmailCodeHandler;

// Rendezvous for blocking Steam Guard prompts: the JVM thread waits on the
// condition while the UI thread sets _submittedCode and signals.
static pthread_mutex_t _codeMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t _codeCond = PTHREAD_COND_INITIALIZER;
static NSString *_submittedCode = nil;

// Long enough for an authenticator app or an email round trip, short enough that an alert
// that never appeared (or was lost) cannot park the JVM thread for good.
static const int kCodeTimeoutSeconds = 5 * 60;

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

+ (void)setPromptDeviceCodeHandler:(SKPromptDeviceCodeBlock)handler {
    @synchronized(self) {
        _promptDeviceCodeHandler = [handler copy];
    }
}

+ (void)setPromptEmailCodeHandler:(SKPromptEmailCodeBlock)handler {
    @synchronized(self) {
        _promptEmailCodeHandler = [handler copy];
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

+ (NSString *)promptForDeviceCode:(BOOL)prevWrong {
    SKPromptDeviceCodeBlock handler;
    @synchronized(self) {
        handler = _promptDeviceCodeHandler;
    }
    if (!handler)
        return @"";

    // Clear before the prompt goes up: clearing inside awaitCode would discard a code
    // submitted between the dispatch and the wait, hanging the JVM thread for good.
    [self resetCode];

    // Dispatch the prompt to the UI thread
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(prevWrong);
    });

    // Block the JVM thread until submitCode is called
    return [self awaitCode];
}

+ (NSString *)promptForEmailCode:(NSString *)email prevWrong:(BOOL)prevWrong {
    SKPromptEmailCodeBlock handler;
    @synchronized(self) {
        handler = _promptEmailCodeHandler;
    }
    if (!handler)
        return @"";

    [self resetCode];

    dispatch_async(dispatch_get_main_queue(), ^{
      handler(email, prevWrong);
    });

    return [self awaitCode];
}

+ (void)resetCode {
    pthread_mutex_lock(&_codeMutex);
    _submittedCode = nil;
    pthread_mutex_unlock(&_codeMutex);
}

+ (NSString *)awaitCode {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += kCodeTimeoutSeconds;

    pthread_mutex_lock(&_codeMutex);
    while (_submittedCode == nil) {
        if (pthread_cond_timedwait(&_codeCond, &_codeMutex, &deadline) == ETIMEDOUT) {
            NSLog(@"[NativeBridge] no code entered within %d s; giving up", kCodeTimeoutSeconds);
            pthread_mutex_unlock(&_codeMutex);
            return @"";
        }
    }
    NSString *code = _submittedCode;
    _submittedCode = nil;
    pthread_mutex_unlock(&_codeMutex);
    return code;
}

+ (void)submitCode:(NSString *)code {
    pthread_mutex_lock(&_codeMutex);
    _submittedCode = code ?: @"";
    pthread_cond_signal(&_codeCond);
    pthread_mutex_unlock(&_codeMutex);
}

@end
