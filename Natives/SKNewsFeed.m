#import "SKNewsFeed.h"

/**
 * The home-screen events, from KnightLauncher's "Flamingo" service — the
 * same feed the desktop launcher renders, maintained by its author, so both
 * launchers show the same thing at the same time.
 *
 * The service speaks plain HTTP on port 6060 (it has no TLS listener at all), so
 * everything it returns is treated as hostile: the image and the link are dropped
 * unless they are HTTPS, and the image download is size-capped.
 */

// machineId is a constant, not a device id: Flamingo uses it to bind beta codes,
// which we never redeem, so identifying this install buys nothing and leaks something.
static NSString *const kFeedURL =
  @"http://flamingo.knightlauncher.com:6060/server-list/?machineId=skapsule-ios";

static NSString *const kCacheKey = @"news_cache_json";
static NSString *const kCacheTimeKey = @"news_cache_time";
static const NSTimeInterval kCacheTTL = 6 * 60 * 60;
static const NSUInteger kMaxFeedBytes = 256 * 1024;
static const NSUInteger kMaxImageBytes = 1024 * 1024;
// A small file can declare a huge canvas; the pixel count is what decoding costs.
static const CGFloat kMaxImageSide = 4096;
static const CGFloat kMaxImagePixels = 8 * 1024 * 1024;

@implementation SKNewsItem
- (BOOL)isEndingSoon {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    return self.endsAt > 0 && self.startsAt <= now && now < self.endsAt &&
           self.endsAt - now < 2 * 24 * 60 * 60;
}
@end

#pragma mark - Parsing

/// A field as a string: numbers become their decimal form (as Android's optString and
/// KnightLauncher's getLong both accept either), anything else @"".
static NSString *sk_str(NSDictionary *d, NSString *key) {
    id v = d[key];
    if ([v isKindOfClass:NSString.class]) return v;
    return [v isKindOfClass:NSNumber.class] ? [v stringValue] : @"";
}

/**
 * One event, or nil if it has no title. The service is cleartext, so the image and link
 * are only kept when they are HTTPS; an event without them still shows, as it does
 * upstream, just without a banner or a tap target. Each field packs two values: banner
 * is `url|intensity` (the intensity is the desktop launcher's dimming factor; we use our
 * own scrim) and content is `title|body`. Timestamps are milliseconds, as strings.
 */
static SKNewsItem *sk_event(NSString *banner, NSString *content, NSString *link,
                            NSString *startsAt, NSString *endsAt) {
    NSRange split = [content rangeOfString:@"|"];
    NSString *title = split.location == NSNotFound ? content : [content substringToIndex:split.location];
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (title.length == 0 || [title caseInsensitiveCompare:@"null"] == NSOrderedSame) return nil;

    SKNewsItem *item = [SKNewsItem new];
    item.title = title;
    item.body = split.location == NSNotFound
                  ? @""
                  : [[content substringFromIndex:NSMaxRange(split)] stringByReplacingOccurrencesOfString:@"\\n"
                                                                                               withString:@"\n"];
    NSString *imageURL = [banner componentsSeparatedByString:@"|"].firstObject;
    item.imageURL = [imageURL hasPrefix:@"https://"] ? imageURL : nil;
    item.link = [link hasPrefix:@"https://"] ? link : nil;
    item.startsAt = startsAt.doubleValue / 1000.0;
    item.endsAt = endsAt.doubleValue / 1000.0;
    return item;
}

/**
 * Mirrors KnightLauncher 2.8's LauncherEventHandler.updateBanner: the Official server's
 * `events`, minus any that have already ended (upcoming ones stay), and `defaultEvent*`
 * only when nothing else is left. The legacy `announce*` fields are still sent for older
 * launchers but KnightLauncher no longer reads them, so neither do we.
 */
static NSArray<SKNewsItem *> *sk_parse(NSData *data) {
    // Flamingo writes a trailing comma after the last field of every `events` entry.
    // JSON5 parsing accepts that by definition; plain parsing only happens to on newer OSes.
    NSJSONReadingOptions options = NSJSONReadingJSON5Allowed;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:options error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return @[];
    NSArray *servers = json[@"serverlist"];
    if (![servers isKindOfClass:NSArray.class]) return @[];

    NSDictionary *server = nil;
    for (NSDictionary *candidate in servers) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        if (!server) server = candidate;
        if ([sk_str(candidate, @"name") isEqualToString:@"Official"]) {
            server = candidate;
            break;
        }
    }
    if (!server) return @[];

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableArray<SKNewsItem *> *items = [NSMutableArray array];
    NSArray *events = [server[@"events"] isKindOfClass:NSArray.class] ? server[@"events"] : @[];
    for (NSDictionary *e in events) {
        if (![e isKindOfClass:NSDictionary.class]) continue;
        SKNewsItem *item = sk_event(sk_str(e, @"banner"), sk_str(e, @"content"), sk_str(e, @"link"),
                                    sk_str(e, @"startsAt"), sk_str(e, @"endsAt"));
        if (item && (item.endsAt == 0 || item.endsAt > now)) [items addObject:item];
    }
    if (items.count > 0) return items;

    SKNewsItem *fallback = sk_event(sk_str(server, @"defaultEventBanner"), sk_str(server, @"defaultEventContent"),
                                    sk_str(server, @"defaultEventLink"), sk_str(server, @"defaultEventStartsAt"),
                                    sk_str(server, @"defaultEventEndsAt"));
    return fallback ? @[ fallback ] : @[];
}

#pragma mark - Capped download

/// Collects a response body, cancelling the transfer as soon as it passes `limit`, rather than
/// buffering whatever an unauthenticated host sends.
@interface SKCappedFetch : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, assign) NSUInteger limit;
@property (nonatomic, strong) NSMutableData *body;
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) BOOL overflow;
@property (nonatomic, copy) void (^done)(NSData *data);
@end

@implementation SKCappedFetch
- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (self.status != 200 || response.expectedContentLength > (long long)self.limit) {
        self.overflow = self.status == 200;
        handler(NSURLSessionResponseCancel);
        return;
    }
    handler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    [self.body appendData:data];
    if (self.body.length > self.limit) {
        self.overflow = YES;
        [task cancel];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    BOOL ok = !error && !self.overflow && self.status == 200 && self.body.length > 0;
    self.done(ok ? self.body : nil);
}
@end

/// Calls `done` off the main queue with the body, or nil on any error, non-200, or oversize.
static void sk_fetch_capped(NSURLRequest *request, NSUInteger limit, void (^done)(NSData *data)) {
    SKCappedFetch *fetch = [SKCappedFetch new];
    fetch.limit = limit;
    fetch.body = [NSMutableData data];
    fetch.done = done;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                                          delegate:fetch
                                                     delegateQueue:nil];
    [[session dataTaskWithRequest:request] resume];
    [session finishTasksAndInvalidate];  // releases the delegate once the task is done
}

#pragma mark - Public API

void SKNewsFetch(void (^completion)(NSArray<SKNewsItem *> *)) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *cached = [defaults dataForKey:kCacheKey];
    NSDate *cachedAt = [defaults objectForKey:kCacheTimeKey];

    if (cached && cachedAt && -cachedAt.timeIntervalSinceNow < kCacheTTL) {
        NSArray<SKNewsItem *> *items = sk_parse(cached);
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(items);
        });
        return;
    }

    NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kFeedURL]];
    [request setValue:@"SKapsule-iOS" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 10;

    sk_fetch_capped(request, kMaxFeedBytes, ^(NSData *data) {
      // Parse first: a captive portal's 200 must not replace a good cache.
      NSArray<SKNewsItem *> *items = data ? sk_parse(data) : @[];
      if (items.count > 0) {
          [defaults setObject:data forKey:kCacheKey];
          [defaults setObject:NSDate.date forKey:kCacheTimeKey];
      } else if (cached) {
          // A stale cache still beats an empty home screen.
          items = sk_parse(cached);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(items);
      });
    });
}

void SKNewsFetchImage(NSString *urlString, void (^completion)(UIImage *)) {
    if (![urlString hasPrefix:@"https://"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(nil);
        });
        return;
    }

    NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                            NSUserDomainMask, YES)
                           .firstObject;
    NSString *path = [cacheDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"news-%lx.img",
                                                            (unsigned long)urlString.hash]];

    NSData *onDisk = [NSData dataWithContentsOfFile:path];
    if (onDisk.length > 0) {
        UIImage *image = [UIImage imageWithData:onDisk];
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(image);
        });
        return;
    }

    NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:@"SKapsule-iOS" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 15;

    sk_fetch_capped(request, kMaxImageBytes, ^(NSData *data) {
      UIImage *image = data ? [UIImage imageWithData:data] : nil;
      CGFloat w = image.size.width * image.scale, h = image.size.height * image.scale;
      if (image && (w > kMaxImageSide || h > kMaxImageSide || w * h > kMaxImagePixels)) image = nil;
      if (image) [data writeToFile:path atomically:YES];
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(image);
      });
    });
}

/// "2d" / "5h" / "soon" for a span, for the chip to prefix.
static NSString *sk_span(NSTimeInterval remaining) {
    int hours = (int)(remaining / 3600);
    if (hours >= 48) return [NSString stringWithFormat:@"%dd", hours / 24];
    if (hours >= 1) return [NSString stringWithFormat:@"%dh", hours];
    return @"soon";
}

NSString *SKNewsStatusLabel(NSTimeInterval startsAt, NSTimeInterval endsAt) {
    if (startsAt <= 0 && endsAt <= 0) return nil;  // evergreen: nothing to count down
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (startsAt > now) return [NSString stringWithFormat:@"Starts in %@", sk_span(startsAt - now)];
    if (endsAt > 0 && endsAt <= now) return @"Ended";
    if (endsAt > 0) return [NSString stringWithFormat:@"Ends in %@", sk_span(endsAt - now)];
    return nil;
}
