#import <Foundation/Foundation.h>

/// The touch-layout export/import format and the preset store. Foundation only, so it builds in
/// a plain macOS test. It is a port of the Android side (touch/TouchLayoutShare.kt and
/// TouchLayoutPresets.kt): the same file must be accepted or refused the same way on both, so
/// change the two together and keep Natives/Tests/fixtures in step.
///
///   { "format": "skapsule-controls", "version": 1, "name": "My layout",
///     "globalOpacity": 0.4, "actionBarVisible": false,
///     "nodes": [ { "id": "btn_esc", "xPercent": 0.06, "yPercent": 0.1, "scale": 1.0, "visible": true } ] }
///
/// Only the arrangement is shared: position, size and visibility of each known node, the global
/// opacity and "Show Buttons". Not `renderScale` (a per-device setting) or `controlsEnabled`, and
/// never what a control sends (type, codes, label): that always comes from the app's own nodes.
/// A file is untrusted: format and version are checked, size and node count capped, numbers must
/// be finite and are clamped to the editor's own ranges, duplicate ids are refused, and ids this
/// build does not know are ignored. Any structural problem refuses the whole file.

extern NSString *const SKLayoutShareErrorDomain;

typedef NS_ENUM(NSInteger, SKLayoutShareError) {
    SKLayoutShareErrorInvalid = 1,
    SKLayoutShareErrorNewer,
    SKLayoutShareErrorTooLarge,
};

extern const NSUInteger SKLayoutShareMaxBytes;
extern const NSUInteger SKLayoutShareMaxNodes;
extern const NSUInteger SKLayoutShareMaxNameLength;
extern const NSUInteger SKLayoutShareMaxPresets;
/// Reserved: a user preset can't take this name, so the list never shows two.
extern NSString *const SKLayoutBuiltInName;

@interface SKSharedNode : NSObject
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic, assign) double xPercent;
@property (nonatomic, assign) double yPercent;
@property (nonatomic, assign) double scale;
@property (nonatomic, assign) BOOL visible;
@end

@interface SKSharedLayout : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double globalOpacity;
@property (nonatomic, assign) BOOL actionBarVisible;
/// In file order; known ids only.
@property (nonatomic, copy) NSArray<SKSharedNode *> *nodes;

/// Trimmed, one line, no control characters, at most 40 characters; "Imported" when empty.
+ (NSString *)cleanName:(NSString *)raw;

/// Nil and *error (domain SKLayoutShareErrorDomain) when the file is refused. `knownIds` is the
/// set of node ids this build has.
+ (instancetype)parseData:(NSData *)data knownIds:(NSSet<NSString *> *)knownIds error:(NSError **)error;

- (NSData *)jsonData;
- (SKSharedNode *)nodeForId:(NSString *)nodeId;
@end

/// The user's named presets (the built-in default is not stored). Entries are stored in the
/// export format and re-validated on every read, so a corrupt entry is skipped, never applied.
@interface SKLayoutPresets : NSObject
@property (nonatomic, copy) NSString *active;  // last applied/saved; a marker, not a promise
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults knownIds:(NSSet<NSString *> *)knownIds;
- (NSArray<SKSharedLayout *> *)all;
- (SKSharedLayout *)presetNamed:(NSString *)name;
/// Saves as a new preset and returns the name it got ("name (2)" when taken or reserved); never
/// overwrites. Nil when the list is full.
- (NSString *)addLayout:(SKSharedLayout *)layout;
- (void)deleteNamed:(NSString *)name;
@end
