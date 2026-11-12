#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SKJITPage) {
    SKJITPageChoose = 0,
    SKJITPagePair,
    SKJITPageImport,
    SKJITPageConnect,
    SKJITPageEnable,
    SKJITPageStikDebug,
    SKJITPageTrollStore,
    SKJITPageJailbreak,
};

/// The JIT walkthrough, in a bottom sheet: pick a way in, follow its numbered steps, end with
/// JIT on. Pairing on this device (iOS 27) and a pairing file both lead to built-in JIT and share
/// the last two steps (LocalDevVPN, then enabling); StikDebug, TrollStore and a jailbreak each have
/// one short page. Pages push inside the sheet's own navigation controller.
@interface SKJITSetupViewController : UIViewController

/// A navigation controller holding the first page, configured as a medium/large sheet.
+ (UINavigationController *)sheet;
/// The same, opened at `page` (the Enable page after a failed enable, say).
+ (UINavigationController *)sheetStartingAt:(SKJITPage)page;

@end

NS_ASSUME_NONNULL_END
