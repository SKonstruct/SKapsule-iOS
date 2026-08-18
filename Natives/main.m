#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <spawn.h>
#import <sys/sysctl.h>

#import "AppDelegate.h"
#import "JavaLauncher.h"
#import "config.h"
#import "utils.h"

#include <dirent.h>
#include <libgen.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PT_TRACE_ME 0
#define PT_DETACH 11
int ptrace(int, pid_t, caddr_t, int);

#define fm NSFileManager.defaultManager
extern char **environ;

static bool init_checkForJailbreak(void) {
    if (NSProcessInfo.processInfo.macCatalystApp) {
        return false;
    }
    // Check if posix_spawn is hooked (common jailbreak indicator)
    for (int i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), "/systemhook.dylib") != NULL) {
            return true;
        }
    }
    return opendir("/Applications") != NULL;
}

static void init_setupHomeDirectory(void) {
    setenv("HOME",
           [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
               .lastObject.path.stringByDeletingLastPathComponent.UTF8String,
           1);

    BOOL isNotSandboxed = [@(getenv("HOME")).lastPathComponent isEqualToString:NSUserName()];
    NSString *homeDir =
        [NSString stringWithFormat:@"%s/Documents%@", getenv("HOME"), isNotSandboxed ? @"/SKapsule" : @""];

    NSError *error;
    if (![fm fileExistsAtPath:homeDir]) {
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&error];
    }

    if (error) {
        error = nil;
        homeDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&error];
    }

    setenv("SKAPSULE_HOME", realpath(homeDir.UTF8String, NULL), 1);
}

// Keep only the `keep` newest files whose name starts with `prefix`. The JVM names
// its crash reports and -Xlog output per-pid (hs_err_pid<N>.log, vmlog-<N>.log), so
// nothing ever overwrites them and Share Logs would otherwise keep exporting runs
// from weeks ago. Pruning at launch rather than at exit is deliberate: the previous
// run's crash report has to survive the relaunch, since that is when it gets shared.
static void prune_logs(NSString *home, NSString *prefix, NSUInteger keep) {
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:home error:nil]) {
        if ([name hasPrefix:prefix]) {
            [matches addObject:name];
        }
    }
    if (matches.count <= keep) {
        return;
    }
    // Newest first, so everything from index `keep` on is surplus.
    [matches sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *da = [fm attributesOfItemAtPath:[home stringByAppendingPathComponent:a]
                                          error:nil].fileModificationDate;
        NSDate *db = [fm attributesOfItemAtPath:[home stringByAppendingPathComponent:b]
                                          error:nil].fileModificationDate;
        if (!da || !db) {
            return NSOrderedSame;
        }
        return [db compare:da];
    }];
    for (NSUInteger i = keep; i < matches.count; i++) {
        [fm removeItemAtPath:[home stringByAppendingPathComponent:matches[i]] error:nil];
    }
}

static void __attribute__((unused)) init_redirectStdio(void) {
    NSString *home = @(getenv("SKAPSULE_HOME"));
    NSString *currName = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSString *oldName = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];

    // Same two-generation retention latestlog gets, applied to the per-pid JVM logs.
    prune_logs(home, @"hs_err_pid", 3);
    prune_logs(home, @"vmlog-", 3);

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];
    if (!file) {
        NSLog(@"[Pre-init] Failed to open %@", currName);
        return;
    }

    setvbuf(stdout, 0, _IOLBF, 0);
    setvbuf(stderr, 0, _IONBF, 0);

    // Tee: keep a copy of the original stdout so console output (Xcode /
    // Console.app) still works, while also writing everything to latestlog.txt so
    // the launcher's "Share Logs" / "Save Logs" can capture non-Xcode (StikJIT)
    // launches.
    static int origOut;
    origOut = dup(fileno(stdout));

    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      ssize_t rsize;
      char buf[2048];
      while ((rsize = read(pfd[0], buf, sizeof(buf) - 1)) > 0) {
          if (rsize < 2048)
              buf[rsize] = '\0';
          if (origOut >= 0) {
              write(origOut, buf, rsize);
          }
          [file writeData:[NSData dataWithBytes:buf length:rsize]];
          [file synchronizeFile];
      }
      [file closeFile];
    });
}

static void init_logDeviceAndVer(void) {
    NSLog(@"[Pre-Init] SKapsule iOS INIT!");
    NSLog(@"[Pre-Init] Version: %@-%s", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], CONFIG_TYPE);
    NSLog(@"[Pre-Init] Commit: %s (%s)", CONFIG_COMMIT, CONFIG_BRANCH);

    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    const char *type;
    if (!access(tsPath.UTF8String, F_OK)) {
        type = "TrollStore";
    } else if (isJailbroken) {
        type = "Jailbroken";
    } else {
        type = "Sideloaded";
    }
    NSLog(@"[Pre-Init] Install type: %s", type);
}

static void init_setupGameDirs(void) {
    const char *home = getenv("SKAPSULE_HOME");
    NSArray *dirsToCreate = @[
        [NSString stringWithFormat:@"%s/sk", home],
        [NSString stringWithFormat:@"%s/sk/rsrc", home],
        [NSString stringWithFormat:@"%s/sk/crucible", home],
        [NSString stringWithFormat:@"%s/sk/tmp", home],
        [NSString stringWithFormat:@"%s/home", home],
        [NSString stringWithFormat:@"%s/home/.userPrefs", home],
        [NSString stringWithFormat:@"%s/home/.systemPrefs", home],
    ];
    for (NSString *dir in dirsToCreate) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

int main(int argc, char *argv[]) {
    // libjli's macOS/iOS launcher re-invokes main() (via apple_main) on the
    // thread that must run the VM's main class. Once launchJVM has resolved
    // JLI_Launch, forward that re-entry straight back into it so the main class
    // actually runs on this thread — the launcher's JAVA_STARTED_ON_FIRST_THREAD
    // guard prevents further recursion. Parking here instead deadlocks the
    // launch. Mirrors Amethyst-iOS.
    if (pJLI_Launch) {
        NSLog(@"[Pre-init] libjli main() re-entry — forwarding into JLI_Launch");
        return pJLI_Launch(argc, (const char **)argv, 0, NULL, 0, NULL, "25-internal", "25", "java", "openjdk", 0, 1, 0,
                           1);
    }

    if (argc == 2 && strlen(argv[1]) == 0) {
        // Child process for JIT enablement via PT_TRACE_ME
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    isJailbroken = init_checkForJailbreak();
    init_setupHomeDirectory();
    init_redirectStdio();  // tees console output to latestlog.txt for Share/Save Logs
    init_logDeviceAndVer();
    init_setupGameDirs();
    skStageJITScriptToDocuments();  // make the JIT script importable in StikJIT

    // If sandbox is disabled (TrollStore), enable JIT via PT_TRACE_ME
    if (!isJITEnabled(YES) && getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        NSLog(@"[Pre-init] no-sandbox: trying to enable JIT");
        int pid;
        int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
        if (ret == 0) {
            waitpid(pid, NULL, WUNTRACED);
            ptrace(PT_DETACH, pid, NULL, 0);
            kill(pid, SIGTERM);
            wait(NULL);
            if (isJITEnabled(YES)) {
                NSLog(@"[Pre-init] JIT enabled with PT_TRACE_ME");
            }
        }
    }

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
