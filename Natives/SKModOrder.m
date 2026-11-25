#import "SKModOrder.h"

/// False for an empty or absolute name, or one whose `..` components leave the root.
static BOOL SKStaysInside(NSString *name) {
    if (name.length == 0 || [name hasPrefix:@"/"] || [name hasPrefix:@"\\"] || [name containsString:@"\0"]) return NO;
    NSInteger depth = 0;
    for (NSString *part in [name componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) {
            if (--depth < 0) return NO;
        } else {
            depth++;
        }
    }
    return YES;
}

@implementation SKModOrder

+ (NSInteger)filesWrittenInEntryNames:(NSArray<NSString *> *)entryNames protectedFiles:(NSSet<NSString *> *)protectedFiles {
    NSInteger count = 0;
    for (NSString *name in entryNames) {
        if ([name hasSuffix:@"/"]) continue;
        NSString *base = name.lastPathComponent;
        if ([base isEqualToString:@"mod.json"] || [base isEqualToString:@"mod.png"]) continue;
        if ([protectedFiles containsObject:name.lowercaseString]) continue;
        if (!SKStaysInside(name)) continue;
        count++;
    }
    return count;
}

+ (NSArray<NSString *> *)optimalOrderOfNames:(NSArray<NSString *> *)names
                                filesChanged:(NSInteger (^)(NSString *name))filesChanged {
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionaryWithCapacity:names.count];
    for (NSString *name in names) counts[name] = @(filesChanged(name));
    return [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      NSInteger ca = counts[a].integerValue, cb = counts[b].integerValue;
      if (ca != cb) return ca > cb ? NSOrderedAscending : NSOrderedDescending;  // most files first
      // Literal comparison: the same code-unit order as Android, whatever the user's locale.
      NSComparisonResult byLower = [a.lowercaseString compare:b.lowercaseString options:NSLiteralSearch];
      if (byLower != NSOrderedSame) return byLower;
      return [a compare:b options:NSLiteralSearch];
    }];
}

@end
