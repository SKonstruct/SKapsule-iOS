#import "SKReporter.h"
#import <UIKit/UIKit.h>
#import <os/proc.h>
#import <sys/sysctl.h>
#import "config.h"
#import "utils.h"

NSString *const SKReportingEnabledKey = @"crash_reporting";

/**
 * Minimal Sentry client: builds an envelope and POSTs it.
 *
 * The Cocoa SDK is deliberately not used. Its crash handler installs a Mach
 * exception port and signal handlers, but the bundled HotSpot uses SIGSEGV and
 * SIGBUS for implicit null checks and JavaLauncher resets those to SIG_DFL right
 * before JLI_Launch; on-device runs also happen under StikDebug, which the SDK
 * detects as a debugger and stops reporting under. With crash handling,
 * app-hang tracking and swizzling all off, what remains of the SDK is an HTTPS
 * POST -- which is this file. The signal it cannot see either way is the one
 * that matters here: the JVM writes its own crash report to disk, and that is
 * what gets picked up on the next launch.
 */

static NSString *const kDSN =
  @"https://dc1484368794de00f34257b784cb33e4@o458165.ingest.us.sentry.io/4511958848438272";
static NSString *const kEnvelopeURL =
  @"https://o458165.ingest.us.sentry.io/api/4511958848438272/envelope/";

static NSString *const kReportedKey = @"crash_reported";
static NSString *const kBackoffKey = @"sentry_backoff_until";

// Release health: one session per launch, so the Releases page can show adoption and a
// crash-free rate for iOS the way it already does for Android.
static NSString *const kSessionIdKey = @"sentry_session_id";
static NSString *const kSessionStartKey = @"sentry_session_started";

/** hs_err bodies are capped; the log tail is smaller because only the end matters. */
static const NSUInteger kMaxHsErrBytes = 512 * 1024;
static const NSUInteger kMaxLogTailBytes = 64 * 1024;

#pragma mark - Consent & rate limiting

static BOOL sk_consent(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id value = [defaults objectForKey:SKReportingEnabledKey];
    return value == nil ? YES : [value boolValue];
}

static BOOL sk_backedOff(void) {
    NSDate *until = [NSUserDefaults.standardUserDefaults objectForKey:kBackoffKey];
    return until != nil && until.timeIntervalSinceNow > 0;
}

#pragma mark - Scrubbing

/**
 * Redacts what the JVM's output is known to carry: Steam/getdown credentials and
 * tokens, the player's account email, and the container path (which embeds the
 * device username on TrollStore installs).
 */
static NSString *sk_scrub(NSString *text) {
    if (text.length == 0) return text;
    static NSRegularExpression *secrets, *emails;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      secrets = [NSRegularExpression
        regularExpressionWithPattern:@"(FRENCHPRESS_STEAM_USER|FRENCHPRESS_STEAM_PASS|pass(word|wd)?"
                                     @"|token|session|auth|cookie|ticket|secret)\\s*[=:]\\s*\\S+"
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
      emails = [NSRegularExpression regularExpressionWithPattern:@"[\\w.+-]+@[\\w-]+\\.[\\w.]{2,}"
                                                        options:0
                                                          error:nil];
    });

    NSMutableString *out = [text mutableCopy];
    [secrets replaceMatchesInString:out
                            options:0
                              range:NSMakeRange(0, out.length)
                       withTemplate:@"$1=[redacted]"];
    [emails replaceMatchesInString:out
                           options:0
                             range:NSMakeRange(0, out.length)
                      withTemplate:@"[redacted-email]"];

    for (NSString *var in @[ @"SKAPSULE_HOME", @"HOME" ]) {
        const char *dir = getenv(var.UTF8String);
        if (dir && strlen(dir) > 1) {
            [out replaceOccurrencesOfString:@(dir)
                                 withString:@"<home>"
                                    options:0
                                      range:NSMakeRange(0, out.length)];
        }
    }
    return out;
}

#pragma mark - Event assembly

static NSString *sk_deviceModel(void) {
    char model[64] = {0};
    size_t size = sizeof(model);
    if (sysctlbyname("hw.machine", model, &size, NULL, 0) != 0) return @"unknown";
    return @(model);
}

static NSString *sk_installType(void) {
    NSString *trollStore =
      [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    if (!access(trollStore.UTF8String, F_OK)) return @"TrollStore";
    return access("/var/mobile", F_OK) == 0 ? @"Jailbroken" : @"Sideloaded";
}

/// Fields shared by every event. No `user`, no `server_name`, no device name.
static NSMutableDictionary *sk_event(NSString *level) {
    NSString *eventId = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-"
                                                                         withString:@""]
                          .lowercaseString;
    return [@{
        @"event_id" : eventId,
        @"timestamp" : @(NSDate.date.timeIntervalSince1970),
        @"platform" : @"native",
        @"logger" : @"skapsule",
        @"level" : level,
        @"release" : [NSString stringWithFormat:@"skapsule-ios@%s", CONFIG_VERSION],
        @"dist" : @CONFIG_COMMIT,
        @"environment" : @CONFIG_TYPE,
        @"sdk" : @{@"name" : @"skapsule.ios.minimal", @"version" : @CONFIG_VERSION},
        @"tags" : @{
            @"branch" : @CONFIG_BRANCH,
            @"jit" : isJITEnabled(NO) ? @"yes" : @"no",
            @"txm" : DeviceHasTXM() ? @"yes" : @"no",
            @"install_type" : sk_installType(),
        },
        @"contexts" : @{
            @"device" : @{
                @"type" : @"device",
                @"model" : sk_deviceModel(),
                @"arch" : @"arm64",
                @"memory_size" : @(NSProcessInfo.processInfo.physicalMemory),
                @"free_memory" : @(os_proc_available_memory()),
                @"simulator" : @NO,
            },
            @"os" : @{
                @"type" : @"os",
                @"name" : @"iOS",
                @"version" : UIDevice.currentDevice.systemVersion,
            },
            @"app" : @{
                @"type" : @"app",
                @"app_identifier" : NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"app_version" : @CONFIG_VERSION,
            },
        },
    } mutableCopy];
}

#pragma mark - Transport

/// Item payloads are appended verbatim, so `length` must be the byte count.
static void sk_appendItem(NSMutableData *envelope, NSDictionary *header, NSData *payload) {
    NSMutableDictionary *withLength = [header mutableCopy];
    withLength[@"length"] = @(payload.length);
    [envelope appendData:[NSJSONSerialization dataWithJSONObject:withLength options:0 error:nil]];
    [envelope appendBytes:"\n" length:1];
    [envelope appendData:payload];
    [envelope appendBytes:"\n" length:1];
}

/**
 * @param onSent  called with YES when the event is delivered, or when the server
 *                rejects it in a way retrying cannot fix. NO means "try again
 *                next launch" — that is the whole of the offline handling.
 */
static void sk_send(NSDictionary *event, NSArray<NSDictionary *> *attachments,
                    void (^onSent)(BOOL)) {
    NSData *eventData = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    if (!eventData) {
        if (onSent) onSent(NO);
        return;
    }

    NSMutableData *envelope = [NSMutableData data];
    NSDictionary *envelopeHeader = @{@"event_id" : event[@"event_id"], @"dsn" : kDSN};
    [envelope appendData:[NSJSONSerialization dataWithJSONObject:envelopeHeader
                                                         options:0
                                                           error:nil]];
    [envelope appendBytes:"\n" length:1];
    sk_appendItem(envelope, @{@"type" : @"event", @"content_type" : @"application/json"},
                  eventData);
    for (NSDictionary *attachment in attachments) {
        sk_appendItem(envelope,
                      @{
                          @"type" : @"attachment",
                          @"filename" : attachment[@"filename"],
                          @"content_type" : @"text/plain",
                      },
                      attachment[@"data"]);
    }

    NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEnvelopeURL]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15;
    [request setValue:@"application/x-sentry-envelope" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = envelope;

    [[NSURLSession.sharedSession
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            NSInteger status = error ? 0 : http.statusCode;
            if (status == 429) {
                double retryAfter = [http.allHeaderFields[@"Retry-After"] doubleValue];
                [NSUserDefaults.standardUserDefaults
                  setObject:[NSDate dateWithTimeIntervalSinceNow:retryAfter > 0 ? retryAfter : 60]
                     forKey:kBackoffKey];
            }
            // A 4xx other than 429 means the envelope itself is wrong; retrying it
            // every launch forever is worse than dropping it.
            BOOL done = (status >= 200 && status < 300) || (status >= 400 && status < 500 && status != 429);
            if (!done) NSLog(@"[SKReporter] send failed (status=%ld, %@)", (long)status, error);
            if (onSent) onSent(done);
          }] resume];
}

#pragma mark - hs_err parsing

/**
 * Pulls a title and a grouping key out of a HotSpot crash report. Only the header
 * is read: everything below it rides along as the attachment.
 *
 * The fingerprint must not contain the faulting address or the load-relative
 * offset — those differ on every run, so leaving them in files each crash as its
 * own issue.
 */
static void sk_parseHsErr(NSString *text, NSString **outType, NSString **outValue,
                          NSString **outGroup) {
    *outType = @"JVM crash";
    *outValue = @"";
    *outGroup = @"";

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger limit = MIN(lines.count, (NSUInteger)40);
    for (NSUInteger i = 0; i < limit; i++) {
        NSString *line = lines[i];
        if ([line containsString:@"# SIG"] || [line containsString:@"#  SIG"]) {
            NSRange sig = [line rangeOfString:@"SIG[A-Z]+" options:NSRegularExpressionSearch];
            if (sig.location != NSNotFound) *outType = [line substringWithRange:sig];
        } else if ([line containsString:@"# Internal Error"]) {
            *outType = @"Internal Error";
        } else if ([line containsString:@"insufficient memory"]) {
            *outType = @"OutOfMemory";
        } else if ([line containsString:@"# Problematic frame:"] && i + 1 < lines.count) {
            NSString *frame = [lines[i + 1] stringByReplacingOccurrencesOfString:@"# "
                                                                     withString:@""];
            *outValue = [frame stringByTrimmingCharactersInSet:
                                 NSCharacterSet.whitespaceCharacterSet];
            *outGroup = [*outValue
              stringByReplacingOccurrencesOfString:@"\\+0x[0-9a-fA-F]+"
                                        withString:@""
                                           options:NSRegularExpressionSearch
                                             range:NSMakeRange(0, (*outValue).length)];
        }
    }
    if ((*outValue).length == 0) *outValue = *outType;
    if ((*outGroup).length == 0) *outGroup = *outType;
}

#pragma mark - Sessions

static NSString *sk_iso8601(NSDate *date) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [NSISO8601DateFormatter new];
    });
    return [formatter stringFromDate:date];
}

/// Posts one session item. Sessions carry no user or device data beyond the release.
static void sk_sendSession(NSString *sid, NSDate *started, NSString *status, BOOL init) {
    if (!sid || !started) return;

    NSMutableDictionary *session = [@{
        @"sid" : sid,
        @"started" : sk_iso8601(started),
        @"timestamp" : sk_iso8601(NSDate.date),
        @"status" : status,
        @"attrs" : @{@"release" : [NSString stringWithFormat:@"skapsule-ios@%s", CONFIG_VERSION],
                     @"environment" : @CONFIG_TYPE},
    } mutableCopy];
    if (init) {
        session[@"init"] = @YES;
        session[@"seq"] = @0;
    } else {
        session[@"duration"] = @(-started.timeIntervalSinceNow);
    }

    NSData *payload = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
    if (!payload) return;

    NSMutableData *envelope = [NSMutableData data];
    [envelope appendData:[NSJSONSerialization dataWithJSONObject:@{@"dsn" : kDSN}
                                                         options:0
                                                           error:nil]];
    [envelope appendBytes:"\n" length:1];
    sk_appendItem(envelope, @{@"type" : @"session"}, payload);

    NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEnvelopeURL]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15;
    [request setValue:@"application/x-sentry-envelope" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = envelope;
    [[NSURLSession.sharedSession dataTaskWithRequest:request] resume];
}

void SKReportSessionStart(void) {
    if (!sk_consent() || sk_backedOff()) return;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *sid = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-"
                                                                     withString:@""]
                      .lowercaseString;
    NSDate *now = NSDate.date;
    [defaults setObject:sid forKey:kSessionIdKey];
    [defaults setObject:now forKey:kSessionStartKey];
    sk_sendSession(sid, now, @"ok", YES);
}

void SKReportSessionEnd(NSString *status) {
    if (!sk_consent() || sk_backedOff()) return;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *sid = [defaults stringForKey:kSessionIdKey];
    NSDate *started = [defaults objectForKey:kSessionStartKey];
    if (!sid || !started) return;

    // Terminal: never update it again, per the session spec.
    [defaults removeObjectForKey:kSessionIdKey];
    [defaults removeObjectForKey:kSessionStartKey];
    sk_sendSession(sid, started, status, NO);
}

#pragma mark - Public API

void SKReportFailure(NSString *type, NSString *message,
                     NSDictionary<NSString *, NSString *> *extra) {
    if (!sk_consent() || sk_backedOff()) return;

    NSMutableDictionary *event = sk_event(@"error");
    event[@"message"] = @{@"formatted" : sk_scrub(message ?: @"")};
    // One issue per failure type, whatever the message details say.
    event[@"fingerprint"] = @[ type ];
    NSMutableDictionary *tags = [event[@"tags"] mutableCopy];
    tags[@"failure"] = type;
    event[@"tags"] = tags;
    if (extra.count > 0) event[@"extra"] = extra;

    sk_send(event, @[], nil);
}

/// Reads at most `limit` bytes from the end of a file (the crash is at the end).
static NSData *sk_tail(NSString *path, NSUInteger limit) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    @try {
        unsigned long long size = [handle seekToEndOfFile];
        unsigned long long from = size > limit ? size - limit : 0;
        [handle seekToFileOffset:from];
        return [handle readDataToEndOfFile];
    } @catch (NSException *e) {
        return nil;
    } @finally {
        [handle closeFile];
    }
}

static NSDictionary *sk_attachment(NSString *path, NSUInteger limit, BOOL fromEnd) {
    NSData *raw;
    if (fromEnd) {
        raw = sk_tail(path, limit);
    } else {
        NSData *whole = [NSData dataWithContentsOfFile:path];
        raw = whole.length > limit ? [whole subdataWithRange:NSMakeRange(0, limit)] : whole;
    }
    if (raw.length == 0) return nil;
    NSString *text = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    return @{
        @"filename" : path.lastPathComponent,
        @"data" : [sk_scrub(text) dataUsingEncoding:NSUTF8StringEncoding],
    };
}

BOOL SKPreviousRunDiedOnJITTrap(void) {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) return NO;

    NSString *path = [@(homeEnv) stringByAppendingPathComponent:@"latestlog.old.txt"];
    NSData *tail = sk_tail(path, kMaxLogTailBytes);
    if (tail.length == 0) return NO;
    NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding];
    if (text.length == 0) return NO;

    // The JVM prints "Requesting N MB" and then executes brk #0x69, expecting the
    // debugger to map the region and print "mapping at RW=..., RX=...". Seeing the
    // request without the result means the trap went unserviced and the kernel took
    // the process down -- no signal handler runs, so nothing else records it.
    NSRange requested = [text rangeOfString:@"[JIT26] Requesting"
                                    options:NSBackwardsSearch];
    if (requested.location == NSNotFound) return NO;
    NSRange mapped = [text rangeOfString:@"[JIT26] mapping at"
                                 options:NSBackwardsSearch];
    if (mapped.location != NSNotFound && mapped.location > requested.location) return NO;

    // Once per occurrence: keyed on the log's mtime so a relaunch does not re-report
    // the same dead run.
    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:path
                                                                     error:nil][NSFileModificationDate];
    NSString *stamp = [NSString stringWithFormat:@"%.0f", modified.timeIntervalSince1970];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![stamp isEqualToString:[defaults stringForKey:@"jit_trap_reported"]]) {
        [defaults setObject:stamp forKey:@"jit_trap_reported"];
        SKReportFailure(@"jit_trap_unserviced",
                        @"JVM requested its JIT mapping and no debugger serviced the trap",
                        nil);
    }
    return YES;
}

void SKReportScanCrashArtifacts(void) {
    if (!sk_consent() || sk_backedOff()) return;

    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) return;
    NSString *home = @(homeEnv);

    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:home error:nil];
    if (entries.count == 0) return;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray *reported =
      [([defaults arrayForKey:kReportedKey] ?: @[]) mutableCopy];

    for (NSString *name in entries) {
        if (![name hasPrefix:@"hs_err_pid"]) continue;
        NSString *path = [home stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        // Keyed by name *and* size: the JVM names these per-pid, and pids are reused.
        NSString *key = [NSString stringWithFormat:@"%@/%@", name, attrs[NSFileSize] ?: @0];
        if ([reported containsObject:key]) continue;

        NSString *body = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
        if (body.length == 0) continue;

        NSString *type, *value, *group;
        sk_parseHsErr(body, &type, &value, &group);

        NSMutableDictionary *event = sk_event(@"fatal");
        event[@"exception"] = @{
            @"values" : @[ @{
                @"type" : type,
                @"value" : sk_scrub(value),
                @"mechanism" : @{@"type" : @"hs_err", @"handled" : @NO, @"synthetic" : @YES},
            } ]
        };
        event[@"fingerprint"] = @[ @"hs_err", type, group ];
        NSMutableDictionary *tags = [event[@"tags"] mutableCopy];
        tags[@"failure"] = @"jvm_crash";
        tags[@"signal"] = type;
        event[@"tags"] = tags;

        NSMutableArray *attachments = [NSMutableArray array];
        NSDictionary *hsErr = sk_attachment(path, kMaxHsErrBytes, NO);
        if (hsErr) [attachments addObject:hsErr];
        NSDictionary *log = sk_attachment([home stringByAppendingPathComponent:@"latestlog.old.txt"],
                                          kMaxLogTailBytes, YES);
        if (log) [attachments addObject:log];

        // The session that wrote this hs_err is the one that crashed.
        SKReportSessionEnd(@"crashed");

        sk_send(event, attachments, ^(BOOL delivered) {
          if (!delivered) return;  // left unrecorded, so the next launch retries
          dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *current =
              [([defaults arrayForKey:kReportedKey] ?: @[]) mutableCopy];
            [current addObject:key];
            // prune_logs keeps 3 hs_err files, so drop keys whose file is gone
            // and this list cannot grow without bound.
            NSArray<NSString *> *live = [NSFileManager.defaultManager
              contentsOfDirectoryAtPath:home
                                  error:nil];
            [current filterUsingPredicate:
                       [NSPredicate predicateWithBlock:^BOOL(NSString *k, NSDictionary *b) {
                         return [live containsObject:[k componentsSeparatedByString:@"/"].firstObject];
                       }]];
            [defaults setObject:current forKey:kReportedKey];
          });
        });
    }
}
