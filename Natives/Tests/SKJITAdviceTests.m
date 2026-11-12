// Host-side tests of the built-in JIT failure advice. Built and run by `make test`.
#import "SKJITAdvice.h"
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
        CHECK(SKJITProblemFromMessage(@"Connection reset by peer") == SKJITProblemPairing, "reset is a pairing problem");
        CHECK(SKJITProblemFromMessage(@"IdeviceError.connectionReset") == SKJITProblemPairing, "enum-style reset");
        CHECK(SKJITProblemFromMessage(@"read: early eof") == SKJITProblemOtherVPN, "early eof is another VPN");
        CHECK(SKJITProblemFromMessage(@"Operation timed out") == SKJITProblemUnreachable, "timeout is unreachable");
        CHECK(SKJITProblemFromMessage(@"No route to host") == SKJITProblemUnreachable, "no route is unreachable");
        CHECK(SKJITProblemFromMessage(@"The Developer Disk Image failed to mount") == SKJITProblemNone,
              "unrelated errors have no advice");

        NSString *cellular = SKJITAdviceForProblem(SKJITProblemUnreachable, YES);
        NSString *plain = SKJITAdviceForProblem(SKJITProblemUnreachable, NO);
        CHECK([cellular containsString:@"cellular"] && ![plain containsString:@"cellular"], "cellular advice differs");

        NSString *unchanged = SKJITMessageWithAdvice(@"Something else", NO);
        CHECK([unchanged isEqualToString:@"Something else"], "unknown messages pass through");
        CHECK([SKJITMessageWithAdvice(@"Connection refused", NO) hasPrefix:@"Connection refused\n\n"],
              "advice is appended after the original message");
    }
    printf(failures ? "%d test(s) failed\n" : "all JIT advice tests passed\n", failures);
    return failures ? 1 : 0;
}
