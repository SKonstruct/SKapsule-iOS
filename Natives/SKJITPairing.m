#import "SKJITPairing.h"

#import <BackgroundTasks/BackgroundTasks.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <dns_sd.h>
#import <stdatomic.h>

#import "SKBuiltinJIT.h"
#import "SKRPPairing.h"

// What the device shows in Settings as "Pair with <name>".
static NSString *const kHostName = @"SKapsule";
static NSString *const kServiceType = @"_remotepairing-pairable-host._tcp";
// A pairing nobody finished is stopped, so the listener and the background task do not linger.
static const NSTimeInterval kPairingTimeout = 300;

@interface SKJITPairing ()
+ (void)cancelWithReason:(NSString *)reason;
@end

static SkrpSession *gSession;
static DNSServiceRef gService;
static UIBackgroundTaskIdentifier gGraceTask;
static BOOL gHasGraceTask;
static id gContinuedTask;  // BGContinuedProcessingTask, iOS 26+
static BOOL gShowingPin;
static SKJITPairingPhase gPhase;
static NSString *gPin, *gDevice, *gFailure;
static BOOL gBackgroundLimited;
static NSString *gCancelReason;
static atomic_bool gRunning;

NSNotificationName const SKJITPairingDidChange = @"SKJITPairingDidChange";

@implementation SKJITPairing

+ (BOOL)supported {
    if (@available(iOS 27.0, *)) return YES;
    return NO;
}

+ (SKJITPairingPhase)phase { return gPhase; }
+ (NSString *)pin { return gPin; }
+ (NSString *)deviceName { return gDevice; }
+ (NSString *)failure { return gFailure; }
+ (BOOL)backgroundLimited { return gBackgroundLimited; }

+ (BOOL)running {
    return atomic_load(&gRunning);
}

+ (void)setPhase:(SKJITPairingPhase)phase {
    gPhase = phase;
    [NSNotificationCenter.defaultCenter postNotificationName:SKJITPairingDidChange object:nil];
}

#pragma mark - Background time

/// "<bundle id>.pairing.session" when "<bundle id>.pairing.*" is in BGTaskSchedulerPermittedIdentifiers. A
/// sideloader that re-signs the bundle under another identifier leaves it stale, and iOS then refuses
/// the task (the pairing goes on with only the short background grace period).
+ (nullable NSString *)continuedTaskIdentifier {
    NSArray *permitted = [NSBundle.mainBundle objectForInfoDictionaryKey:@"BGTaskSchedulerPermittedIdentifiers"];
    NSString *prefix = [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".pairing."];
    for (id entry in permitted) {
        if ([entry isKindOfClass:NSString.class] && [entry isEqualToString:[prefix stringByAppendingString:@"*"]]) {
            return [prefix stringByAppendingString:@"session"];
        }
    }
    return nil;
}

+ (void)beginBackgroundTime {
    gHasGraceTask = YES;
    gGraceTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"SKapsule pairing"
                                                            expirationHandler:^{
                                                              // Only the grace period is left when no continued task runs.
                                                              if (!gContinuedTask) {
                                                                  [self cancelWithReason:@"iOS stopped SKapsule in the "
                                                                                         @"background. Start again and go to "
                                                                                         @"Settings straight away."];
                                                              }
                                                            }];
    gBackgroundLimited = YES;
    NSString *identifier = [self continuedTaskIdentifier];
    if (!identifier) return;
    if (@available(iOS 26.0, *)) {
        // The handler is registered for the concrete identifier that is then submitted: submitting an
        // identifier nothing registered raises an exception, and registering one twice kills the app.
        static NSString *registered;
        if (![registered isEqualToString:identifier]) {
            BOOL ok = [BGTaskScheduler.sharedScheduler
                registerForTaskWithIdentifier:identifier
                                   usingQueue:dispatch_get_main_queue()
                                launchHandler:^(BGTask *task) {
                                  if (![task isKindOfClass:BGContinuedProcessingTask.class] || ![self running]) {
                                      [task setTaskCompletedWithSuccess:NO];
                                      return;
                                  }
                                  BGContinuedProcessingTask *continued = (BGContinuedProcessingTask *)task;
                                  // A continued task is shown with progress; one that never reports any is ended.
                                  continued.progress.totalUnitCount = 2;
                                  continued.progress.completedUnitCount = gShowingPin ? 1 : 0;
                                  gContinuedTask = continued;
                                  continued.expirationHandler = ^{
                                    gContinuedTask = nil;
                                    [self cancelWithReason:@"iOS stopped the pairing in the background. Try again."];
                                  };
                                }];
            if (!ok) {
                NSLog(@"[JITPairing] continued task registration refused");
                [self setPhase:gPhase];
                return;
            }
            registered = identifier;
        }
        BGContinuedProcessingTaskRequest *request =
            [[BGContinuedProcessingTaskRequest alloc] initWithIdentifier:identifier
                                                                   title:@"Pairing with SKapsule"
                                                                subtitle:@"Settings > Privacy & Security > Developer Mode"];
        request.strategy = BGContinuedProcessingTaskRequestSubmissionStrategyFail;
        NSError *error = nil;
        if ([BGTaskScheduler.sharedScheduler submitTaskRequest:request error:&error]) {
            gBackgroundLimited = NO;
        } else {
            NSLog(@"[JITPairing] continued task refused: %@", error.localizedDescription);
        }
        [self setPhase:gPhase];
    }
}

+ (void)endBackgroundTimeSuccess:(BOOL)success {
    if (@available(iOS 26.0, *)) {
        BGContinuedProcessingTask *task = gContinuedTask;
        task.progress.completedUnitCount = task.progress.totalUnitCount;
        [task setTaskCompletedWithSuccess:success];
    }
    gContinuedTask = nil;
    if (gHasGraceTask) {
        [UIApplication.sharedApplication endBackgroundTask:gGraceTask];
        gHasGraceTask = NO;
    }
}

#pragma mark - PIN

/// The code appears in the app, in the continued task's progress UI and as a notification, since
/// the user is in Settings while the device asks for it.
+ (void)showPin:(NSString *)pin {
    if (gPhase != SKJITPairingPhaseWaiting && gPhase != SKJITPairingPhasePin) return;
    gShowingPin = YES;
    gPin = pin;
    if (@available(iOS 26.0, *)) {
        BGContinuedProcessingTask *task = gContinuedTask;
        [task updateTitle:[NSString stringWithFormat:@"Pairing code %@", pin] subtitle:@"Enter it on this device to pair with SKapsule"];
        task.progress.completedUnitCount = 1;
    }
    // In the app the sheet shows it; the notification is for when the user is in Settings.
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = [NSString stringWithFormat:@"SKapsule pairing code: %@", pin];
        content.body = @"Enter this code on the pairing screen to finish.";
        [UNUserNotificationCenter.currentNotificationCenter
            addNotificationRequest:[UNNotificationRequest requestWithIdentifier:@"skapsule.pairing.pin" content:content trigger:nil]
             withCompletionHandler:nil];
    }
    [self setPhase:SKJITPairingPhasePin];
}

static void skPinCallback(const char *pin, void *context) {
    NSString *code = @(pin);
    dispatch_async(dispatch_get_main_queue(), ^{
      [SKJITPairing showPin:code];
    });
}

#pragma mark - Bonjour

static void skRegisterReply(DNSServiceRef ref, DNSServiceFlags flags, DNSServiceErrorType error, const char *name,
                            const char *type, const char *domain, void *context) {
    if (error == kDNSServiceErr_NoError) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      [SKJITPairing cancelWithReason:error == kDNSServiceErr_PolicyDenied
                                         ? @"Local Network access is off for SKapsule. Turn it on in Settings > "
                                           @"Privacy & Security > Local Network."
                                         : [NSString stringWithFormat:@"Couldn't publish the pairing service (%d).",
                                                                      (int)error]];
    });
}

/// Publishes the service through mDNSResponder, so only the Local Network permission is needed,
/// not the multicast entitlement. NULL on success, else a message.
+ (nullable NSString *)publishService {
    TXTRecordRef txt;
    uint8_t buffer[1024];
    TXTRecordCreate(&txt, sizeof(buffer), buffer);
    for (size_t i = 0; i < skrp_txt_count(gSession); i++) {
        const char *key = skrp_txt_key(gSession, i), *value = skrp_txt_value(gSession, i);
        if (key && value) TXTRecordSetValue(&txt, key, (uint8_t)strlen(value), value);
    }
    DNSServiceErrorType error = DNSServiceRegister(&gService, 0, 0, skrp_service_name(gSession), kServiceType.UTF8String,
                                                   NULL, NULL, htons(skrp_port(gSession)), TXTRecordGetLength(&txt),
                                                   TXTRecordGetBytesPtr(&txt), skRegisterReply, NULL);
    TXTRecordDeallocate(&txt);
    if (error != kDNSServiceErr_NoError) {
        gService = NULL;
        return [NSString stringWithFormat:@"Couldn't publish the pairing service (%d).", (int)error];
    }
    DNSServiceSetDispatchQueue(gService, dispatch_get_main_queue());
    return nil;
}

#pragma mark - Run

+ (void)start {
    if (![self supported]) return;
    if (atomic_exchange(&gRunning, true)) return;
    gCancelReason = nil;
    gPin = gDevice = gFailure = nil;
    gShowingPin = NO;
    gBackgroundLimited = NO;
    [self setPhase:SKJITPairingPhaseWaiting];

    char *errorText = NULL;
    gSession = skrp_new(kHostName.UTF8String, &errorText);
    if (!gSession) {
        NSString *message = errorText ? @(errorText) : @"Couldn't start pairing.";
        if (errorText) skrp_string_free(errorText);
        [self finishWithDevice:nil error:message];
        return;
    }
    NSString *publishError = [self publishService];
    if (publishError) {
        [self finishWithDevice:nil error:publishError];
        return;
    }
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                                                                      completionHandler:^(BOOL granted, NSError *e){
                                                                      }];
    [self beginBackgroundTime];

    SkrpSession *session = gSession;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      uint8_t *plist = NULL;
      size_t length = 0;
      char *device = NULL, *failure = NULL;
      int32_t code = skrp_accept(session, skPinCallback, NULL, &plist, &length, &device, &failure);
      NSData *data = (code == 0 && plist) ? [NSData dataWithBytes:plist length:length] : nil;
      NSString *deviceName = device ? @(device) : @"this device";
      NSString *message = failure ? @(failure) : nil;
      if (plist) skrp_bytes_free(plist, length);
      if (device) skrp_string_free(device);
      if (failure) skrp_string_free(failure);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (code == 0 && data) {
            NSString *saveError = [SKBuiltinJIT savePairingData:data source:@"onDevice"];
            [self finishWithDevice:saveError ? nil : deviceName error:saveError];
        } else if (code == 2) {
            // A cancel by the user has no reason and goes back to Idle.
            [self finishWithDevice:nil error:gCancelReason];
        } else {
            [self finishWithDevice:nil error:message ?: @"Pairing failed."];
        }
      });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPairingTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gSession == session) [self cancelWithReason:@"Pairing timed out. Start again when you are ready to pair from Settings."];
    });
}

+ (void)cancel {
    gCancelReason = nil;
    if (gSession) skrp_cancel(gSession);
}

+ (void)reset {
    if (gPhase == SKJITPairingPhaseWaiting || gPhase == SKJITPairingPhasePin) return;
    gPin = gDevice = gFailure = nil;
    [self setPhase:SKJITPairingPhaseIdle];
}

+ (void)cancelWithReason:(NSString *)reason {
    if (!gSession) return;
    if (!gCancelReason) gCancelReason = reason;
    // Ends skrp_accept with 2; its completion path reports the reason.
    skrp_cancel(gSession);
}

/// The one exit: every outcome ends up here, on the main queue. Paired with a device, failed with
/// a message, or neither (the user cancelled).
+ (void)finishWithDevice:(nullable NSString *)device error:(nullable NSString *)error {
    if (gService) {
        DNSServiceRefDeallocate(gService);
        gService = NULL;
    }
    if (gSession) {
        skrp_free(gSession);
        gSession = NULL;
    }
    [self endBackgroundTimeSuccess:device != nil];
    gShowingPin = NO;
    gPin = nil;
    [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[ @"skapsule.pairing.pin" ]];
    gDevice = device;
    gFailure = error;
    atomic_store(&gRunning, false);
    [self setPhase:device ? SKJITPairingPhasePaired : error ? SKJITPairingPhaseFailed : SKJITPairingPhaseIdle];
}

@end
