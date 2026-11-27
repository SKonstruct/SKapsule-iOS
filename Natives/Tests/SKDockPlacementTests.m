// Host-side tests of where the selected control's dialog goes in the touch editor. Built and run by `make test`.
// The same cases run on Android (DialogDockTest.kt).
#import "SKDockPlacement.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

static const CGFloat W = 2000, H = 900, DW = 480, DH = 360;

static CGRect Place(const CGRect *reserved, int count, CGFloat dialogHeight) {
    CGPoint p = SKDockPlace(CGSizeMake(W, H), CGSizeMake(DW, dialogHeight), reserved, count, 24, 24);
    return CGRectMake(p.x, p.y, DW, dialogHeight);
}

int main(void) {
    @autoreleasepool {
        CGRect tabStrip = CGRectMake(W / 2 - 300, 0, 600, 120), done = CGRectMake(W - 260, 0, 260, 150);

        CGRect d = Place(NULL, 0, DH);
        CHECK(d.origin.x == W - DW - 24 && d.origin.y == 24, "with nothing reserved it sits in the top right corner");

        CGRect both[2] = {tabStrip, done};
        d = Place(both, 2, DH);
        CHECK(d.origin.x == W - DW - 24, "it stays at the right edge");
        CHECK(!CGRectIntersectsRect(d, done), "it never covers the Done button");
        CHECK(d.origin.y == CGRectGetMaxY(done) + 24, "it sits just below the Done button");

        CGRect onlyTabs[1] = {tabStrip};
        CHECK(Place(onlyTabs, 1, DH).origin.y == 24, "the tab strip in the middle does not move it");

        CGRect doneOnly[1] = {done};
        d = Place(doneOnly, 1, 800);
        CHECK(d.origin.x >= 0 && d.origin.y >= 0 && CGRectGetMaxX(d) <= W && CGRectGetMaxY(d) <= H,
              "it never leaves the screen");
    }
    printf(failures ? "%d test(s) failed\n" : "all dock placement tests passed\n", failures);
    return failures ? 1 : 0;
}
