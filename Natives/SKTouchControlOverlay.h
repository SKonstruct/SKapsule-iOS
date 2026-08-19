#import <UIKit/UIKit.h>
#import "SKTouchControls.h"

@class SKTouchControlOverlay;

@protocol SKTouchControlOverlayDelegate <NSObject>
/// Fired when the user finishes dragging the resolution slider (not while dragging, so the
/// framebuffer isn't rebuilt on every step).
- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeRenderScale:(CGFloat)renderScale;
@end

@interface SKTouchControlOverlay : UIView
@property (nonatomic, strong, readonly) SKTouchLayout *layout;
@property (nonatomic, assign, readonly, getter=isEditing) BOOL editing;
@property (nonatomic, weak) id<SKTouchControlOverlayDelegate> delegate;

- (void)toggleEditMode;
@end
