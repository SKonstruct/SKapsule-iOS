// Host-side tests of the custom-server settings: validation, the properties edit, and rewriting a real
// config.jar. Built and run by `make test`.
#import "SKServers.h"
#import "SKZipUtils.h"
#import <stdio.h>

static int failures = 0;
#define CHECK(cond, msg)                                   \
    do {                                                   \
        if (!(cond)) {                                     \
            printf("FAIL: %s (line %d)\n", msg, __LINE__); \
            failures++;                                    \
        }                                                  \
    } while (0)

static NSDictionary *Server(NSString *name, NSString *host, NSInteger port, NSString *key, NSString *client, NSString *content) {
    return @{SKServerIdKey: @"a", SKServerNameKey: name, SKServerHostKey: host, SKServerPortKey: @(port),
             SKServerPublicKeyKey: key, SKServerClientURLKey: client, SKServerContentURLKey: content};
}

static NSString *ReadEntry(NSString *jar, NSString *entry) {
    __block NSString *text = nil;
    [SKZipUtils enumerateZip:jar usingBlock:^BOOL(NSString *name, NSData *data) {
      if ([name isEqualToString:entry]) text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      return YES;
    }];
    return text;
}

int main(void) {
    @autoreleasepool {
        NSArray *none = @[];
        CHECK([SKServers validateServer:Server(@"Home", @"10.0.2.2", 47624, @"", @"", @"") against:none] == SKServerProblemNone, "plain server is valid");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"AB12#10001", @"https://h/x", @"http://c") against:none] == SKServerProblemNone, "full server is valid");
        CHECK([SKServers validateServer:Server(@"", @"h", 1, @"", @"", @"") against:none] == SKServerProblemName, "blank name");
        CHECK([SKServers validateServer:Server([@"" stringByPaddingToLength:41 withString:@"x" startingAtIndex:0], @"h", 1, @"", @"", @"") against:none] == SKServerProblemName, "long name");
        CHECK([SKServers validateServer:Server(@"official", @"h", 1, @"", @"", @"") against:none] == SKServerProblemDuplicate, "Official is taken");
        NSDictionary *other = @{SKServerIdKey: @"z", SKServerNameKey: @"HOME"};
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"", @"", @"") against:@[other]] == SKServerProblemDuplicate, "duplicate name, any case");
        NSDictionary *self_ = @{SKServerIdKey: @"a", SKServerNameKey: @"Home"};
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"", @"", @"") against:@[self_]] == SKServerProblemNone, "editing keeps its own name");
        CHECK([SKServers validateServer:Server(@"Home", @"a b", 1, @"", @"", @"") against:none] == SKServerProblemHost, "space in host");
        CHECK([SKServers validateServer:Server(@"Home", @"http://h", 1, @"", @"", @"") against:none] == SKServerProblemHost, "scheme in host");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 0, @"", @"", @"") against:none] == SKServerProblemPort, "port 0");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 70000, @"", @"", @"") against:none] == SKServerProblemPort, "port too big");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"zz#1", @"", @"") against:none] == SKServerProblemKey, "non-hex key");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"abcd", @"", @"") against:none] == SKServerProblemKey, "key without exponent");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"", @"ftp://h", @"") against:none] == SKServerProblemURL, "ftp client url");
        CHECK([SKServers validateServer:Server(@"Home", @"h", 1, @"", @"", @"http://") against:none] == SKServerProblemURL, "url without host");

        CHECK([[SKServers clientRootForURL:@"http://gamemedia2.spiralknights.com/spiral/client/"] isEqualToString:@"http://gamemedia2.spiralknights.com"], "client root drops the path");
        CHECK([[SKServers clientRootForURL:@"HTTPS://h:8080/a/b"] isEqualToString:@"https://h:8080"], "client root keeps scheme and port");
        CHECK([[SKServers clientRootForURL:@"h/x"] isEqualToString:@"http://h"], "client root defaults to http");
        CHECK([[SKServers clientRootForURL:@"  "] isEqualToString:@""], "blank client root");

        NSDictionary *props = [SKServers connectionPropertiesForServer:Server(@"Home", @"10.0.2.2", 5000, @"", @"https://c.example/client/x", @"")];
        CHECK([props[@"server_host"] isEqualToString:@"10.0.2.2"], "host");
        CHECK([props[@"server_ports"] isEqualToString:@"5000"] && [props[@"datagram_ports"] isEqualToString:@"5000"], "ports");
        CHECK([props[@"key.public"] hasSuffix:@"#10001"] && [props[@"key.public"] hasPrefix:@"a5ed0dc3"], "blank key is Official's");
        CHECK([props[@"client_root_url"] isEqualToString:@"https://c.example"], "client root");
        CHECK([props[@"content_url"] isEqualToString:@"http://content.spiralknights.com/"], "blank content url is Official's");
        CHECK([[SKServers connectionPropertiesForServer:nil][@"server_host"] isEqualToString:@"game.spiralknights.com"], "Official host");

        NSString *text = @"#comment\nclient_title=Spiral Knights\nserver_host=game.spiralknights.com\ncontent_url=http\\://c/\n";
        NSString *edited = [SKServers propertiesText:text withValues:@{@"server_host": @"10.0.2.2", @"key.public": @"ab#10001", @"content_url": @"http://x:1/"}];
        CHECK([edited hasPrefix:@"#comment\nclient_title=Spiral Knights\nserver_host=10.0.2.2\n"], "lines replaced in place, others kept");
        CHECK([edited containsString:@"content_url=http\\://x\\:1/\n"], "value escaped like Java");
        CHECK([[SKServers valueForKey:@"content_url" inPropertiesText:edited] isEqualToString:@"http://x:1/"], "escaped value reads back");
        CHECK([[SKServers valueForKey:@"key.public" inPropertiesText:edited] isEqualToString:@"ab#10001"], "appended key reads back");
        CHECK([edited hasSuffix:@"\n"] && ![edited hasSuffix:@"\n\n"], "single trailing newline");

        CHECK([[SKServers manifestVersionInText:@"appbase = http://x/%VERSION%\nversion = 20261110044614\n"] isEqualToString:@"20261110044614"], "manifest version");
        CHECK([[SKServers manifestVersionInText:@"  version=1  "] isEqualToString:@"1"], "manifest version without spaces");
        CHECK([SKServers manifestVersionInText:@"versioned = 2\nappbase = x"] == nil, "versioned is not version");
        CHECK([SKServers manifestVersionInText:nil] == nil, "no manifest");

        // A real jar: other entries survive, the settings switch, and a repeat leaves it alone.
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *src = [root stringByAppendingPathComponent:@"src"];
        [fm createDirectoryAtPath:[src stringByAppendingPathComponent:@"mod"] withIntermediateDirectories:YES attributes:nil error:nil];
        [@"client_title=Spiral Knights\nserver_host=game.spiralknights.com\n" writeToFile:[src stringByAppendingPathComponent:@"deployment.properties"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"bytecode" writeToFile:[src stringByAppendingPathComponent:@"mod/Patched.class"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *jar = [root stringByAppendingPathComponent:@"config.jar"];
        CHECK([SKZipUtils createZipFileFromDirectory:src toZipPath:jar], "test jar built");

        NSError *error = nil;
        NSDictionary *home = Server(@"Home", @"10.0.2.2", 5000, @"ab#10001", @"", @"");
        CHECK([SKServers applyServer:home toConfigJar:jar error:&error], "apply to a custom server");
        NSString *after = ReadEntry(jar, @"deployment.properties");
        CHECK([[SKServers valueForKey:@"server_host" inPropertiesText:after] isEqualToString:@"10.0.2.2"], "jar points at the server");
        CHECK([[SKServers valueForKey:@"key.public" inPropertiesText:after] isEqualToString:@"ab#10001"], "jar has the server key");
        CHECK([[SKServers valueForKey:@"client_title" inPropertiesText:after] isEqualToString:@"Spiral Knights"], "other keys kept");
        CHECK([ReadEntry(jar, @"mod/Patched.class") isEqualToString:@"bytecode"], "other entries kept");
        CHECK(![fm fileExistsAtPath:[jar stringByAppendingString:@".server"]], "no leftover temp jar");

        NSDate *stamp = [fm attributesOfItemAtPath:jar error:nil].fileModificationDate;
        [NSThread sleepForTimeInterval:0.05];
        CHECK([SKServers applyServer:home toConfigJar:jar error:&error], "repeat apply");
        CHECK([[fm attributesOfItemAtPath:jar error:nil].fileModificationDate isEqualToDate:stamp], "unchanged settings do not rewrite the jar");

        CHECK([SKServers applyServer:nil toConfigJar:jar error:&error], "back to Official");
        after = ReadEntry(jar, @"deployment.properties");
        CHECK([[SKServers valueForKey:@"server_host" inPropertiesText:after] isEqualToString:@"game.spiralknights.com"], "Official host restored");
        CHECK([[SKServers valueForKey:@"key.public" inPropertiesText:after] hasPrefix:@"a5ed0dc3"], "Official key restored");

        error = nil;
        CHECK(![SKServers applyServer:home toConfigJar:[root stringByAppendingPathComponent:@"missing.jar"] error:&error] && error.code == 1, "missing jar is code 1");
        [fm removeItemAtPath:root error:nil];
    }
    printf(failures ? "%d test(s) failed\n" : "all server tests passed\n", failures);
    return failures ? 1 : 0;
}
