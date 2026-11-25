// Host-side tests of the automatic mod order. Built and run by `make test`.
// The same cases run on Android (ModsOrderTest.kt); the rule is SKradle's: the mods that change
// the most files go first, equal ones by name, so a small mod applied later beats a broad one.
#import "SKModOrder.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

static NSInteger Written(NSArray<NSString *> *names) {
    NSSet *protectedFiles = [NSSet setWithArray:@[ @"config/item.dat", @"config/wall.dat" ]];
    return [SKModOrder filesWrittenInEntryNames:names protectedFiles:protectedFiles];
}

static NSArray<NSString *> *Order(NSDictionary<NSString *, NSNumber *> *counts, NSArray<NSString *> *input) {
    return [SKModOrder optimalOrderOfNames:input filesChanged:^NSInteger(NSString *name) { return counts[name].integerValue; }];
}

int main(void) {
    @autoreleasepool {
        // --- what counts as a file a mod writes ---
        CHECK(Written(@[ @"a.txt", @"dir/b.txt", @"dir/sub/c.txt" ]) == 3, "plain files");
        CHECK(Written(@[ @"dir/", @"dir/sub/", @"dir/f.txt" ]) == 1, "directories do not count");
        CHECK(Written(@[ @"mod.json", @"mod.png", @"pack/mod.json", @"pack/mod.png", @"x.txt" ]) == 1, "metadata at any depth");
        CHECK(Written(@[ @"config/item.dat", @"Config/WALL.DAT", @"config/other.dat" ]) == 1, "protected files, any case");
        CHECK(Written(@[ @"../evil.txt", @"/abs.txt", @"a/../../b.txt", @"ok.txt" ]) == 1, "paths that leave the root");
        CHECK(Written(@[ @"a/../b.txt" ]) == 1, "a .. that stays inside is fine");
        CHECK(Written(@[]) == 0, "nothing");

        // --- the order ---
        NSDictionary *counts = @{@"small.zip" : @2, @"Broad.zip" : @50, @"mid.zip" : @10, @"Alpha.zip" : @10, @"beta.zip" : @10};
        NSArray *expected = @[ @"Broad.zip", @"Alpha.zip", @"beta.zip", @"mid.zip", @"small.zip" ];
        CHECK([Order(counts, counts.allKeys) isEqualToArray:expected], "most files first, then by name ignoring case");

        NSDictionary *tied = @{@"a.zip" : @3, @"B.zip" : @3, @"b.zip" : @3, @"c.zip" : @9, @"d.modpack" : @0};
        NSArray *reference = Order(tied, @[ @"a.zip", @"B.zip", @"b.zip", @"c.zip", @"d.modpack" ]);
        NSArray *reversed = Order(tied, @[ @"d.modpack", @"c.zip", @"b.zip", @"B.zip", @"a.zip" ]);
        NSArray *scrambled = Order(tied, @[ @"b.zip", @"d.modpack", @"a.zip", @"c.zip", @"B.zip" ]);
        CHECK([reference isEqualToArray:reversed] && [reference isEqualToArray:scrambled], "the input order does not matter");
        NSUInteger upper = [reference indexOfObject:@"B.zip"], lower = [reference indexOfObject:@"b.zip"];
        CHECK(upper < lower, "names that differ only in case keep one fixed order (exact name decides)");
        CHECK([reference.firstObject isEqual:@"c.zip"] && [reference.lastObject isEqual:@"d.modpack"], "broadest first, empty last");

        NSArray *two = Order(@{@"tweak.zip" : @1, @"overhaul.zip" : @400}, @[ @"tweak.zip", @"overhaul.zip" ]);
        CHECK([two.firstObject isEqual:@"overhaul.zip"] && [two.lastObject isEqual:@"tweak.zip"],
              "a targeted mod comes after a broad one, so it wins");
    }
    printf(failures ? "%d test(s) failed\n" : "all mod order tests passed\n", failures);
    return failures ? 1 : 0;
}
