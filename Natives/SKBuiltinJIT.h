#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How SKapsule gets JIT: through the bundled helper extension (StikJIT, no other app
/// needed) or by asking the StikDebug app. Both end the same way -- a debugger attached to
/// this process running skapsule-jit.js -- so readiness is still isJITEnabled().
@interface SKBuiltinJIT : NSObject

typedef NS_ENUM(NSInteger, SKJITMethod) {
    /// The StikDebug app when it is installed, otherwise built-in JIT.
    SKJITMethodAutomatic = 0,
    SKJITMethodBuiltin,
    SKJITMethodStikDebug,
    /// TrollStore's enable-jit, before iOS 26 (the TXM needs a debugger after that).
    SKJITMethodTrollStore,
    /// A jailbreak that marks apps as debugged (Dopamine's Allow JIT in Apps), before iOS 26.
    SKJITMethodJailbreak,
};

/// The user's choice; switched to built-in when a pairing file is imported. It is never
/// changed behind the user's back after a failure: the error says what to fix.
@property (class, nonatomic) SKJITMethod method;

/// The method a request will use, with Automatic resolved.
@property (class, nonatomic, readonly) SKJITMethod resolvedMethod;

/// Whether built-in JIT is what a request will use.
@property (class, nonatomic, readonly) BOOL selected;

/// Before iOS 26 a process a debugger touched may make executable memory itself, which is all
/// TrollStore and jailbreaks provide. From iOS 26 (the TXM) only a debugger that stays and
/// answers the VM can, so those two methods are not offered.
+ (BOOL)canGrantOwnJIT;
+ (BOOL)installedWithTrollStore;
+ (BOOL)jailbreakPresent;
/// Whether the process was already marked as debugged when it started, which is what a
/// jailbreak that allows JIT in apps does to every app it launches.
+ (BOOL)debuggedAtLaunch;
+ (void)noteLaunchState;

/// How the saved pairing file got here: @"onDevice", @"imported", or nil when there is none.
+ (nullable NSString *)pairingSource;

/// Whether the StikDebug app is installed.
+ (BOOL)stikDebugInstalled;

/// Why built-in JIT cannot run in this install, or nil when it can.
+ (nullable NSString *)unavailableReason;

+ (BOOL)hasPairingFile;

/// Where the imported pairing file lives (Library, not Documents).
+ (NSString *)pairingPath;

/// Copies a user-picked pairing file into the app. Returns an error message, or nil.
+ (nullable NSString *)importPairingFileFromURL:(NSURL *)url;

/// Stores pairing file bytes (picked, or made by on-device pairing) and selects built-in JIT.
/// `source` is @"imported" or @"onDevice". Returns an error message, or nil.
+ (nullable NSString *)savePairingData:(NSData *)data source:(NSString *)source;

/// Asks the helper to @"prepare" (check LocalDevVPN, mount the Developer Disk Image) or
/// @"reset" (drop its cached disk image). Completion runs on the main queue.
+ (void)perform:(NSString *)operation completion:(void (^)(BOOL ok, NSString *message))completion;

/// Starts the built-in helper whatever the selected method is (the JIT Setup sheet's Enable page).
/// `failure` runs on the main queue with a message for the user.
+ (void)enableBuiltInWithFailure:(void (^)(NSString *message))failure;

/// Requests JIT for this process by whichever method is selected. Success means the
/// request was started; readiness arrives through isJITEnabled(). `failure` runs on the
/// main queue with a message for the user.
+ (void)requestJITWithFailure:(void (^)(NSString *message))failure;

@end

NS_ASSUME_NONNULL_END
