#import "LauncherViewController.h"
#import "GameViewController.h"
#import "SKInstaller.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, SKLoginMode) {
    SKLoginModeWeb,
    SKLoginModeSteam,
};

@interface LauncherViewController ()
@property (nonatomic, strong) UIButton *btnPlayWeb;
@property (nonatomic, strong) UIButton *btnPlaySteam;
@property (nonatomic, strong) UILabel  *setupStatus;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL runtimeReady;
@end

@implementation LauncherViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // Title
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"SKapsule";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont boldSystemFontOfSize:32];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"Spiral Knights for iOS";
    subtitleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    subtitleLabel.font = [UIFont systemFontOfSize:14];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitleLabel];

    // Play (Web) button
    self.btnPlayWeb = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.btnPlayWeb setTitle:@"Play (Web)" forState:UIControlStateNormal];
    self.btnPlayWeb.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.btnPlayWeb setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.btnPlayWeb.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:1.0];
    self.btnPlayWeb.layer.cornerRadius = 12;
    self.btnPlayWeb.translatesAutoresizingMaskIntoConstraints = NO;
    [self.btnPlayWeb addTarget:self action:@selector(onPlayWeb)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btnPlayWeb];

    // Play (Steam) button
    self.btnPlaySteam = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.btnPlaySteam setTitle:@"Play (Steam)" forState:UIControlStateNormal];
    self.btnPlaySteam.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.btnPlaySteam setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.btnPlaySteam.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0];
    self.btnPlaySteam.layer.cornerRadius = 12;
    self.btnPlaySteam.layer.borderWidth = 1;
    self.btnPlaySteam.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.btnPlaySteam.translatesAutoresizingMaskIntoConstraints = NO;
    [self.btnPlaySteam addTarget:self action:@selector(onPlaySteam)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btnPlaySteam];

    // Setup status
    self.setupStatus = [[UILabel alloc] init];
    self.setupStatus.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.setupStatus.font = [UIFont systemFontOfSize:13];
    self.setupStatus.textAlignment = NSTextAlignmentCenter;
    self.setupStatus.numberOfLines = 0;
    self.setupStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.setupStatus];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:subtitleLabel.topAnchor constant:-4],

        [subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:self.btnPlayWeb.topAnchor constant:-40],

        [self.btnPlayWeb.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.btnPlayWeb.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.btnPlayWeb.widthAnchor constraintEqualToConstant:220],
        [self.btnPlayWeb.heightAnchor constraintEqualToConstant:50],

        [self.btnPlaySteam.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.btnPlaySteam.topAnchor constraintEqualToAnchor:self.btnPlayWeb.bottomAnchor constant:16],
        [self.btnPlaySteam.widthAnchor constraintEqualToConstant:220],
        [self.btnPlaySteam.heightAnchor constraintEqualToConstant:50],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:self.btnPlaySteam.bottomAnchor constant:24],

        [self.setupStatus.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.setupStatus.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:8],
        [self.setupStatus.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.setupStatus.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    [self setButtonsEnabled:NO];
    [self ensureRuntime];
}

- (void)setButtonsEnabled:(BOOL)enabled {
    self.btnPlayWeb.enabled = enabled;
    self.btnPlaySteam.enabled = enabled;
    self.btnPlayWeb.alpha = enabled ? 1.0 : 0.4;
    self.btnPlaySteam.alpha = enabled ? 1.0 : 0.4;
}

- (void)ensureRuntime {
    if ([SKInstaller isInstalled]) {
        NSLog(@"[Launcher] Runtime already installed");
        [self setButtonsEnabled:YES];
        return;
    }

    [self.spinner startAnimating];
    self.setupStatus.text = @"Setting up runtime…";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [SKInstaller installWithProgress:^(NSString *status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.setupStatus.text = status;
            });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.setupStatus.text = @"";
            self.runtimeReady = YES;
            [self setButtonsEnabled:YES];
        });
    });
}

- (void)onPlayWeb {
    [self launchGameWithMode:SKLoginModeWeb steamUser:@"" steamPass:@""];
}

- (void)onPlaySteam {
    // Check for stored creds first; if present, skip the login prompt
    NSString *credFile = [SKInstaller credFilePath];
    if ([NSFileManager.defaultManager fileExistsAtPath:credFile]) {
        [self launchGameWithMode:SKLoginModeSteam steamUser:@"" steamPass:@""];
        return;
    }
    [self promptSteamLogin];
}

- (void)promptSteamLogin {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Steam Login"
        message:@"Enter your Steam credentials. They are passed directly to the game and never stored by SKapsule."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Steam username";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Steam password";
        tf.secureTextEntry = YES;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Login" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *user = alert.textFields[0].text ?: @"";
            NSString *pass = alert.textFields[1].text ?: @"";
            [self launchGameWithMode:SKLoginModeSteam
                           steamUser:[user stringByTrimmingCharactersInSet:
                               NSCharacterSet.whitespaceCharacterSet]
                           steamPass:pass];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)launchGameWithMode:(SKLoginMode)mode
                 steamUser:(NSString *)user
                 steamPass:(NSString *)pass {
    GameViewController *gameVC = [[GameViewController alloc] init];
    gameVC.loginMode = mode;
    gameVC.steamUser = user;
    gameVC.steamPass = pass;
    gameVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:gameVC animated:YES completion:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

@end
