#import <UIKit/UIKit.h>

@class SKTouchControlOverlay;

/// The layout library UI: the built-in default, the user's named presets, and export/import of a
/// layout as a file (see SKLayoutShare.h for the format and what a file may change). Shared by the
/// standalone editor and the in-game editor; both hand it a presenting view controller and the
/// overlay being edited. Applying anything replaces the arrangement, so it always asks first, and
/// import never overwrites a preset (it saves under a new name and offers to apply it). Mirrors
/// LayoutLibraryController.kt on Android. The owner must keep a strong reference to it.
@interface SKLayoutLibrary : NSObject <UIDocumentPickerDelegate>
- (instancetype)initWithPresenter:(UIViewController *)presenter overlay:(SKTouchControlOverlay *)overlay;
/// Shows the list (and, from there, everything else).
- (void)show;
@end
