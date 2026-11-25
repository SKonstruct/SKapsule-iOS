// Host-side tests of the modpack status (Download / Update / up to date). Built and run by `make test`.
// The same cases run on Android (ModsDownloaderTest.kt).
#import "SKModPack.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

/// `here` is what is in the mods folder; `stale` the names that no longer match the listing.
static SKModPackStatus *Status(NSArray<NSString *> *remote, NSArray<NSString *> *synced, NSArray<NSString *> *here,
                               NSArray<NSString *> *stale) {
    NSSet *hereSet = [NSSet setWithArray:here], *staleSet = [NSSet setWithArray:stale];
    return [SKModPackStatus statusForRemoteNames:remote
                                          synced:[NSSet setWithArray:synced]
                                          exists:^BOOL(NSString *n) { return [hereSet containsObject:n]; }
                                       isCurrent:^BOOL(NSString *n) { return [hereSet containsObject:n] && ![staleSet containsObject:n]; }];
}

int main(void) {
    @autoreleasepool {
        SKModPackStatus *s = Status(@[ @"a.zip", @"b.zip" ], @[], @[], @[]);
        CHECK(s.state == SKModPackStateNotInstalled && s.toDownload == 2, "nothing downloaded yet is not installed");

        s = Status(@[ @"a.zip", @"b.zip" ], @[ @"a.zip" ], @[ @"a.zip" ], @[]);
        CHECK(s.state == SKModPackStateUpdate, "a mod added to the pack since the last sync is an update");
        s = Status(@[ @"a.zip" ], @[ @"a.zip" ], @[ @"a.zip" ], @[ @"a.zip" ]);
        CHECK(s.state == SKModPackStateUpdate && s.toDownload == 1, "a changed mod is an update");

        s = Status(@[ @"a.zip" ], @[ @"a.zip", @"old.zip" ], @[ @"a.zip", @"old.zip" ], @[]);
        CHECK(s.state == SKModPackStateUpdate && s.toDelete == 1, "a mod the pack dropped is an update when a sync wrote it");
        s = Status(@[ @"a.zip" ], @[ @"a.zip" ], @[ @"a.zip", @"mine.zip" ], @[]);
        CHECK(s.state == SKModPackStateCurrent, "the player's own mod is no reason to update");

        s = Status(@[ @"a.zip", @"b.zip" ], @[ @"a.zip", @"b.zip" ], @[ @"a.zip", @"b.zip" ], @[]);
        CHECK(s.state == SKModPackStateCurrent && s.toDownload + s.toDelete == 0, "matching files are current");

        s = Status(@[ @"a.zip", @"b.zip" ], @[], @[ @"a.zip" ], @[]);
        CHECK(s.state == SKModPackStateUpdate, "one shared file counts as installed, so the rest is an update");

        CHECK([SKModPackStatus currentStatus].state == SKModPackStateCurrent, "the status after a sync");
    }
    printf(failures ? "%d test(s) failed\n" : "all mod pack tests passed\n", failures);
    return failures ? 1 : 0;
}
