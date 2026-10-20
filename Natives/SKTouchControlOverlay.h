#import <UIKit/UIKit.h>
#import "SKTouchControls.h"

@class SKTouchControlOverlay;

@protocol SKTouchControlOverlayDelegate <NSObject>
/// Fired when the user finishes dragging the resolution slider (not while dragging, so the
/// framebuffer isn't rebuilt on every step).
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeRenderScale:(CGFloat)renderScale;
@optional
/// Appearance changed (opacity, Show Controls, Show Buttons). The host uses it to keep the
/// chrome buttons in step; without it they only catch up on the next layout pass.
- (void)touchOverlayDidChangeAppearance:(SKTouchControlOverlay *)overlay;
@end

@interface SKTouchControlOverlay : UIView
@property (nonatomic, strong, readonly) SKTouchLayout *layout;
@property (nonatomic, assign, readonly, getter=isEditing) BOOL editing;
@property (nonatomic, weak) id<SKTouchControlOverlayDelegate> delegate;

- (void)toggleEditMode;

/// "Show Buttons" state and a toggle for it, so the chrome eye button and the editor
/// switch drive the same setting.
@property (nonatomic, assign, readonly) BOOL buttonsVisible;
- (BOOL)toggleButtonsVisible;
@end
