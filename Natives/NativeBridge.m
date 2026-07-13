#import "NativeBridge.h"
#import <pthread.h>

static SKBootStatusBlock _bootStatusHandler;
static SKRenderReadyBlock _renderReadyHandler;
static SKPromptDeviceCodeBlock _promptDeviceCodeHandler;
static SKPromptEmailCodeBlock _promptEmailCodeHandler;

// Rendezvous for blocking Steam Guard prompts: the JVM thread waits on the
// condition while the UI thread sets _submittedCode and signals.
static pthread_mutex_t _codeMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t _codeCond = PTHREAD_COND_INITIALIZER;
static NSString *_submittedCode = nil;

@implementation SKNativeBridge

+ (void)setBootStatusHandler:(SKBootStatusBlock)handler {
    _bootStatusHandler = [handler copy];
}

+ (void)setRenderReadyHandler:(SKRenderReadyBlock)handler {
    _renderReadyHandler = [handler copy];
}

+ (void)setPromptDeviceCodeHandler:(SKPromptDeviceCodeBlock)handler {
    _promptDeviceCodeHandler = [handler copy];
}

+ (void)setPromptEmailCodeHandler:(SKPromptEmailCodeBlock)handler {
    _promptEmailCodeHandler = [handler copy];
}

+ (void)onLaunchStatus:(NSString *)message {
    NSLog(@"[NativeBridge] launchStatus: %@", message);
    if (_bootStatusHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
          _bootStatusHandler(message);
        });
    }
}

+ (void)onRenderReady {
    NSLog(@"[NativeBridge] renderReady");
    if (_renderReadyHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
          _renderReadyHandler();
        });
    }
}

+ (NSString *)promptForDeviceCode:(BOOL)prevWrong {
    if (!_promptDeviceCodeHandler)
        return @"";

    // Dispatch the prompt to the UI thread
    dispatch_async(dispatch_get_main_queue(), ^{
      _promptDeviceCodeHandler(prevWrong);
    });

    // Block the JVM thread until submitCode is called
    return [self awaitCode];
}

+ (NSString *)promptForEmailCode:(NSString *)email prevWrong:(BOOL)prevWrong {
    if (!_promptEmailCodeHandler)
        return @"";

    dispatch_async(dispatch_get_main_queue(), ^{
      _promptEmailCodeHandler(email, prevWrong);
    });

    return [self awaitCode];
}

+ (NSString *)awaitCode {
    pthread_mutex_lock(&_codeMutex);
    _submittedCode = nil;
    while (_submittedCode == nil) {
        pthread_cond_wait(&_codeCond, &_codeMutex);
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
