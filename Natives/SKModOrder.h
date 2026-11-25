#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The order mods are applied in, worked out automatically; there is no manual order.
///
/// A later mod wins when two change the same file. The rule is SKradle's "optimal" order
/// (`core::mods::list`) and Android's `ModsOrder.kt`: the mods that change the most files go first,
/// equal ones by name, so a small, targeted mod comes later and beats a broad one. It is a total
/// order, so it agrees for every pair of mods and does not depend on the order the filesystem lists
/// them in (`contentsOfDirectoryAtPath:` leaves it undefined). Foundation only, so it builds in a
/// plain macOS test. Keep it in step with the Android file: both are checked by the same cases.
@interface SKModOrder : NSObject

/// How many files a mod writes, from the entry names of one archive: not a directory, not
/// `mod.json` / `mod.png` (at any depth, as extraction skips them), not a protected game file
/// (`protectedFiles`, lowercase, compared case-insensitively) and not a path that climbs out of
/// the extraction root.
+ (NSInteger)filesWrittenInEntryNames:(NSArray<NSString *> *)entryNames protectedFiles:(NSSet<NSString *> *)protectedFiles;

/// `names` in apply order: most files first, then by name ignoring case, then by exact name.
/// `filesChanged` is asked once per name.
+ (NSArray<NSString *> *)optimalOrderOfNames:(NSArray<NSString *> *)names
                                filesChanged:(NSInteger (^)(NSString *name))filesChanged;

@end

NS_ASSUME_NONNULL_END
