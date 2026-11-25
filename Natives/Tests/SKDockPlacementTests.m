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

static CGRect Box(CGFloat cx, CGFloat cy) { return CGRectMake(cx - 80, cy - 80, 160, 160); }

static CGRect Place(CGRect control, const CGRect *others, int othersCount) {
    CGRect reserved[2] = {CGRectMake(W / 2 - 300, 0, 600, 120), CGRectMake(W - 260, 0, 260, 150)};
    CGPoint p = SKDockPlace(CGSizeMake(W, H), CGSizeMake(DW, DH), control, reserved, 2, others, othersCount, 24, 24);
    return CGRectMake(p.x, p.y, DW, DH);
}

int main(void) {
    @autoreleasepool {
        CHECK(CGRectGetMidX(Place(Box(300, 600), NULL, 0)) > W / 2, "a control on the left puts the dialog on the right");
        CHECK(CGRectGetMidX(Place(Box(1700, 600), NULL, 0)) < W / 2, "a control on the right puts the dialog on the left");

        CGRect reserved[2] = {CGRectMake(W / 2 - 300, 0, 600, 120), CGRectMake(W - 260, 0, 260, 150)};
        BOOL covers = NO, clashes = NO, offscreen = NO;
        for (int cx = 100; cx <= 1900; cx += 150) {
            for (int cy = 100; cy <= 850; cy += 150) {
                CGRect c = Box(cx, cy), d = Place(c, NULL, 0);
                if (SKRectsOverlap(d, c)) covers = YES;
                if (SKRectsOverlap(d, reserved[0]) || SKRectsOverlap(d, reserved[1])) clashes = YES;
                if (d.origin.x < 0 || d.origin.y < 0 || CGRectGetMaxX(d) > W || CGRectGetMaxY(d) > H) offscreen = YES;
            }
        }
        CHECK(!covers, "the dialog never covers the control, anywhere on the grid");
        CHECK(!clashes, "the dialog keeps clear of the tab strip and Done, anywhere on the grid");
        CHECK(!offscreen, "the dialog stays on screen");

        CGRect busy[2] = {CGRectMake(1500, 500, 480, 380), CGRectMake(1500, 100, 480, 380)};
        CGRect selected = Box(300, 600), d = Place(selected, busy, 2);
        CHECK(!SKRectsOverlap(d, busy[0]) && !SKRectsOverlap(d, busy[1]), "it prefers a spot that covers no other control");
        CHECK(!SKRectsOverlap(d, selected), "and still not the selected one");

        CGRect huge = CGRectMake(0, 0, W, H);
        CHECK(Place(huge, NULL, 0).size.width == DW, "a control as big as the screen still gets a spot");
    }
    printf(failures ? "%d test(s) failed\n" : "all dock placement tests passed\n", failures);
    return failures ? 1 : 0;
}
