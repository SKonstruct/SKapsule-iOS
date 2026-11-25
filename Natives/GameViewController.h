#pragma once

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SKLoginMode) {
    SKLoginModeWeb,
    SKLoginModeSteam,
};

@interface GameViewController : UIViewController
@property (nonatomic, assign) SKLoginMode loginMode;
/// A Steam launch with no stored sign-in: the screen starts in portrait for the QR code and turns
/// landscape when the sign-in ends, before the game starts.
@property (nonatomic, assign) BOOL signInInPortrait;
/// Optional quick login for Web mode, and the server (the game's server_host) it belongs to.
@property (nonatomic, copy) NSString *webUser;
@property (nonatomic, copy) NSString *webPass;
@property (nonatomic, copy) NSString *loginHost;
@end
