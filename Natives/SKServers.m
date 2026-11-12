#import "SKServers.h"
#import "SKZipUtils.h"

NSString *const SKServerIdKey = @"id";
NSString *const SKServerNameKey = @"name";
NSString *const SKServerHostKey = @"host";
NSString *const SKServerPortKey = @"port";
NSString *const SKServerPublicKeyKey = @"publicKey";
NSString *const SKServerClientURLKey = @"clientUrl";
NSString *const SKServerContentURLKey = @"contentUrl";

static NSString *const kServersDefaultsKey = @"servers.list";
static NSString *const kSelectedDefaultsKey = @"servers.selected";

static NSString *const kOfficialHost = @"game.spiralknights.com";
static const NSInteger kOfficialPort = 47624;
static NSString *const kOfficialClientURL = @"http://gamemedia2.spiralknights.com";
static NSString *const kOfficialContentURL = @"http://content.spiralknights.com/";
static NSString *const kOfficialKey =
  @"a5ed0dc3892b9472cfb668e236064e989e95945dad18f3d7e7d8e474d6e03de38bc044c3429b9ca649d0881d601c0eb8ffebc3756f0503f73a8ca"
  @"1760943ea0e8921ad6f8102026586db3133844bbadbcfcfc666d23982d7684511fbf6cd8bb1d02a14270d0854098d16fe88f99c05825b0fe1b6fd4"
  @"97709106f2c418796aaf7aab7c92f26fcd9fbb3c43df48075fed8dd931273a7b0a333c8de5967797874c1944aed65b47f0792b273a529ac22a2dce"
  @"08dad04eeebeeff67c7bc99b97682bff488038b28e24f4b5eea77ed966caede52f2c1ecf2b403110a9765daa81ddf718129a040823bead3a0bdca7"
  @"0ef6d08f483757a6d3b6e01fbbcb32006b7872bcd#10001";

static NSString *SKStr(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:NSString.class] ? v : @"";
}

static NSInteger SKPort(NSDictionary *d) {
    id v = d[SKServerPortKey];
    return [v isKindOfClass:NSNumber.class] ? [v integerValue] : 0;
}

/// A stored record is third-party-shaped data: drop it unless every required field is the right type.
static BOOL SKRecordUsable(id record) {
    if (![record isKindOfClass:NSDictionary.class]) return NO;
    NSInteger port = SKPort(record);
    return SKStr(record, SKServerIdKey).length && SKStr(record, SKServerNameKey).length &&
           SKStr(record, SKServerHostKey).length && port >= 1 && port <= 65535;
}

static BOOL SKMatches(NSString *pattern, NSString *s) {
    return [s rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL SKHttpURLOrBlank(NSString *url) {
    if (!url.length) return YES;
    NSURLComponents *c = [NSURLComponents componentsWithString:url];
    NSString *scheme = c.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && c.host.length > 0;
}

/// Java .properties escaping for a value: backslash, the separators and comment markers, and a leading space.
static NSString *SKEscapeValue(NSString *value) {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (c == '\\' || c == ':' || c == '=' || c == '#' || c == '!' || (c == ' ' && i == 0)) [out appendString:@"\\"];
        [out appendFormat:@"%C", c];
    }
    return out;
}

static NSString *SKUnescape(NSString *s) {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' && i + 1 < s.length) c = [s characterAtIndex:++i];
        [out appendFormat:@"%C", c];
    }
    return out;
}

/// Splits a "key=value" / "key: value" / "key value" line; NO for blanks and comments.
static BOOL SKSplitLine(NSString *line, NSString **key, NSString **value) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!trimmed.length || [trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"!"]) return NO;
    NSUInteger i = 0;
    while (i < trimmed.length) {
        unichar c = [trimmed characterAtIndex:i];
        if (c == '\\') { i += 2; continue; }
        if (c == '=' || c == ':' || c == ' ' || c == '\t') break;
        i++;
    }
    if (i > trimmed.length) i = trimmed.length;
    *key = SKUnescape([trimmed substringToIndex:i]);
    NSString *rest = [trimmed substringFromIndex:i];
    rest = [rest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([rest hasPrefix:@"="] || [rest hasPrefix:@":"]) rest = [[rest substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    *value = SKUnescape(rest);
    return YES;
}

@implementation SKServers

+ (NSArray<NSDictionary *> *)servers {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:kServersDefaultsKey];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id record in stored) if (SKRecordUsable(record)) [out addObject:record];
    return out;
}

+ (NSDictionary *)selectedServer {
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kSelectedDefaultsKey];
    if (!selected) return nil;
    for (NSDictionary *s in self.servers) if ([SKStr(s, SKServerIdKey) isEqualToString:selected]) return s;
    return nil;
}

+ (void)selectServerWithId:(NSString *)serverId {
    if (serverId) [NSUserDefaults.standardUserDefaults setObject:serverId forKey:kSelectedDefaultsKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kSelectedDefaultsKey];
}

+ (void)saveServer:(NSDictionary *)server {
    NSMutableArray *list = [NSMutableArray array];
    BOOL replaced = NO;
    for (NSDictionary *s in self.servers) {
        if ([SKStr(s, SKServerIdKey) isEqualToString:SKStr(server, SKServerIdKey)]) {
            [list addObject:server];
            replaced = YES;
        } else {
            [list addObject:s];
        }
    }
    if (!replaced) [list addObject:server];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kServersDefaultsKey];
}

+ (void)deleteServerWithId:(NSString *)serverId {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *s in self.servers) if (![SKStr(s, SKServerIdKey) isEqualToString:serverId]) [list addObject:s];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kServersDefaultsKey];
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kSelectedDefaultsKey] isEqualToString:serverId]) {
        [self selectServerWithId:nil];
    }
}

+ (NSString *)newServerId {
    return NSUUID.UUID.UUIDString;
}

+ (SKServerProblem)validateServer:(NSDictionary *)server against:(NSArray<NSDictionary *> *)others {
    NSString *name = SKStr(server, SKServerNameKey), *host = SKStr(server, SKServerHostKey);
    NSString *key = SKStr(server, SKServerPublicKeyKey);
    if (!name.length || name.length > 40) return SKServerProblemName;
    if ([name caseInsensitiveCompare:@"Official"] == NSOrderedSame) return SKServerProblemDuplicate;
    for (NSDictionary *o in others) {
        if (![SKStr(o, SKServerIdKey) isEqualToString:SKStr(server, SKServerIdKey)] &&
            [SKStr(o, SKServerNameKey) caseInsensitiveCompare:name] == NSOrderedSame) {
            return SKServerProblemDuplicate;
        }
    }
    // The host ends up in a Java properties file and a socket address: no whitespace or '/'.
    if (!host.length || host.length > 253 || !SKMatches(@"^[A-Za-z0-9._:\\[\\]-]+$", host)) return SKServerProblemHost;
    NSInteger port = SKPort(server);
    if (port < 1 || port > 65535) return SKServerProblemPort;
    if (key.length && !SKMatches(@"^[0-9a-fA-F]+#[0-9a-fA-F]+$", key)) return SKServerProblemKey;
    if (!SKHttpURLOrBlank(SKStr(server, SKServerClientURLKey)) || !SKHttpURLOrBlank(SKStr(server, SKServerContentURLKey))) {
        return SKServerProblemURL;
    }
    return SKServerProblemNone;
}

+ (NSString *)clientRootForURL:(NSString *)url {
    NSString *trimmed = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return @"";
    NSRange sep = [trimmed rangeOfString:@"://"];
    NSString *scheme = sep.location != NSNotFound && sep.location > 0 ? [trimmed substringToIndex:sep.location].lowercaseString : @"http";
    NSString *rest = sep.location != NSNotFound && sep.location > 0 ? [trimmed substringFromIndex:NSMaxRange(sep)] : trimmed;
    NSString *authority = [rest componentsSeparatedByString:@"/"].firstObject;
    return [NSString stringWithFormat:@"%@://%@", [scheme isEqualToString:@"https"] ? @"https" : @"http", authority];
}

+ (NSDictionary<NSString *, NSString *> *)connectionPropertiesForServer:(NSDictionary *)server {
    NSString *port = [NSString stringWithFormat:@"%ld", (long)(server ? SKPort(server) : kOfficialPort)];
    NSString *key = server ? SKStr(server, SKServerPublicKeyKey) : @"";
    NSString *client = server ? SKStr(server, SKServerClientURLKey) : @"";
    NSString *content = server ? SKStr(server, SKServerContentURLKey) : @"";
    return @{
        @"server_host": server ? SKStr(server, SKServerHostKey) : kOfficialHost,
        @"server_ports": port,
        @"datagram_ports": port,
        @"key.public": key.length ? key : kOfficialKey,
        @"client_root_url": client.length ? [self clientRootForURL:client] : kOfficialClientURL,
        @"content_url": content.length ? content : kOfficialContentURL,
    };
}

+ (NSString *)propertiesText:(NSString *)text withValues:(NSDictionary<NSString *, NSString *> *)values {
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    // A trailing newline splits into an empty last element; keep it last when appending.
    BOOL trailingNewline = lines.count > 0 && lines.lastObject.length == 0;
    if (trailingNewline) [lines removeLastObject];
    NSMutableSet<NSString *> *done = [NSMutableSet set];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *key, *value;
        if (!SKSplitLine(lines[i], &key, &value) || !values[key]) continue;
        lines[i] = [NSString stringWithFormat:@"%@=%@", SKEscapeValue(key), SKEscapeValue(values[key])];
        [done addObject:key];
    }
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![done containsObject:key]) [lines addObject:[NSString stringWithFormat:@"%@=%@", SKEscapeValue(key), SKEscapeValue(values[key])]];
    }
    return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

+ (NSString *)valueForKey:(NSString *)key inPropertiesText:(NSString *)text {
    NSString *found = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *k, *v;
        if (SKSplitLine(line, &k, &v) && [k isEqualToString:key]) found = v; // the last one wins, as in Java
    }
    return found;
}

+ (NSString *)manifestVersionInText:(NSString *)text {
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![trimmed hasPrefix:@"version"]) continue;
        NSString *rest = [[trimmed substringFromIndex:7] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![rest hasPrefix:@"="]) continue;
        NSString *value = [[rest substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return value.length ? value : nil;
    }
    return nil;
}

+ (BOOL)updatePendingForGameAtPath:(NSString *)skPath {
    NSString *localText = [NSString stringWithContentsOfFile:[skPath stringByAppendingPathComponent:@"getdown.txt"]
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    NSString *local = [self manifestVersionInText:localText];
    __block NSString *remote = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURL *url = [NSURL URLWithString:@"https://gamemedia2.spiralknights.com/spiral/latest/getdown.txt"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8];
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
                                     if (!error && ((NSHTTPURLResponse *)response).statusCode == 200 && body.length <= 64 * 1024) {
                                         remote = [self manifestVersionInText:[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding]];
                                     }
                                     dispatch_semaphore_signal(done);
                                   }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    return local && remote && ![local isEqualToString:remote];
}

+ (BOOL)applyServer:(NSDictionary *)server toConfigJar:(NSString *)jarPath error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *(^fail)(NSInteger, NSString *) = ^NSError *(NSInteger code, NSString *message) {
        return [NSError errorWithDomain:@"SKServersDomain" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
    };
    if (![fm fileExistsAtPath:jarPath]) {
        if (error) *error = fail(1, @"The game isn't installed yet.");
        return NO;
    }

    NSDictionary *wanted = [self connectionPropertiesForServer:server];
    __block NSString *current = nil;
    // The handler stops the walk once it has the entry, which also makes the call report NO.
    [SKZipUtils enumerateZip:jarPath
                                    matching:^BOOL(NSString *name) { return [name isEqualToString:@"deployment.properties"]; }
                                  usingBlock:^BOOL(NSString *name, NSData *data) {
                                    current = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
                                    return NO;
                                  }];
    if (!current) {
        if (error) *error = fail(2, @"config.jar has no deployment.properties.");
        return NO;
    }
    BOOL same = YES;
    for (NSString *key in wanted) {
        if (![[self valueForKey:key inPropertiesText:current] isEqualToString:wanted[key]]) same = NO;
    }
    if (same) return YES;

    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"sk-config-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *tmpJar = [jarPath stringByAppendingString:@".server"];
    BOOL ok = NO;
    @try {
        ok = [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil] &&
             [SKZipUtils extractZipFile:jarPath toDirectory:work checkProtected:NO protectedFiles:nil];
        if (ok) {
            NSString *props = [work stringByAppendingPathComponent:@"deployment.properties"];
            NSData *out = [[self propertiesText:current withValues:wanted] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
            ok = [out writeToFile:props atomically:YES];
        }
        [fm removeItemAtPath:tmpJar error:nil];
        ok = ok && [SKZipUtils createZipFileFromDirectory:work toZipPath:tmpJar] &&
             rename(tmpJar.fileSystemRepresentation, jarPath.fileSystemRepresentation) == 0;
    } @finally {
        [fm removeItemAtPath:work error:nil];
        [fm removeItemAtPath:tmpJar error:nil];
    }
    if (!ok && error) *error = fail(3, @"Couldn't rewrite config.jar. Check free space, then try again.");
    return ok;
}

@end
