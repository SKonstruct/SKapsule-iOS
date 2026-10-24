// Host-side tests for the zip code that parses third-party mod archives. Built and run
// by `make test` on the Mac; no simulator or XCTest needed.
#import "SKZipUtils.h"
#import <zlib.h>

static int failures = 0;
#define CHECK(cond, msg)                                                      \
    do {                                                                      \
        if (!(cond)) {                                                        \
            printf("FAIL: %s (line %d)\n", msg, __LINE__);                    \
            failures++;                                                       \
        }                                                                     \
    } while (0)

static void put16(NSMutableData *d, uint16_t v) { [d appendBytes:&v length:2]; }
static void put32(NSMutableData *d, uint32_t v) { [d appendBytes:&v length:4]; }

/// A one-entry archive using the stored method, with the central directory's sizes forced
/// to `declared` so a forged header can be tested.
static NSData *StoredZip(NSString *name, NSData *content, uint32_t declared) {
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = (uint32_t)crc32(crc32(0, Z_NULL, 0), content.bytes, (uInt)content.length);
    NSMutableData *z = [NSMutableData data];
    put32(z, 0x04034b50); put16(z, 20); put16(z, 0); put16(z, 0); put16(z, 0); put16(z, 0);
    put32(z, crc); put32(z, (uint32_t)content.length); put32(z, (uint32_t)content.length);
    put16(z, (uint16_t)nameData.length); put16(z, 0);
    [z appendData:nameData];
    [z appendData:content];
    uint32_t cdOffset = (uint32_t)z.length;
    put32(z, 0x02014b50); put16(z, 20); put16(z, 20); put16(z, 0); put16(z, 0); put16(z, 0); put16(z, 0);
    put32(z, crc); put32(z, declared); put32(z, declared);
    put16(z, (uint16_t)nameData.length); put16(z, 0); put16(z, 0); put16(z, 0); put16(z, 0);
    put32(z, 0); put32(z, 0);
    [z appendData:nameData];
    uint32_t cdSize = (uint32_t)z.length - cdOffset;
    put32(z, 0x06054b50); put16(z, 0); put16(z, 0); put16(z, 1); put16(z, 1);
    put32(z, cdSize); put32(z, cdOffset); put16(z, 0);
    return z;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                    [NSString stringWithFormat:@"skzip-%d", getpid()]];
        [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];

        // safeDestinationForEntry
        NSString *root = [tmp stringByAppendingPathComponent:@"root"];
        [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        CHECK([SKZipUtils safeDestinationForEntry:@"a/b.txt" inDirectory:root] != nil, "plain entry is allowed");
        CHECK([SKZipUtils safeDestinationForEntry:@"../x" inDirectory:root] == nil, "../ is rejected");
        CHECK([SKZipUtils safeDestinationForEntry:@"a/../../x" inDirectory:root] == nil, "nested ../ is rejected");
        CHECK([SKZipUtils safeDestinationForEntry:@"/etc/passwd" inDirectory:root] == nil, "absolute is rejected");

        // create -> enumerate round trip
        NSString *src = [tmp stringByAppendingPathComponent:@"src"];
        [fm createDirectoryAtPath:[src stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES
                       attributes:nil error:nil];
        [@"one" writeToFile:[src stringByAppendingPathComponent:@"a.txt"] atomically:YES
                   encoding:NSUTF8StringEncoding error:nil];
        [@"two two two two two two" writeToFile:[src stringByAppendingPathComponent:@"sub/b.txt"] atomically:YES
                                       encoding:NSUTF8StringEncoding error:nil];
        NSString *zipPath = [tmp stringByAppendingPathComponent:@"rt.zip"];
        CHECK([SKZipUtils createZipFileFromDirectory:src toZipPath:zipPath], "zip is created");
        NSMutableDictionary *seen = [NSMutableDictionary dictionary];
        BOOL ok = [SKZipUtils enumerateZip:zipPath usingBlock:^BOOL(NSString *n, NSData *c) {
            seen[n] = [[NSString alloc] initWithData:c encoding:NSUTF8StringEncoding];
            return YES;
        }];
        CHECK(ok && [seen[@"a.txt"] isEqual:@"one"] && [seen[@"sub/b.txt"] hasPrefix:@"two"], "round trip keeps contents");

        // a traversal entry must not land outside the target
        NSString *evilZip = [tmp stringByAppendingPathComponent:@"evil.zip"];
        [StoredZip(@"../evil.txt", [@"x" dataUsingEncoding:NSUTF8StringEncoding], 1) writeToFile:evilZip atomically:YES];
        [SKZipUtils extractZipFile:evilZip toDirectory:root checkProtected:NO protectedFiles:nil];
        CHECK(![fm fileExistsAtPath:[tmp stringByAppendingPathComponent:@"evil.txt"]], "traversal entry is not written");

        // forged sizes and damaged archives are refused, not trusted
        NSString *hugeZip = [tmp stringByAppendingPathComponent:@"huge.zip"];
        [StoredZip(@"big.bin", [@"x" dataUsingEncoding:NSUTF8StringEncoding], 0x7fffffff) writeToFile:hugeZip atomically:YES];
        CHECK(![SKZipUtils enumerateZip:hugeZip usingBlock:^BOOL(NSString *n, NSData *c) { return YES; }],
              "a declared 2 GB entry is refused");
        NSData *good = [NSData dataWithContentsOfFile:zipPath];
        NSString *cutZip = [tmp stringByAppendingPathComponent:@"cut.zip"];
        [[good subdataWithRange:NSMakeRange(0, good.length - 10)] writeToFile:cutZip atomically:YES];
        CHECK(![SKZipUtils enumerateZip:cutZip usingBlock:^BOOL(NSString *n, NSData *c) { return YES; }],
              "a truncated archive is refused");
        NSString *junkZip = [tmp stringByAppendingPathComponent:@"junk.zip"];
        [[NSMutableData dataWithLength:100] writeToFile:junkZip atomically:YES];
        CHECK(![SKZipUtils enumerateZip:junkZip usingBlock:^BOOL(NSString *n, NSData *c) { return YES; }],
              "a file that is not a zip is refused");

        // mod.json: found when nested, ignored when it is not an object
        NSString *modZip = [tmp stringByAppendingPathComponent:@"mod.zip"];
        NSData *json = [@"{\"name\":\"X\",\"type\":\"class\"}" dataUsingEncoding:NSUTF8StringEncoding];
        [StoredZip(@"pack/mod.json", json, (uint32_t)json.length) writeToFile:modZip atomically:YES];
        CHECK([[SKZipUtils readModMetadataFromZip:modZip][@"type"] isEqual:@"class"], "nested mod.json is read");
        NSString *arrZip = [tmp stringByAppendingPathComponent:@"arr.zip"];
        NSData *arr = [@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding];
        [StoredZip(@"mod.json", arr, (uint32_t)arr.length) writeToFile:arrZip atomically:YES];
        CHECK([SKZipUtils readModMetadataFromZip:arrZip] == nil, "a non-object mod.json is ignored");

        // Streamed archives (jar, `zip -`) write sizes after the data, in a data descriptor; only the
        // central directory has them. Real mods are built that way.
        NSString *ddDir = [tmp stringByAppendingPathComponent:@"dd"];
        [fm createDirectoryAtPath:ddDir withIntermediateDirectories:YES attributes:nil error:nil];
        [@"{\"name\":\"Streamed\",\"type\":\"class\"}" writeToFile:[ddDir stringByAppendingPathComponent:@"mod.json"]
                                                                atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *ddZip = [tmp stringByAppendingPathComponent:@"dd.zip"];
        NSString *cmd = [NSString stringWithFormat:@"cd '%@' && /usr/bin/zip -q - mod.json | cat > '%@'", ddDir, ddZip];
        CHECK(system(cmd.UTF8String) == 0, "zip is available to build the fixture");
        NSData *ddData = [NSData dataWithContentsOfFile:ddZip];
        CHECK(ddData.length > 30 && (((const uint8_t *)ddData.bytes)[6] & 0x08), "fixture really uses a data descriptor");
        CHECK([[SKZipUtils readModMetadataFromZip:ddZip][@"name"] isEqual:@"Streamed"], "a data-descriptor archive reads");

        // mod.json written with a trailing comma, as many mods are
        NSString *tc = [SKZipUtils stripTrailingCommas:@"{\"mod\": {\"name\": \"A, }\",\n  \"v\": [1, 2,],\n }\n}"];
        id tcJson = [NSJSONSerialization JSONObjectWithData:[tc dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        CHECK([tcJson[@"mod"][@"name"] isEqual:@"A, }"] && [tcJson[@"mod"][@"v"] count] == 2, "trailing commas are dropped, string contents kept");

        // git blob sha of "hello\n"
        NSString *hello = [tmp stringByAppendingPathComponent:@"hello.txt"];
        [@"hello\n" writeToFile:hello atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK([[SKZipUtils calculateGitBlobShaOfFile:hello] isEqual:@"ce013625030ba8dba906f756967f9e9ca394464a"],
              "git blob sha matches git's");

        [fm removeItemAtPath:tmp error:nil];
    }
    printf(failures ? "%d test(s) failed\n" : "all tests passed\n", failures);
    return failures ? 1 : 0;
}
