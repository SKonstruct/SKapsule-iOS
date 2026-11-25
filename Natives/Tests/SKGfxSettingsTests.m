// Host-side tests of the graphics settings' decisions. Built and run by `make test`.
#import "SKGfxSettings.h"
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
        CHECK(!SKGfxUsesOffscreen(0.6f, 0, NO), "nothing asked for: the old path");
        CHECK(SKGfxUsesOffscreen(0.6f, 40, NO), "sharpening needs the offscreen path");
        CHECK(SKGfxUsesOffscreen(1.0f, 10, NO), "sharpening at full resolution too");
        CHECK(SKGfxUsesOffscreen(0.6f, 0, YES), "Sharp HUD below full resolution");
        CHECK(!SKGfxUsesOffscreen(1.0f, 0, YES), "Sharp HUD does nothing at full resolution");
        CHECK(!SKGfxSharpHudApplies(1.0f) && SKGfxSharpHudApplies(0.6f), "Sharp HUD needs a smaller scene");

        int w = 0, h = 0;
        SKGfxGameSize(2556, 1179, 0.6f, NO, &w, &h);
        CHECK(w == 1534 && h == 707, "the game is told the scene size");
        SKGfxGameSize(2556, 1179, 0.6f, YES, &w, &h);
        CHECK(w == 2556 && h == 1179, "Sharp HUD lays the game out at the full size");
        SKGfxGameSize(2556, 1179, 1.0f, NO, &w, &h);
        CHECK(w == 2556 && h == 1179, "full resolution is full size");

        CHECK(SKGfxScaled(1, 0.25f) == 1, "never zero");
        CHECK(SKGfxScaled(5, 0.5f) == 3, "half rounds up");
        CHECK(SKGfxScaled(963, 0.6f) == 578, "matches the Android rounding");
    }
    printf(failures ? "%d test(s) failed\n" : "all graphics settings tests passed\n", failures);
    return failures ? 1 : 0;
}
