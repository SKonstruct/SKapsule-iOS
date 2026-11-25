#import <UIKit/UIKit.h>
#import "SKLayoutShare.h"

typedef NS_ENUM(NSInteger, SKControlType) {
    SKControlTypeButton,
    SKControlTypeJoystickLeft,
    SKControlTypeJoystickRight,
};

/// A single on-screen control. Positions are fractions of the overlay's size and refer to
/// the control's centre, so a layout survives rotation and different devices. Mirrors
/// ControlNode in the Android port (touch/TouchControlModels.kt).
@interface SKControlNode : NSObject
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic, assign) SKControlType type;
@property (nonatomic, assign) CGFloat xPercent;
@property (nonatomic, assign) CGFloat yPercent;
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, assign) BOOL visible;
/// Gamepad button or axis index; -1 when this node emits a key instead.
@property (nonatomic, assign) NSInteger buttonCode;
/// GLFW key code, or -1. Takes precedence over buttonCode.
@property (nonatomic, assign) NSInteger keyCode;
/// Emit buttonCode as an axis (+1 held / -1 released) rather than a button.
@property (nonatomic, assign) BOOL isAxisTrigger;
/// Latching: press flips the state, release emits nothing.
@property (nonatomic, assign) BOOL isToggle;
@property (nonatomic, copy) NSString *label;
/// Part of the bottom action row (attacks + items), which has its own show/hide switch.
@property (nonatomic, assign) BOOL isActionBar;
@end

@interface SKTouchLayout : NSObject
@property (nonatomic, assign) CGFloat globalOpacity;
@property (nonatomic, assign) BOOL controlsEnabled;
@property (nonatomic, assign) BOOL actionBarVisible;
@property (nonatomic, assign) CGFloat renderScale;
@property (nonatomic, strong) NSMutableArray<SKControlNode *> *nodes;

+ (instancetype)defaultLayout;
+ (instancetype)loadLayout;
- (void)save;
@end

/// Presets and export/import (see SKLayoutShare.h). Only the arrangement moves: what a control
/// sends is never read from a shared layout.
@interface SKTouchLayout (Sharing)
/// The node ids this build has: the only ones an imported layout may touch.
+ (NSSet<NSString *> *)knownNodeIds;
- (SKSharedLayout *)sharedLayoutNamed:(NSString *)name;
/// Lays `shared` over the live nodes (position, size, visibility) plus opacity and "Show
/// Buttons"; nil means the built-in default arrangement. A node the layout doesn't mention takes
/// its default. `controlsEnabled` and `renderScale` are left alone. Doesn't save.
- (void)applySharedLayout:(SKSharedLayout *)shared;
@end

extern const CGFloat SKMinOpacity;
extern const CGFloat SKDefaultOpacity;
extern const CGFloat SKMinRenderScale;
extern const CGFloat SKMaxRenderScale;
extern const CGFloat SKMinNodeScale;
extern const CGFloat SKMaxNodeScale;

/// ESC's default centre and every button's edge, both as fractions of the surface width
/// (height, for the y). The chrome row lines up beside ESC, so it reads these too.
extern const CGFloat SKEscXPercent;
extern const CGFloat SKEscYPercent;
extern const CGFloat SKButtonWidthPercent;
