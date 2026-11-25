// Host-side tests of when mods are applied automatically. Built and run by `make test`.
// The same cases run on Android (ModsSyncTest.kt).
#import "SKModSync.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

int main(void) {
    @autoreleasepool {
        CHECK(SKModSyncDecide(NO, @"a", @"j", nil, nil) == SKModSyncNone, "no game installed: nothing to do");
        CHECK(SKModSyncDecide(YES, @"a", @"j", nil, nil) == SKModSyncApply, "mods and nothing ever applied: apply");
        CHECK(SKModSyncDecide(YES, @"", @"j", nil, nil) == SKModSyncNone, "no mods and nothing ever applied: nothing");
        CHECK(SKModSyncDecide(YES, @"a", @"j", @"a", @"j") == SKModSyncNone, "nothing changed: nothing");
        CHECK(SKModSyncDecide(YES, @"a|b", @"j", @"a", @"j") == SKModSyncApply, "a mod was added: apply");
        CHECK(SKModSyncDecide(YES, @"a", @"j2", @"a", @"j") == SKModSyncApply, "the game put its jars back: apply again");
        CHECK(SKModSyncDecide(YES, @"", @"j", @"a", @"j") == SKModSyncRestore, "every mod was removed: restore once");
        CHECK(SKModSyncDecide(YES, @"", @"j2", @"", @"j") == SKModSyncNone, "restored already: nothing, whatever the jars do");
        CHECK(SKModSyncDecide(YES, @"a", @"j", @"a", @"j") == SKModSyncNone, "after a reset the same mods stay unapplied");
    }
    printf(failures ? "%d test(s) failed\n" : "all mod sync tests passed\n", failures);
    return failures ? 1 : 0;
}
