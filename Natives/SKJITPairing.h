#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Pairs this device with itself for built-in JIT, with no computer (iOS 27 and later).
///
/// iOS 27 lists every `_remotepairing-pairable-host._tcp` service on the local network under
/// Settings > Privacy & Security > Developer Mode, and pairing with one asks for a PIN the
/// "computer" shows. This publishes such a service (libskrppairing.a, Natives/RPPairing, runs the
/// pairing), exposes the PIN, and stores the resulting pairing file where built-in JIT reads it.
///
/// The user pairs from Settings, so the app has to keep running in the background: a
/// continued-processing task (its progress UI shows the PIN too) where iOS grants one, otherwise
/// only the short background grace period. State is read through the class methods below and
/// announced with SKJITPairingDidChange, on the main queue.
typedef NS_ENUM(NSInteger, SKJITPairingPhase) {
    SKJITPairingPhaseIdle = 0,
    /// Advertised; the user pairs from Settings.
    SKJITPairingPhaseWaiting,
    /// The device asked for the code.
    SKJITPairingPhasePin,
    SKJITPairingPhasePaired,
    SKJITPairingPhaseFailed,
};

extern NSNotificationName const SKJITPairingDidChange;

@interface SKJITPairing : NSObject

+ (BOOL)supported;
+ (SKJITPairingPhase)phase;
/// The code to type on the device, while the phase is Pin.
+ (nullable NSString *)pin;
/// The paired device's name, once Paired.
+ (nullable NSString *)deviceName;
/// What went wrong, once Failed.
+ (nullable NSString *)failure;
/// iOS refused a continued task, so the app only gets the short background grace period.
+ (BOOL)backgroundLimited;

+ (void)start;
/// Stops a pairing in progress and returns to Idle.
+ (void)cancel;
/// Forgets a finished or failed attempt so the next one starts clean.
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
