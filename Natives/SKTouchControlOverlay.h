#import <UIKit/UIKit.h>
#import "SKTouchControls.h"

@class SKTouchControlOverlay;

@protocol SKTouchControlOverlayDelegate <NSObject>
/// Fired when the user finishes dragging the resolution slider (not while dragging, so the
/// framebuffer isn't rebuilt on every step).
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeRenderScale:(CGFloat)renderScale;
@optional
/// Sharpening or Sharp HUD changed (read them back from SKGfxSettings.h): the surface and the native pass follow.
- (void)touchOverlayDidChangeGfx:(SKTouchControlOverlay *)overlay;
/// The FPS counter was switched on or off.
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeFpsVisible:(BOOL)visible;
/// "Avoid screen edges" was switched (the default `avoid_screen_edges` holds it): the host re-insets the play area.
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeAvoidEdges:(BOOL)avoid;
/// The mouse cursor was switched on or off (read it back from SKGfxSettings.h).
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeCursorVisible:(BOOL)visible;
/// Appearance changed (opacity, Show Controls, Show Buttons). The host uses it to keep the
/// chrome buttons in step; without it they only catch up on the next layout pass.
- (void)touchOverlayDidChangeAppearance:(SKTouchControlOverlay *)overlay;
@end

@interface SKTouchControlOverlay : UIView
@property (nonatomic, strong, readonly) SKTouchLayout *layout;
@property (nonatomic, assign, readonly, getter=isEditing) BOOL editing;
@property (nonatomic, weak) id<SKTouchControlOverlayDelegate> delegate;

- (void)toggleEditMode;

/// Set by the host (the standalone editor and the game) to open the layout library (presets,
/// export, import); setting it is what reveals the panel's "Layouts…" button.
@property (nonatomic, copy) void (^layoutLibraryHandler)(void);

/// Replaces the arrangement with a shared layout (nil = the built-in default), keeping
/// `controlsEnabled` and the render scale, then saves and refreshes the panel.
- (void)applySharedLayout:(SKSharedLayout *)shared;

/// "Show Buttons" state and a toggle for it, so the chrome eye button and the editor
/// switch drive the same setting.
@property (nonatomic, assign, readonly) BOOL buttonsVisible;
- (BOOL)toggleButtonsVisible;
@end
