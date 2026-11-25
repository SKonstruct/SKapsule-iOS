// Host-side tests of the touch-layout export/import format. Built and run by `make test`.
// The same files are parsed by the Android tests (TouchLayoutShareTest.kt): an export from
// either app must import on the other, so keep Tests/fixtures identical in both repos.
#import "SKLayoutShare.h"
#import <stdio.h>

// The editor's own limits live in SKTouchControls.m (UIKit); mirrored here for the host build.
const CGFloat SKMinOpacity = 0.2f;
const CGFloat SKMinNodeScale = 0.5f;
const CGFloat SKMaxNodeScale = 2.5f;

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

static NSSet<NSString *> *KnownIds(void) {
    return [NSSet setWithArray:@[
        @"joy_move", @"joy_face", @"btn_esc", @"btn_strafe", @"btn_defend", @"btn_dodge", @"btn_shieldbash",
        @"btn_prevweap", @"btn_nextweap", @"btn_ab1", @"btn_ab2", @"btn_ab3", @"btn_item1", @"btn_item2",
        @"btn_item3", @"btn_item4",
    ]];
}

static NSData *Json(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }

static NSMutableDictionary *ValidFile(void) {
    return [@{
        @"format" : @"skapsule-controls",
        @"version" : @1,
        @"name" : @"Test",
        @"globalOpacity" : @0.5,
        @"actionBarVisible" : @YES,
        @"nodes" : @[ @{@"id" : @"btn_esc", @"xPercent" : @0.1, @"yPercent" : @0.2, @"scale" : @1.5, @"visible" : @YES} ],
    } mutableCopy];
}

static SKSharedLayout *Parse(NSData *data, NSInteger *code) {
    NSError *error = nil;
    SKSharedLayout *layout = [SKSharedLayout parseData:data knownIds:KnownIds() error:&error];
    if (code) *code = layout ? 0 : error.code;
    return layout;
}

static NSData *Fixture(NSString *name) {
    NSString *dir = [[@__FILE__ stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fixtures"];
    return [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // --- both apps' real exports parse ---
        for (NSString *file in @[ @"controls-android-export.json", @"controls-ios-export.json" ]) {
            NSData *data = Fixture(file);
            CHECK(data != nil, "fixture present");
            SKSharedLayout *l = Parse(data, NULL);
            CHECK(l != nil, [[file stringByAppendingString:@" parses"] UTF8String]);
            CHECK(l.nodes.count == 16, "all 16 known nodes");
            CHECK([l nodeForId:@"btn_future"] == nil, "an id this build lacks is ignored");
            SKSharedNode *esc = [l nodeForId:@"btn_esc"];
            CHECK(esc && fabs(esc.xPercent - 0.12) < 1e-6 && fabs(esc.scale - 1.5) < 1e-6, "values survive (floats widened to doubles)");
            CHECK([l nodeForId:@"btn_strafe"].visible == NO, "visibility survives");
            CHECK(fabs(l.globalOpacity - 0.55) < 1e-6 && l.actionBarVisible, "opacity and Show Buttons survive");
        }

        // --- round trip through our own writer ---
        SKSharedLayout *l = Parse(Fixture(@"controls-android-export.json"), NULL);
        SKSharedLayout *again = Parse([l jsonData], NULL);
        CHECK(again && again.nodes.count == l.nodes.count && [again.name isEqualToString:l.name], "export then import is lossless");
        NSDictionary *written = [NSJSONSerialization JSONObjectWithData:[l jsonData] options:0 error:nil];
        CHECK([written[@"version"] isEqual:@1] && !CFNumberIsFloatType((__bridge CFNumberRef)written[@"version"]),
              "version is written as the integer 1, which Android reads with `as? Int`");

        // --- refusals: the whole file or nothing ---
        NSInteger code = 0;
        NSMutableDictionary *f = ValidFile();
        f[@"format"] = @"something-else";
        CHECK(Parse(Json(f), &code) == nil && code == SKLayoutShareErrorInvalid, "wrong format");
        f = ValidFile();
        f[@"version"] = @2;
        CHECK(Parse(Json(f), &code) == nil && code == SKLayoutShareErrorNewer, "newer version");
        f = ValidFile();
        f[@"version"] = @1.5;
        CHECK(Parse(Json(f), &code) == nil, "version must be an integer, as on Android");
        f = ValidFile();
        f[@"version"] = @0;
        CHECK(Parse(Json(f), &code) == nil && code == SKLayoutShareErrorInvalid, "old version");
        f = ValidFile();
        f[@"nodes"] = @[];
        CHECK(Parse(Json(f), &code) == nil, "no nodes");
        f = ValidFile();
        f[@"nodes"] = @[ @{@"id" : @"btn_future", @"xPercent" : @0.1, @"yPercent" : @0.1, @"scale" : @1, @"visible" : @YES} ];
        CHECK(Parse(Json(f), &code) == nil, "only unknown nodes: nothing usable");
        f = ValidFile();
        NSDictionary *node = f[@"nodes"][0];
        f[@"nodes"] = @[ node, node ];
        CHECK(Parse(Json(f), &code) == nil, "a repeated known id");
        f = ValidFile();
        f[@"nodes"] = @[ @{@"id" : @"btn_esc", @"xPercent" : @"0.1", @"yPercent" : @0.2, @"scale" : @1, @"visible" : @YES} ];
        CHECK(Parse(Json(f), &code) == nil, "a number given as a string");
        f = ValidFile();
        f[@"nodes"] = @[ @{@"id" : @"btn_esc", @"xPercent" : @YES, @"yPercent" : @0.2, @"scale" : @1, @"visible" : @YES} ];
        CHECK(Parse(Json(f), &code) == nil, "a number given as a boolean");
        f = ValidFile();
        f[@"nodes"] = @[ @{@"id" : @"btn_future", @"xPercent" : @"bad", @"yPercent" : @0.2, @"scale" : @1, @"visible" : @YES},
                         @{@"id" : @"btn_esc", @"xPercent" : @0.1, @"yPercent" : @0.2, @"scale" : @1, @"visible" : @YES} ];
        CHECK(Parse(Json(f), &code) == nil, "a malformed node is refused even when its id is unknown");
        f = ValidFile();
        [f removeObjectForKey:@"actionBarVisible"];
        CHECK(Parse(Json(f), &code) == nil, "missing actionBarVisible");
        CHECK(Parse([@"not json" dataUsingEncoding:NSUTF8StringEncoding], &code) == nil, "not JSON");
        CHECK(Parse([NSData data], &code) == nil, "empty");
        NSMutableData *big = [NSMutableData dataWithLength:SKLayoutShareMaxBytes + 1];
        CHECK(Parse(big, &code) == nil && code == SKLayoutShareErrorTooLarge, "too large");
        NSMutableArray *many = [NSMutableArray array];
        for (int i = 0; i < 65; i++) [many addObject:@{@"id" : @"btn_esc", @"xPercent" : @0, @"yPercent" : @0, @"scale" : @1, @"visible" : @YES}];
        f = ValidFile();
        f[@"nodes"] = many;
        CHECK(Parse(Json(f), &code) == nil, "more than 64 nodes");

        // --- clamping and names ---
        f = ValidFile();
        f[@"globalOpacity"] = @0.0;
        f[@"nodes"] = @[ @{@"id" : @"btn_esc", @"xPercent" : @-3, @"yPercent" : @9, @"scale" : @100, @"visible" : @NO} ];
        SKSharedLayout *c = Parse(Json(f), NULL);
        SKSharedNode *n = [c nodeForId:@"btn_esc"];
        CHECK(n.xPercent == 0 && n.yPercent == 1 && n.scale == SKMaxNodeScale, "positions and scale are clamped");
        CHECK(c.globalOpacity == SKMinOpacity, "opacity never goes invisible");
        CHECK([[SKSharedLayout cleanName:@"  a\nb\t "] isEqualToString:@"ab"], "control characters dropped, trimmed");
        CHECK([[SKSharedLayout cleanName:@"   "] isEqualToString:@"Imported"], "empty becomes Imported");
        CHECK([SKSharedLayout cleanName:[@"" stringByPaddingToLength:80 withString:@"x" startingAtIndex:0]].length == 40, "names are cut at 40");

        // --- presets ---
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"sk.layout-share-tests"];
        [defaults removePersistentDomainForName:@"sk.layout-share-tests"];
        SKLayoutPresets *presets = [[SKLayoutPresets alloc] initWithDefaults:defaults knownIds:KnownIds()];
        CHECK(presets.all.count == 0, "starts empty");
        SKSharedLayout *base = Parse(Fixture(@"controls-ios-export.json"), NULL);
        base.name = @"Mine";
        CHECK([[presets addLayout:base] isEqualToString:@"Mine"], "saved under its name");
        CHECK([[presets addLayout:base] isEqualToString:@"Mine (2)"], "a taken name gets a suffix, never overwrites");
        base.name = @"default";
        CHECK([[presets addLayout:base] isEqualToString:@"default (2)"], "the built-in's name is reserved");
        CHECK(presets.all.count == 3 && [presets presetNamed:@"Mine"] != nil, "listed and found");
        presets.active = @"Mine";
        [presets deleteNamed:@"Mine"];
        CHECK(presets.all.count == 2 && presets.active == nil, "deleting the active preset clears the marker");
        [defaults setObject:@"[{\"format\":\"nope\"}, 5, null]" forKey:@"touch_layout_presets"];
        CHECK(presets.all.count == 0, "corrupt stored entries are skipped, not applied");
        [defaults setObject:@"[]" forKey:@"touch_layout_presets"];
        for (int i = 0; i < (int)SKLayoutShareMaxPresets; i++) {
            base.name = [NSString stringWithFormat:@"p%d", i];
            [presets addLayout:base];
        }
        base.name = @"one too many";
        CHECK([presets addLayout:base] == nil, "the list is capped");
        [defaults removePersistentDomainForName:@"sk.layout-share-tests"];

        // --dump <path> writes a real iOS export, used to refresh Tests/fixtures/controls-ios-export.json.
        if (argc == 3 && strcmp(argv[1], "--dump") == 0) {
            SKSharedLayout *dump = Parse(Fixture(@"controls-android-export.json"), NULL);
            dump.name = @"From iOS";
            [[dump jsonData] writeToFile:@(argv[2]) atomically:YES];
        }
    }
    printf(failures ? "%d test(s) failed\n" : "all layout share tests passed\n", failures);
    return failures ? 1 : 0;
}
