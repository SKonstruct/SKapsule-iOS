#import "SKLayoutShare.h"

// Defined in SKTouchControls.m (the editor's own limits); a macOS test defines them itself.
extern const CGFloat SKMinOpacity;
extern const CGFloat SKMinNodeScale;
extern const CGFloat SKMaxNodeScale;

NSString *const SKLayoutShareErrorDomain = @"SKLayoutShare";
const NSUInteger SKLayoutShareMaxBytes = 64 * 1024;
const NSUInteger SKLayoutShareMaxNodes = 64;
const NSUInteger SKLayoutShareMaxNameLength = 40;
const NSUInteger SKLayoutShareMaxPresets = 32;
NSString *const SKLayoutBuiltInName = @"Default";

static NSString *const kFormat = @"skapsule-controls";
static const NSInteger kVersion = 1;
static NSString *const kDefaultImportName = @"Imported";
static NSString *const kPresetsKey = @"touch_layout_presets";
static NSString *const kActiveKey = @"touch_layout_active";

static BOOL SKRefuse(NSError **error, SKLayoutShareError code, NSString *why) {
    if (error) *error = [NSError errorWithDomain:SKLayoutShareErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : why}];
    return NO;
}

/// JSON `true`/`false` arrive as NSNumber too, so tell them apart: a number field holding a
/// boolean is as wrong as it is on Android (`as? Number` rejects a Boolean).
static BOOL SKIsBool(id v) {
    return [v isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID();
}

static BOOL SKFiniteNumber(id v, double *out) {
    if (![v isKindOfClass:NSNumber.class] || SKIsBool(v)) return NO;
    double d = [v doubleValue];
    if (!isfinite(d)) return NO;
    *out = d;
    return YES;
}

/// An integral JSON number ("1", not "1.0"), like Android's `as? Int`.
static BOOL SKIntegerNumber(id v, NSInteger *out) {
    if (![v isKindOfClass:NSNumber.class] || SKIsBool(v)) return NO;
    if (CFNumberIsFloatType((__bridge CFNumberRef)v)) return NO;
    *out = [v integerValue];
    return YES;
}

static double SKClamp(double v, double lo, double hi) { return MIN(MAX(v, lo), hi); }

@implementation SKSharedNode
@end

@implementation SKSharedLayout

+ (NSString *)cleanName:(NSString *)raw {
    NSString *s = [raw isKindOfClass:NSString.class] ? raw : @"";
    s = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@""];
    NSCharacterSet *blank = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    s = [s stringByTrimmingCharactersInSet:blank];
    if (s.length > SKLayoutShareMaxNameLength) {
        // Cut on a character boundary, not in the middle of a surrogate pair or emoji.
        NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:SKLayoutShareMaxNameLength - 1];
        NSUInteger cut = NSMaxRange(r) > SKLayoutShareMaxNameLength ? r.location : SKLayoutShareMaxNameLength;
        s = [[s substringToIndex:cut] stringByTrimmingCharactersInSet:blank];
    }
    return s.length ? s : kDefaultImportName;
}

+ (instancetype)parseData:(NSData *)data knownIds:(NSSet<NSString *> *)knownIds error:(NSError **)error {
    if (data.length > SKLayoutShareMaxBytes) {
        SKRefuse(error, SKLayoutShareErrorTooLarge, @"file too large");
        return nil;
    }
    id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class]) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"unreadable JSON");
        return nil;
    }
    if (![root[@"format"] isEqual:kFormat]) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"not a SKapsule controls file");
        return nil;
    }
    NSInteger version = 0;
    if (!SKIntegerNumber(root[@"version"], &version)) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"no version");
        return nil;
    }
    if (version > kVersion) {
        SKRefuse(error, SKLayoutShareErrorNewer, @"made by a newer version");
        return nil;
    }
    if (version != kVersion) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"unsupported version");
        return nil;
    }

    NSArray *array = root[@"nodes"];
    if (![array isKindOfClass:NSArray.class] || array.count == 0 || array.count > SKLayoutShareMaxNodes) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"bad nodes");
        return nil;
    }
    NSMutableArray<SKSharedNode *> *nodes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in array) {
        double x = 0, y = 0, scale = 0;
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSString.class] ||
            !SKFiniteNumber(entry[@"xPercent"], &x) || !SKFiniteNumber(entry[@"yPercent"], &y) ||
            !SKFiniteNumber(entry[@"scale"], &scale) || !SKIsBool(entry[@"visible"]) ||
            // Optional, so a file from before floating sticks still parses; present, it must be a boolean.
            (entry[@"floating"] != nil && !SKIsBool(entry[@"floating"]))) {
            SKRefuse(error, SKLayoutShareErrorInvalid, @"bad node");
            return nil;
        }
        NSString *nodeId = entry[@"id"];
        // An id this build doesn't have (a newer control) is skipped; a repeat of a known one
        // means the file is inconsistent, so it is refused.
        if (![knownIds containsObject:nodeId]) continue;
        if ([seen containsObject:nodeId]) {
            SKRefuse(error, SKLayoutShareErrorInvalid, @"duplicate id");
            return nil;
        }
        [seen addObject:nodeId];
        SKSharedNode *node = [SKSharedNode new];
        node.nodeId = nodeId;
        node.xPercent = SKClamp(x, 0, 1);
        node.yPercent = SKClamp(y, 0, 1);
        node.scale = SKClamp(scale, SKMinNodeScale, SKMaxNodeScale);
        node.visible = [entry[@"visible"] boolValue];
        node.floating = [entry[@"floating"] boolValue];
        [nodes addObject:node];
    }
    double opacity = 0;
    if (nodes.count == 0 || !SKFiniteNumber(root[@"globalOpacity"], &opacity) || !SKIsBool(root[@"actionBarVisible"])) {
        SKRefuse(error, SKLayoutShareErrorInvalid, @"missing fields");
        return nil;
    }
    SKSharedLayout *layout = [SKSharedLayout new];
    layout.name = [self cleanName:root[@"name"]];
    layout.globalOpacity = SKClamp(opacity, SKMinOpacity, 1.0);
    layout.actionBarVisible = [root[@"actionBarVisible"] boolValue];
    layout.nodes = nodes;
    return layout;
}

- (NSDictionary *)dictionary {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.nodes.count];
    for (SKSharedNode *n in self.nodes) {
        NSMutableDictionary *entry = [@{
            @"id" : n.nodeId,
            @"xPercent" : @(n.xPercent),
            @"yPercent" : @(n.yPercent),
            @"scale" : @(n.scale),
            @"visible" : @(n.visible),
        } mutableCopy];
        // Written only when on, so a file from before floating sticks reads as not floating.
        if (n.floating) entry[@"floating"] = @YES;
        [out addObject:entry];
    }
    return @{
        @"format" : kFormat,
        @"version" : @(kVersion),
        @"name" : self.name ?: kDefaultImportName,
        @"globalOpacity" : @(self.globalOpacity),
        @"actionBarVisible" : @(self.actionBarVisible),
        @"nodes" : out,
    };
}

- (NSData *)jsonData {
    return [NSJSONSerialization dataWithJSONObject:[self dictionary] options:NSJSONWritingPrettyPrinted error:nil];
}

- (SKSharedNode *)nodeForId:(NSString *)nodeId {
    for (SKSharedNode *n in self.nodes) {
        if ([n.nodeId isEqualToString:nodeId]) return n;
    }
    return nil;
}

@end

@implementation SKLayoutPresets {
    NSUserDefaults *_defaults;
    NSSet<NSString *> *_knownIds;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults knownIds:(NSSet<NSString *> *)knownIds {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _knownIds = knownIds;
    }
    return self;
}

- (NSString *)active {
    return [_defaults stringForKey:kActiveKey];
}

- (void)setActive:(NSString *)active {
    if (active) [_defaults setObject:active forKey:kActiveKey];
    else [_defaults removeObjectForKey:kActiveKey];
}

- (NSArray<SKSharedLayout *> *)all {
    NSString *text = [_defaults stringForKey:kPresetsKey];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    id array = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![array isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<SKSharedLayout *> *out = [NSMutableArray array];
    for (id entry in array) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSData *one = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
        SKSharedLayout *layout = one ? [SKSharedLayout parseData:one knownIds:_knownIds error:nil] : nil;
        if (layout) [out addObject:layout];
    }
    return out;
}

- (SKSharedLayout *)presetNamed:(NSString *)name {
    for (SKSharedLayout *l in [self all]) {
        if ([l.name isEqualToString:name]) return l;
    }
    return nil;
}

- (void)write:(NSArray<SKSharedLayout *> *)list {
    NSMutableArray *dicts = [NSMutableArray arrayWithCapacity:list.count];
    for (SKSharedLayout *l in list) [dicts addObject:[l dictionary]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dicts options:0 error:nil];
    if (data) [_defaults setObject:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:kPresetsKey];
}

- (NSString *)addLayout:(SKSharedLayout *)layout {
    NSArray<SKSharedLayout *> *current = [self all];
    if (current.count >= SKLayoutShareMaxPresets) return nil;
    NSMutableSet<NSString *> *taken = [NSMutableSet setWithObject:SKLayoutBuiltInName.lowercaseString];
    for (SKSharedLayout *l in current) [taken addObject:l.name.lowercaseString];
    NSString *base = [SKSharedLayout cleanName:layout.name];
    NSString *name = base;
    for (NSInteger n = 2; [taken containsObject:name.lowercaseString]; n++) {
        NSString *suffix = [NSString stringWithFormat:@" (%ld)", (long)n];
        NSString *head = base.length > SKLayoutShareMaxNameLength - suffix.length
                             ? [base substringToIndex:SKLayoutShareMaxNameLength - suffix.length]
                             : base;
        name = [[head stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                   stringByAppendingString:suffix];
    }
    SKSharedLayout *saved = [SKSharedLayout new];
    saved.name = name;
    saved.globalOpacity = layout.globalOpacity;
    saved.actionBarVisible = layout.actionBarVisible;
    saved.nodes = layout.nodes;
    [self write:[current arrayByAddingObject:saved]];
    return name;
}

- (void)deleteNamed:(NSString *)name {
    NSMutableArray<SKSharedLayout *> *keep = [NSMutableArray array];
    for (SKSharedLayout *l in [self all]) {
        if (![l.name isEqualToString:name]) [keep addObject:l];
    }
    [self write:keep];
    if ([self.active isEqualToString:name]) self.active = nil;
}

@end
