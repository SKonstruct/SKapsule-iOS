#import <UIKit/UIKit.h>

/// Offscreen first responder that raises the system keyboard and forwards what the user
/// types into the GLFW event queue. SK expects a real keyboard; without this there is no
/// way to chat or enter text on a device that has none.
@interface SKKeyboardBridge : UIView <UIKeyInput>
/// Shows the keyboard if hidden, hides it if shown. Returns the new visibility.
- (BOOL)toggle;
@end
