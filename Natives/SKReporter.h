#ifndef SKREPORTER_H
#define SKREPORTER_H

#import <Foundation/Foundation.h>

/// Uploads any hs_err_pid*.log in SKAPSULE_HOME not already reported, with the
/// previous run's log tail attached. No-op when reporting is switched off.
void SKReportScanCrashArtifacts(void);

/// YES when the previous run died on the JIT trap: the JVM asked a debugger for its
/// executable mapping and nothing answered, which kills the process instantly and
/// leaves no crash report. Reports the event as a side effect (once per occurrence).
BOOL SKPreviousRunDiedOnJITTrap(void);

/// A failure the app detected itself. `type` is the grouping key (one Sentry
/// issue per type). No-op when reporting is switched off.
void SKReportFailure(NSString *type, NSString *message,
                     NSDictionary<NSString *, NSString *> *extra);

/// Starts a release-health session. Call once per launch.
void SKReportSessionStart(void);

/// Ends the current session: "exited" on a clean background, "crashed" when the next
/// launch finds an hs_err from it. No-op if none is open.
void SKReportSessionEnd(NSString *status);

/// NSUserDefaults key behind the sidebar switch. Defaults to YES.
extern NSString *const SKReportingEnabledKey;

#endif /* SKREPORTER_H */
