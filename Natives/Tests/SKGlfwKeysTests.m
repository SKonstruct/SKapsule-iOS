// Host-side tests of the key behind a typed character. Built and run by `make test`.
// The same cases run on Android (GlfwKeysTest.kt).
#import "SKGlfwKeys.h"
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
        CHECK(SKGlfwKeyForChar('a') == 65 && SKGlfwKeyForChar('A') == 65 && SKGlfwKeyForChar('z') == 90, "letters map to their key whatever the case");
        CHECK(!SKGlfwCharNeedsShift('a') && SKGlfwCharNeedsShift('A'), "only a capital holds Shift");
        CHECK(SKGlfwKeyForChar('0') == 48 && SKGlfwKeyForChar('9') == 57, "digits");
        CHECK(SKGlfwKeyForChar('!') == 49 && SKGlfwKeyForChar(')') == 48 && SKGlfwKeyForChar('(') == 57, "shifted digits share the digit's key");
        CHECK(SKGlfwCharNeedsShift('!') && !SKGlfwCharNeedsShift('1'), "and need Shift");
        CHECK(SKGlfwKeyForChar(' ') == 32 && SKGlfwKeyForChar(',') == 44 && SKGlfwKeyForChar('<') == 44, "space and comma");
        CHECK(SKGlfwKeyForChar('.') == 46 && SKGlfwKeyForChar('_') == 45 && SKGlfwKeyForChar('+') == 61 && SKGlfwKeyForChar('~') == 96, "punctuation");
        CHECK(SKGlfwKeyForChar('"') == 39 && SKGlfwCharNeedsShift('"') && !SKGlfwCharNeedsShift('\''), "quotes");
        CHECK(SKGlfwKeyForChar(0xE9) == kSKGlfwKeyUnknown && SKGlfwKeyForChar(0x1F600) == kSKGlfwKeyUnknown, "text with no key has none");
        CHECK(SKGlfwKeyForChar('\n') == kSKGlfwKeyUnknown && SKGlfwKeyForChar(0x1002C) == kSKGlfwKeyUnknown, "control and wide code points have none");
        CHECK(!SKGlfwCharNeedsShift(0xE9), "no Shift for accents");
    }
    printf(failures ? "%d test(s) failed\n" : "all glfw key tests passed\n", failures);
    return failures ? 1 : 0;
}
