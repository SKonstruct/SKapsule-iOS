#pragma once

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SKLoginMode);

@interface GameViewController : UIViewController
@property (nonatomic, assign) SKLoginMode loginMode;
@property (nonatomic, copy) NSString *steamUser;
@property (nonatomic, copy) NSString *steamPass;
@end
