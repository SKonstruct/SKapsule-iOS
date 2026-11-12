#pragma once

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SKLoginMode) {
    SKLoginModeWeb,
    SKLoginModeSteam,
};

@interface GameViewController : UIViewController
@property (nonatomic, assign) SKLoginMode loginMode;
@property (nonatomic, copy) NSString *steamUser;
@property (nonatomic, copy) NSString *steamPass;
/// Optional quick login for Web mode, and the server (the game's server_host) it belongs to.
@property (nonatomic, copy) NSString *webUser;
@property (nonatomic, copy) NSString *webPass;
@property (nonatomic, copy) NSString *loginHost;
@end
