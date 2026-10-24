#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How SKapsule gets JIT: through the bundled helper extension (StikJIT, no other app
/// needed) or by asking the StikDebug app. Both end the same way -- a debugger attached to
/// this process running skapsule-jit.js -- so readiness is still isJITEnabled().
@interface SKBuiltinJIT : NSObject

/// The user's choice; switched on when a pairing file is imported.
@property (class, nonatomic) BOOL selected;

/// Why built-in JIT cannot run in this install, or nil when it can.
+ (nullable NSString *)unavailableReason;

+ (BOOL)hasPairingFile;

/// Where the imported pairing file lives (Library, not Documents).
+ (NSString *)pairingPath;

/// Copies a user-picked pairing file into the app. Returns an error message, or nil.
+ (nullable NSString *)importPairingFileFromURL:(NSURL *)url;

/// Asks the helper to @"prepare" (check LocalDevVPN, mount the Developer Disk Image) or
/// @"reset" (drop its cached disk image). Completion runs on the main queue.
+ (void)perform:(NSString *)operation completion:(void (^)(BOOL ok, NSString *message))completion;

/// Requests JIT for this process by whichever method is selected. Success means the
/// request was started; readiness arrives through isJITEnabled(). `failure` runs on the
/// main queue with a message for the user.
+ (void)requestJITWithFailure:(void (^)(NSString *message))failure;

@end

NS_ASSUME_NONNULL_END
