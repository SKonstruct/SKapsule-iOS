// Host-side tests of the mouse button diffing used for trackpads and mice. Built and run by `make test`.
#import "SKMouseButtons.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

static void expect(unsigned previous, unsigned now, unsigned pressed, unsigned released, const char *msg) {
    unsigned p, r;
    SKMouseButtonChanges(previous, now, &p, &r);
    CHECK(p == pressed && r == released, msg);
}

int main(void) {
    expect(0, 1, 1, 0, "first button down presses it");
    expect(1, 0, 0, 1, "last button up releases it");
    // The reported case: left released while right is pressed, with no pointer up in between.
    expect(1, 2, 2, 1, "left up and right down in one step");
    expect(1, 3, 2, 0, "a second button pressed while the first is held");
    expect(3, 0, 0, 3, "both released together");
    expect(2, 2, 0, 0, "no change, no events");
    printf(failures ? "%d test(s) failed\n" : "all mouse button tests passed\n", failures);
    return failures ? 1 : 0;
}
