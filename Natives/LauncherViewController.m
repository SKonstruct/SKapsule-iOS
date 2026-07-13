#import "LauncherViewController.h"
#import <CommonCrypto/CommonDigest.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <zlib.h>
#import "GameViewController.h"
#import "SKInstaller.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, SKLoginMode) {
    SKLoginModeWeb,
    SKLoginModeSteam,
};

@interface LauncherViewController ()
@property (nonatomic, strong) UISegmentedControl *modeSegmentedControl;
@property (nonatomic, strong) UIButton *btnLaunch;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *setupStatus;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL runtimeReady;

// Sidebar & Dimming Overlay
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *sidebarView;
@property (nonatomic, strong) NSLayoutConstraint *sidebarTrailingConstraint;
@property (nonatomic, strong) UIButton *btnLogout;
@property (nonatomic, strong) UIView *logoutDivider;
@property (nonatomic, strong) UISwitch *avoidEdgesSwitch;
@property (nonatomic, assign) BOOL sidebarOpen;
@end

@implementation LauncherViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    UIColor *themeColor = [UIColor colorWithRed:171.0 / 255.0
                                          green:74.0 / 255.0
                                           blue:129.0 / 255.0
                                          alpha:1.0];  // #ab4a81

    // 1. Top Options/Gear Button
    UIButton *btnOptions = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [btnOptions setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    } else {
        [btnOptions setTitle:@"⚙" forState:UIControlStateNormal];
        btnOptions.titleLabel.font = [UIFont systemFontOfSize:24];
    }
    btnOptions.tintColor = UIColor.whiteColor;
    btnOptions.translatesAutoresizingMaskIntoConstraints = NO;
    [btnOptions addTarget:self action:@selector(toggleSidebar) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnOptions];

    // 2. Title & Subtitle Container
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont boldSystemFontOfSize:32];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    // Set title with version name
    NSString *verStr = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    titleLabel.text = [NSString stringWithFormat:@"SKapsule v%@", verStr];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = @"Spiral Knights for iOS";
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.subtitleLabel];

    // 3. Segmented Control
    self.modeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Web", @"Steam"]];
    self.modeSegmentedControl.selectedSegmentIndex = 0;
    self.modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;

    if (@available(iOS 13.0, *)) {
        self.modeSegmentedControl.selectedSegmentTintColor = themeColor;
    } else {
        self.modeSegmentedControl.tintColor = themeColor;
    }

    // Style text of segmented control
    [self.modeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.6 alpha:1.0],
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightRegular]
    }
                                             forState:UIControlStateNormal];
    [self.modeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightBold]
    }
                                             forState:UIControlStateSelected];

    [self.modeSegmentedControl addTarget:self
                                  action:@selector(onSegmentChanged:)
                        forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeSegmentedControl];

    // Restore persistent segmented selection
    NSString *savedMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"login_mode"] ?: @"Web";
    if ([savedMode isEqualToString:@"Steam"]) {
        self.modeSegmentedControl.selectedSegmentIndex = 1;
    } else {
        self.modeSegmentedControl.selectedSegmentIndex = 0;
    }
    [self updateSegmentedTextStyles];

    // 4. Launch Button
    self.btnLaunch = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.btnLaunch setTitle:@" Launch" forState:UIControlStateNormal];
    self.btnLaunch.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.btnLaunch setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.btnLaunch.backgroundColor = themeColor;
    self.btnLaunch.layer.cornerRadius = 26;
    self.btnLaunch.clipsToBounds = YES;
    self.btnLaunch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.btnLaunch addTarget:self action:@selector(onLaunchPressed) forControlEvents:UIControlEventTouchUpInside];

    if (@available(iOS 13.0, *)) {
        [self.btnLaunch setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        self.btnLaunch.tintColor = UIColor.whiteColor;
    }
    [self.view addSubview:self.btnLaunch];

    // 5. Setup Status & Spinner
    self.setupStatus = [[UILabel alloc] init];
    self.setupStatus.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.setupStatus.font = [UIFont systemFontOfSize:13];
    self.setupStatus.textAlignment = NSTextAlignmentCenter;
    self.setupStatus.numberOfLines = 0;
    self.setupStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.setupStatus];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    if (@available(iOS 13.0, *)) {
        self.spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleMedium;
    }
    self.spinner.color = UIColor.whiteColor;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    // 6. Setup Dimming Overlay
    self.dimmingView = [[UIView alloc] init];
    self.dimmingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    self.dimmingView.alpha = 0;
    self.dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingView.userInteractionEnabled = NO;
    [self.view addSubview:self.dimmingView];

    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                 action:@selector(toggleSidebar)];
    [self.dimmingView addGestureRecognizer:tapDismiss];

    // 7. Setup Sidebar Container
    self.sidebarView = [[UIView alloc] init];
    self.sidebarView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.sidebarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sidebarView];

    // Scrollable Stack for Sidebar
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarView addSubview:scrollView];

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 4;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.distribution = UIStackViewDistributionFill;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stackView];

    // Sidebar Title
    UILabel *settingsTitle = [[UILabel alloc] init];
    settingsTitle.text = @"Settings";
    settingsTitle.textColor = UIColor.whiteColor;
    settingsTitle.font = [UIFont boldSystemFontOfSize:20];
    [stackView addArrangedSubview:settingsTitle];

    // Add spacer under title
    UIView *titleSpacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 16)];
    [stackView addArrangedSubview:titleSpacer];

    // Sidebar Buttons Helper
    UIButton *btnShare = [self createSidebarButtonWithTitle:@"Share Logs"
                                                   iconName:@"square.and.arrow.up"
                                                     action:@selector(onShareLogs)];
    [stackView addArrangedSubview:btnShare];

    UIButton *btnSave = [self createSidebarButtonWithTitle:@"Save Logs"
                                                  iconName:@"square.and.arrow.down"
                                                    action:@selector(onSaveLogs)];
    [stackView addArrangedSubview:btnSave];

    UIButton *btnDownloadMods = [self createSidebarButtonWithTitle:@"Download Modpack"
                                                          iconName:@"icloud.and.arrow.down"
                                                            action:@selector(onDownloadMods)];
    [stackView addArrangedSubview:btnDownloadMods];

    UIButton *btnApplyMods = [self createSidebarButtonWithTitle:@"Apply Mods"
                                                       iconName:@"hammer"
                                                         action:@selector(onApplyMods)];
    [stackView addArrangedSubview:btnApplyMods];

    UIButton *btnOpenFolder = [self createSidebarButtonWithTitle:@"Open Folder"
                                                        iconName:@"folder"
                                                          action:@selector(onOpenFolder)];
    [stackView addArrangedSubview:btnOpenFolder];

    UIButton *btnGitHub = [self createSidebarButtonWithTitle:@"GitHub" iconName:@"link" action:@selector(onGitHub)];
    [stackView addArrangedSubview:btnGitHub];

    UIButton *btnDiscord = [self createSidebarButtonWithTitle:@"Discord"
                                                     iconName:@"bubble.left.and.bubble.right"
                                                       action:@selector(onDiscord)];
    [stackView addArrangedSubview:btnDiscord];

    // Logout divider
    self.logoutDivider = [[UIView alloc] init];
    self.logoutDivider.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self.logoutDivider.heightAnchor constraintEqualToConstant:1].active = YES;
    [stackView addArrangedSubview:self.logoutDivider];

    // Logout button
    self.btnLogout = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.btnLogout setTitle:@"  Logout" forState:UIControlStateNormal];
    [self.btnLogout setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]
                         forState:UIControlStateNormal];
    self.btnLogout.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.btnLogout.titleLabel.font = [UIFont systemFontOfSize:16];
    self.btnLogout.contentEdgeInsets = UIEdgeInsetsMake(12, 8, 12, 8);
    [self.btnLogout addTarget:self action:@selector(onLogout) forControlEvents:UIControlEventTouchUpInside];
    if (@available(iOS 13.0, *)) {
        [self.btnLogout setImage:[UIImage systemImageNamed:@"rectangle.portrait.and.arrow.right"]
                        forState:UIControlStateNormal];
        self.btnLogout.tintColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
        self.btnLogout.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
        self.btnLogout.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    }
    [stackView addArrangedSubview:self.btnLogout];

    // General divider
    UIView *generalDivider = [[UIView alloc] init];
    generalDivider.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [generalDivider.heightAnchor constraintEqualToConstant:1].active = YES;
    [stackView addArrangedSubview:generalDivider];

    // Avoid screen edges row
    UIView *avoidRow = [[UIView alloc] init];
    avoidRow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *avoidLabel = [[UILabel alloc] init];
    avoidLabel.text = @"Avoid screen edges";
    avoidLabel.textColor = UIColor.whiteColor;
    avoidLabel.font = [UIFont systemFontOfSize:14];
    avoidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [avoidRow addSubview:avoidLabel];

    self.avoidEdgesSwitch = [[UISwitch alloc] init];
    self.avoidEdgesSwitch.onTintColor = themeColor;
    self.avoidEdgesSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.avoidEdgesSwitch addTarget:self
                              action:@selector(onAvoidEdgesChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [avoidRow addSubview:self.avoidEdgesSwitch];

    // Restore avoid edges switch
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"avoid_screen_edges"];
    if (val) {
        self.avoidEdgesSwitch.on = [val boolValue];
    } else {
        self.avoidEdgesSwitch.on = NO;
    }

    [stackView addArrangedSubview:avoidRow];

    // Layout Constraints
    self.sidebarTrailingConstraint = [self.sidebarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                                                     constant:280];

    [NSLayoutConstraint activateConstraints:@[
        // Options Button
        [btnOptions.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [btnOptions.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [btnOptions.widthAnchor constraintEqualToConstant:44], [btnOptions.heightAnchor constraintEqualToConstant:44],

        // Title & Subtitle Layout
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:self.subtitleLabel.topAnchor constant:-4],

        [self.subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.modeSegmentedControl.topAnchor constant:-30],

        // Segmented Control Layout
        [self.modeSegmentedControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.modeSegmentedControl.bottomAnchor constraintEqualToAnchor:self.btnLaunch.topAnchor constant:-20],
        [self.modeSegmentedControl.widthAnchor constraintEqualToConstant:240],
        [self.modeSegmentedControl.heightAnchor constraintEqualToConstant:48],

        // Launch Button Layout
        [self.btnLaunch.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.btnLaunch.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:30],
        [self.btnLaunch.widthAnchor constraintEqualToConstant:240],
        [self.btnLaunch.heightAnchor constraintEqualToConstant:52],

        // Setup status / spinner
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:self.btnLaunch.bottomAnchor constant:24],

        [self.setupStatus.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.setupStatus.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:8],
        [self.setupStatus.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.setupStatus.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],

        // Dimming overlay constraints
        [self.dimmingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.dimmingView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.dimmingView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.dimmingView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Sidebar constraints
        self.sidebarTrailingConstraint, [self.sidebarView.widthAnchor constraintEqualToConstant:280],
        [self.sidebarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.sidebarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Scroll view inside sidebar
        [scrollView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor constant:16],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor constant:-16],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],

        // Stack view constraints inside scroll view
        [stackView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [stackView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [stackView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],

        // Avoid Edges row contents
        [avoidLabel.leadingAnchor constraintEqualToAnchor:avoidRow.leadingAnchor constant:8],
        [avoidLabel.centerYAnchor constraintEqualToAnchor:avoidRow.centerYAnchor],
        [self.avoidEdgesSwitch.trailingAnchor constraintEqualToAnchor:avoidRow.trailingAnchor constant:-8],
        [self.avoidEdgesSwitch.centerYAnchor constraintEqualToAnchor:avoidRow.centerYAnchor],
        [avoidRow.heightAnchor constraintEqualToConstant:50]
    ]];

    [self setButtonsEnabled:NO];
    [self fetchPlayerCount];
    [self ensureRuntime];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateLogoutButtonVisibility];
}

- (UIButton *)createSidebarButtonWithTitle:(NSString *)title iconName:(NSString *)iconName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:[NSString stringWithFormat:@"  %@", title] forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    btn.contentEdgeInsets = UIEdgeInsetsMake(12, 8, 12, 8);
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    if (@available(iOS 13.0, *)) {
        [btn setImage:[UIImage systemImageNamed:iconName] forState:UIControlStateNormal];
        btn.tintColor = UIColor.whiteColor;
        btn.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
        btn.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    }
    return btn;
}

- (void)toggleSidebar {
    self.sidebarOpen = !self.sidebarOpen;
    self.sidebarTrailingConstraint.constant = self.sidebarOpen ? 0 : 280;
    self.dimmingView.userInteractionEnabled = self.sidebarOpen;

    [UIView animateWithDuration:0.3
                     animations:^{
                       self.dimmingView.alpha = self.sidebarOpen ? 1.0 : 0.0;
                       [self.view layoutIfNeeded];
                     }];
}

- (void)onSegmentChanged:(UISegmentedControl *)sender {
    [self updateSegmentedTextStyles];
    NSString *mode = (sender.selectedSegmentIndex == 1) ? @"Steam" : @"Web";
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:@"login_mode"];
}

- (void)updateSegmentedTextStyles {
    // Bold / change font for selected vs unselected segments programmatically
    for (int i = 0; i < self.modeSegmentedControl.numberOfSegments; i++) {
        // UISegmentedControl handles selected text attributes globally on iOS 13+
        // and we already set titleTextAttributes for Normal and Selected states in
        // viewDidLoad.
    }
}

- (void)onAvoidEdgesChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"avoid_screen_edges"];
}

- (void)onShareLogs {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) {
        [self showAlertWithTitle:@"No Logs" message:@"SKapsule home directory is not set."];
        return;
    }
    NSString *home = [NSString stringWithUTF8String:homeEnv];
    NSString *logPath = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSMutableArray *items = [NSMutableArray array];
    if ([fileManager fileExistsAtPath:logPath]) {
        [items addObject:[NSURL fileURLWithPath:logPath]];
    }

    NSString *oldLogPath = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    if ([fileManager fileExistsAtPath:oldLogPath]) {
        [items addObject:[NSURL fileURLWithPath:oldLogPath]];
    }

    if (items.count > 0) {
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:items
                                                                                 applicationActivities:nil];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            activityVC.popoverPresentationController.sourceView = self.view;
            activityVC.popoverPresentationController.sourceRect =
                CGRectMake(self.view.bounds.size.width - 50, 50, 1, 1);
        }
        [self presentViewController:activityVC animated:YES completion:nil];
    } else {
        [self showAlertWithTitle:@"No Logs" message:@"No log files found yet. Launch the game first."];
    }
}

- (void)onSaveLogs {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    if (!homeEnv) {
        [self showAlertWithTitle:@"No Logs" message:@"SKapsule home directory is not set."];
        return;
    }
    NSString *home = [NSString stringWithUTF8String:homeEnv];
    NSString *logPath = [home stringByAppendingPathComponent:@"latestlog.txt"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        NSURL *logURL = [NSURL fileURLWithPath:logPath];
        if (@available(iOS 14.0, *)) {
            UIDocumentPickerViewController *picker =
                [[UIDocumentPickerViewController alloc] initForExportingURLs:@[logURL] asCopy:YES];
            [self presentViewController:picker animated:YES completion:nil];
        } else {
            UIDocumentPickerViewController *picker =
                [[UIDocumentPickerViewController alloc] initWithURL:logURL inMode:UIDocumentPickerModeExportToService];
            [self presentViewController:picker animated:YES completion:nil];
        }
    } else {
        [self showAlertWithTitle:@"No Logs" message:@"No log file found yet. Launch the game first."];
    }
}

- (void)openURLWithSafariFallback:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (!success) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                     SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
                                     [self presentViewController:safari animated:YES completion:nil];
                                   });
                               }
                             }];
}

- (void)onOpenFolder {
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docsDir) {
        [self showAlertWithTitle:@"Open Folder" message:@"Could not locate Documents directory."];
        return;
    }
    NSURL *docsURL = [NSURL fileURLWithPath:docsDir];
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.folder"]]];
        picker.directoryURL = docsURL;
        picker.delegate = (id)self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initWithURL:docsURL inMode:UIDocumentPickerModeOpen];
        picker.delegate = (id)self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)onGitHub {
    [self openURLWithSafariFallback:@"https://github.com/SKonstruct/SKapsule-iOS"];
}

- (void)onDiscord {
    [self openURLWithSafariFallback:@"https://dankware.alwaysdata.net/discord"];
}

- (void)onLogout {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Logout"
                                            message:@"Sign out of Steam? Your saved session will be "
                                                    @"cleared."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Sign out"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                              NSString *cred = [SKInstaller credFilePath];
                                              if ([NSFileManager.defaultManager fileExistsAtPath:cred]) {
                                                  [NSFileManager.defaultManager removeItemAtPath:cred error:nil];
                                              }
                                              [self updateLogoutButtonVisibility];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateLogoutButtonVisibility {
    BOOL hasCreds = [NSFileManager.defaultManager fileExistsAtPath:[SKInstaller credFilePath]];
    self.btnLogout.hidden = !hasCreds;
    self.logoutDivider.hidden = !hasCreds;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)onLaunchPressed {
    SKLoginMode mode = (self.modeSegmentedControl.selectedSegmentIndex == 1) ? SKLoginModeSteam : SKLoginModeWeb;
    if (mode == SKLoginModeSteam) {
        [self onPlaySteam];
    } else {
        [self onPlayWeb];
    }
}

- (void)setButtonsEnabled:(BOOL)enabled {
    self.btnLaunch.enabled = enabled;
    self.btnLaunch.alpha = enabled ? 1.0 : 0.4;
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
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Steam Login"
                                            message:@"Enter your Steam credentials. They are passed "
                                                    @"directly to the game and never stored by SKapsule."
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

    [alert
        addAction:[UIAlertAction
                      actionWithTitle:@"Login"
                                style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction *action) {
                                NSString *user = alert.textFields[0].text ?: @"";
                                NSString *pass = alert.textFields[1].text ?: @"";
                                [self
                                    launchGameWithMode:SKLoginModeSteam
                                             steamUser:[user
                                                           stringByTrimmingCharactersInSet:NSCharacterSet
                                                                                               .whitespaceCharacterSet]
                                             steamPass:pass];
                              }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)launchGameWithMode:(SKLoginMode)mode steamUser:(NSString *)user steamPass:(NSString *)pass {
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

#pragma pack(push, 1)
typedef struct {
    uint32_t signature;  // 0x04034b50
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_time;
    uint16_t last_mod_date;
    uint32_t crc32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t filename_length;
    uint16_t extra_field_length;
} iOSLocalFileHeader;

typedef struct {
    uint32_t signature;  // 0x02014b50
    uint16_t version_made;
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_time;
    uint16_t last_mod_date;
    uint32_t crc32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t filename_length;
    uint16_t extra_field_length;
    uint16_t comment_length;
    uint16_t disk_start;
    uint16_t internal_attrs;
    uint32_t external_attrs;
    uint32_t local_header_offset;
} iOSCentralHeader;

typedef struct {
    uint32_t signature;  // 0x06054b50
    uint16_t disk_number;
    uint16_t disk_with_cd;
    uint16_t disk_entries;
    uint16_t total_entries;
    uint32_t cd_size;
    uint32_t cd_offset;
    uint16_t comment_length;
} iOSEOCD;
#pragma pack(pop)

static BOOL extractZipFile(NSString *zipPath, NSString *targetDir, BOOL checkProtected,
                           NSSet<NSString *> *protectedFiles) {
    FILE *f = fopen([zipPath UTF8String], "rb");
    if (!f)
        return NO;

    iOSLocalFileHeader header;
    while (fread(&header, 1, sizeof(iOSLocalFileHeader), f) == sizeof(iOSLocalFileHeader)) {
        if (header.signature != 0x04034b50) {
            break;
        }

        char *filename = malloc(header.filename_length + 1);
        if (fread(filename, 1, header.filename_length, f) != header.filename_length) {
            free(filename);
            fclose(f);
            return NO;
        }
        filename[header.filename_length] = '\0';

        fseek(f, header.extra_field_length, SEEK_CUR);

        NSString *entryName = [NSString stringWithUTF8String:filename];
        free(filename);

        if (!entryName) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        if ([entryName hasSuffix:@"/"] || [entryName isEqualToString:@"mod.json"] ||
            [entryName hasSuffix:@"/mod.json"] || [entryName isEqualToString:@"mod.png"] ||
            [entryName hasSuffix:@"/mod.png"]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        if (checkProtected && [protectedFiles containsObject:entryName]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        NSString *destPath = [targetDir stringByAppendingPathComponent:entryName];
        [[NSFileManager defaultManager] createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        uint8_t *compData = malloc(header.compressed_size);
        if (fread(compData, 1, header.compressed_size, f) != header.compressed_size) {
            free(compData);
            fclose(f);
            return NO;
        }

        if (header.compression_method == 0) {
            NSData *data = [NSData dataWithBytesNoCopy:compData length:header.compressed_size freeWhenDone:YES];
            [data writeToFile:destPath atomically:YES];
        } else if (header.compression_method == 8) {
            uint8_t *uncompData = malloc(header.uncompressed_size);

            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            strm.next_in = (Bytef *)compData;
            strm.avail_in = header.compressed_size;
            strm.next_out = (Bytef *)uncompData;
            strm.avail_out = header.uncompressed_size;

            int ret = inflateInit2(&strm, -15);
            if (ret == Z_OK) {
                ret = inflate(&strm, Z_FINISH);
                inflateEnd(&strm);
            }

            free(compData);

            if (ret == Z_STREAM_END || ret == Z_OK) {
                NSData *data = [NSData dataWithBytesNoCopy:uncompData length:header.uncompressed_size freeWhenDone:YES];
                [data writeToFile:destPath atomically:YES];
            } else {
                free(uncompData);
                fclose(f);
                return NO;
            }
        } else {
            free(compData);
            fclose(f);
            return NO;
        }
    }

    fclose(f);
    return YES;
}

static BOOL extractJarWithoutOverwrite(NSString *jarPath, NSString *targetDir) {
    FILE *f = fopen([jarPath UTF8String], "rb");
    if (!f)
        return NO;

    iOSLocalFileHeader header;
    while (fread(&header, 1, sizeof(iOSLocalFileHeader), f) == sizeof(iOSLocalFileHeader)) {
        if (header.signature != 0x04034b50) {
            break;
        }

        char *filename = malloc(header.filename_length + 1);
        if (fread(filename, 1, header.filename_length, f) != header.filename_length) {
            free(filename);
            fclose(f);
            return NO;
        }
        filename[header.filename_length] = '\0';

        fseek(f, header.extra_field_length, SEEK_CUR);

        NSString *entryName = [NSString stringWithUTF8String:filename];
        free(filename);

        if (!entryName || [entryName hasSuffix:@"/"]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        NSString *destPath = [targetDir stringByAppendingPathComponent:entryName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        [[NSFileManager defaultManager] createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        uint8_t *compData = malloc(header.compressed_size);
        if (fread(compData, 1, header.compressed_size, f) != header.compressed_size) {
            free(compData);
            fclose(f);
            return NO;
        }

        if (header.compression_method == 0) {
            NSData *data = [NSData dataWithBytesNoCopy:compData length:header.compressed_size freeWhenDone:YES];
            [data writeToFile:destPath atomically:YES];
        } else if (header.compression_method == 8) {
            uint8_t *uncompData = malloc(header.uncompressed_size);
            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            strm.next_in = (Bytef *)compData;
            strm.avail_in = header.compressed_size;
            strm.next_out = (Bytef *)uncompData;
            strm.avail_out = header.uncompressed_size;

            int ret = inflateInit2(&strm, -15);
            if (ret == Z_OK) {
                ret = inflate(&strm, Z_FINISH);
                inflateEnd(&strm);
            }
            free(compData);

            if (ret == Z_STREAM_END || ret == Z_OK) {
                NSData *data = [NSData dataWithBytesNoCopy:uncompData length:header.uncompressed_size freeWhenDone:YES];
                [data writeToFile:destPath atomically:YES];
            } else {
                free(uncompData);
                fclose(f);
                return NO;
            }
        } else {
            free(compData);
            fclose(f);
            return NO;
        }
    }

    fclose(f);
    return YES;
}

static void collectFiles(NSString *baseDir, NSString *currentDir, NSMutableArray *filePaths) {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:currentDir error:nil];
    for (NSString *file in files) {
        NSString *fullPath = [currentDir stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) {
                collectFiles(baseDir, fullPath, filePaths);
            } else {
                [filePaths addObject:fullPath];
            }
        }
    }
}

static BOOL createZipFile(NSString *sourceDir, NSString *zipPath) {
    NSMutableArray *files = [NSMutableArray array];
    collectFiles(sourceDir, sourceDir, files);

    FILE *f = fopen([zipPath UTF8String], "wb");
    if (!f)
        return NO;

    NSMutableArray *centralHeaders = [NSMutableArray array];
    uint32_t currentOffset = 0;

    for (NSString *filePath in files) {
        NSString *relPath = [filePath substringFromIndex:sourceDir.length + 1];
        if ([relPath isEqualToString:@"mod.json"] || [relPath isEqualToString:@"mod.png"]) {
            continue;
        }

        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data)
            continue;

        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, [data bytes], (uInt)[data length]);

        NSMutableData *compressed = [NSMutableData data];
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        int ret = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
        if (ret != Z_OK) {
            fclose(f);
            return NO;
        }

        uint8_t outBuffer[8192];
        strm.next_in = (Bytef *)[data bytes];
        strm.avail_in = (uInt)[data length];

        do {
            strm.next_out = outBuffer;
            strm.avail_out = sizeof(outBuffer);
            ret = deflate(&strm, Z_FINISH);
            NSInteger compressedBytes = sizeof(outBuffer) - strm.avail_out;
            [compressed appendBytes:outBuffer length:compressedBytes];
        } while (strm.avail_out == 0);

        deflateEnd(&strm);

        NSData *nameData = [relPath dataUsingEncoding:NSUTF8StringEncoding];

        iOSLocalFileHeader localHeader;
        localHeader.signature = 0x04034b50;
        localHeader.version_needed = 20;
        localHeader.flags = 0;
        localHeader.compression_method = 8;
        localHeader.last_mod_time = 0;
        localHeader.last_mod_date = 0;
        localHeader.crc32 = (uint32_t)crc;
        localHeader.compressed_size = (uint32_t)[compressed length];
        localHeader.uncompressed_size = (uint32_t)[data length];
        localHeader.filename_length = (uint16_t)[nameData length];
        localHeader.extra_field_length = 0;

        fwrite(&localHeader, 1, sizeof(iOSLocalFileHeader), f);
        fwrite([nameData bytes], 1, [nameData length], f);
        fwrite([compressed bytes], 1, [compressed length], f);

        NSMutableData *cdRecord = [NSMutableData data];
        iOSCentralHeader cdHeader;
        cdHeader.signature = 0x02014b50;
        cdHeader.version_made = 20;
        cdHeader.version_needed = 20;
        cdHeader.flags = 0;
        cdHeader.compression_method = 8;
        cdHeader.last_mod_time = 0;
        cdHeader.last_mod_date = 0;
        cdHeader.crc32 = (uint32_t)crc;
        cdHeader.compressed_size = (uint32_t)[compressed length];
        cdHeader.uncompressed_size = (uint32_t)[data length];
        cdHeader.filename_length = (uint16_t)[nameData length];
        cdHeader.extra_field_length = 0;
        cdHeader.comment_length = 0;
        cdHeader.disk_start = 0;
        cdHeader.internal_attrs = 0;
        cdHeader.external_attrs = 0;
        cdHeader.local_header_offset = currentOffset;

        [cdRecord appendBytes:&cdHeader length:sizeof(iOSCentralHeader)];
        [cdRecord appendData:nameData];
        [centralHeaders addObject:cdRecord];

        currentOffset += sizeof(iOSLocalFileHeader) + [nameData length] + [compressed length];
    }

    uint32_t cdOffset = currentOffset;
    uint32_t cdSize = 0;

    for (NSData *cdRecord in centralHeaders) {
        fwrite([cdRecord bytes], 1, [cdRecord length], f);
        cdSize += [cdRecord length];
    }

    iOSEOCD eocd;
    eocd.signature = 0x06054b50;
    eocd.disk_number = 0;
    eocd.disk_with_cd = 0;
    eocd.disk_entries = (uint16_t)[centralHeaders count];
    eocd.total_entries = (uint16_t)[centralHeaders count];
    eocd.cd_size = cdSize;
    eocd.cd_offset = cdOffset;
    eocd.comment_length = 0;

    fwrite(&eocd, 1, sizeof(iOSEOCD), f);

    fclose(f);
    return YES;
}

static NSString *calculateGitBlobShaOfFile(NSString *filePath) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:filePath];
    if (!stream)
        return nil;
    [stream open];

    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
    CC_SHA1_CTX sha1;
    CC_SHA1_Init(&sha1);

    NSString *header = [NSString stringWithFormat:@"blob %llu", fileSize];
    const char *headerStr = [header UTF8String];
    NSMutableData *headerData = [NSMutableData dataWithBytes:headerStr
                                                      length:[header lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    char nullChar = '\0';
    [headerData appendBytes:&nullChar length:1];

    CC_SHA1_Update(&sha1, [headerData bytes], (CC_LONG)[headerData length]);

    uint8_t buffer[8192];
    while ([stream hasBytesAvailable]) {
        NSInteger bytesRead = [stream read:buffer maxLength:sizeof(buffer)];
        if (bytesRead > 0) {
            CC_SHA1_Update(&sha1, buffer, (CC_LONG)bytesRead);
        } else if (bytesRead < 0) {
            [stream close];
            return nil;
        }
    }
    [stream close];

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &sha1);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

- (void)fetchPlayerCount {
    NSURL *url = [NSURL URLWithString:@"https://api.steampowered.com/ISteamUserStats/"
                                      @"GetNumberOfCurrentPlayers/v1/?appid=99900"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
          dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
          if (error || !data)
              return;
          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
          if (!json)
              return;
          NSDictionary *resp = json[@"response"];
          if (![resp isKindOfClass:[NSDictionary class]])
              return;
          id playerCountObj = resp[@"player_count"];
          if (!playerCountObj)
              return;
          NSInteger steam = [playerCountObj integerValue];
          if (steam <= 0)
              return;
          NSInteger total = (NSInteger)roundf(steam * 1.4f);
          dispatch_async(dispatch_get_main_queue(), ^{
            self.subtitleLabel.text =
                [NSString stringWithFormat:@"Fight alongside ~%ld other Spiral Knights!", (long)total];
          });
        }];
    [task resume];
}

- (void)onDownloadMods {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Downloading Mods"
                                                                   message:@"Connecting to GitHub…"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    progressView.progressTintColor = [UIColor colorWithRed:171.0 / 255.0
                                                     green:74.0 / 255.0
                                                      blue:129.0 / 255.0
                                                     alpha:1.0];
    [alert.view addSubview:progressView];

    [NSLayoutConstraint activateConstraints:@[
        [progressView.leadingAnchor constraintEqualToAnchor:alert.view.leadingAnchor constant:20],
        [progressView.trailingAnchor constraintEqualToAnchor:alert.view.trailingAnchor constant:-20],
        [progressView.bottomAnchor constraintEqualToAnchor:alert.view.bottomAnchor constant:-20]
    ]];

    [alert.view.heightAnchor constraintEqualToConstant:120].active = YES;

    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      const char *homeEnv = getenv("SKAPSULE_HOME");
      if (!homeEnv) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Download Failed"
                                                         message:@"SKapsule home "
                                                                 @"directory is "
                                                                 @"not set."];
                                      }];
          });
          return;
      }

      NSString *home = [NSString stringWithUTF8String:homeEnv];
      NSString *modsPath = [home stringByAppendingPathComponent:@"sk/mods"];
      [[NSFileManager defaultManager] createDirectoryAtPath:modsPath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];

      NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/SirDank/"
                                        @"Spiral-Knights-Modpack/contents/mods"];
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
      [request setValue:@"SKapsule-Launcher-iOS" forHTTPHeaderField:@"User-Agent"];

      NSError *error = nil;
      NSHTTPURLResponse *response = nil;
      NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

      if (error || !data || response.statusCode != 200) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Download Failed"
                                                         message:@"Failed to connect "
                                                                 @"to GitHub. Check "
                                                                 @"your internet "
                                                                 @"connection."];
                                      }];
          });
          return;
      }

      NSArray *remoteFiles = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (![remoteFiles isKindOfClass:[NSArray class]] || remoteFiles.count == 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Download Failed"
                                                         message:@"No mods found in "
                                                                 @"the repository."];
                                      }];
          });
          return;
      }

      NSMutableArray *modsToSync = [NSMutableArray array];
      NSMutableSet *remoteNames = [NSMutableSet set];

      for (NSDictionary *file in remoteFiles) {
          if ([file[@"type"] isEqualToString:@"file"]) {
              [modsToSync addObject:file];
              [remoteNames addObject:file[@"name"]];
          }
      }

      NSFileManager *fm = [NSFileManager defaultManager];
      NSArray *localFiles = [fm contentsOfDirectoryAtPath:modsPath error:nil];
      NSInteger deleted = 0;
      for (NSString *localFile in localFiles) {
          if (![remoteNames containsObject:localFile]) {
              [fm removeItemAtPath:[modsPath stringByAppendingPathComponent:localFile] error:nil];
              deleted++;
          }
      }

      NSInteger downloaded = 0;
      NSInteger skipped = 0;

      for (NSInteger i = 0; i < modsToSync.count; i++) {
          NSDictionary *mod = modsToSync[i];
          NSString *name = mod[@"name"];
          NSString *downloadUrlString = mod[@"download_url"];
          NSString *remoteSha = mod[@"sha"];

          NSString *destPath = [modsPath stringByAppendingPathComponent:name];

          dispatch_async(dispatch_get_main_queue(), ^{
            alert.message =
                [NSString stringWithFormat:@"Checking (%ld/%ld): %@", (long)(i + 1), (long)modsToSync.count, name];
            progressView.progress = (float)(i) / modsToSync.count;
          });

          if ([fm fileExistsAtPath:destPath] && remoteSha.length > 0) {
              NSString *localSha = calculateGitBlobShaOfFile(destPath);
              if ([localSha isEqualToString:remoteSha]) {
                  skipped++;
                  continue;
              }
          }

          dispatch_async(dispatch_get_main_queue(), ^{
            alert.message = [NSString stringWithFormat:@"[%ld/%ld]: %@", (long)(i + 1), (long)modsToSync.count, name];
          });

          NSData *modData = [NSData dataWithContentsOfURL:[NSURL URLWithString:downloadUrlString]];
          if (modData) {
              [modData writeToFile:destPath atomically:YES];
              downloaded++;
          }
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES
                                  completion:^{
                                    NSString *stats =
                                        [NSString stringWithFormat:@"Sync complete!\nDownloaded: "
                                                                   @"%ld\nSkipped: %ld\nDeleted: %ld",
                                                                   (long)downloaded, (long)skipped, (long)deleted];
                                    [self showAlertWithTitle:@"Download Modpack" message:stats];
                                  }];
      });
    });
}

- (void)onApplyMods {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Applying Mods"
                                                                   message:@"Preparing to apply…"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    progressView.progressTintColor = [UIColor colorWithRed:171.0 / 255.0
                                                     green:74.0 / 255.0
                                                      blue:129.0 / 255.0
                                                     alpha:1.0];
    [alert.view addSubview:progressView];

    [NSLayoutConstraint activateConstraints:@[
        [progressView.leadingAnchor constraintEqualToAnchor:alert.view.leadingAnchor constant:20],
        [progressView.trailingAnchor constraintEqualToAnchor:alert.view.trailingAnchor constant:-20],
        [progressView.bottomAnchor constraintEqualToAnchor:alert.view.bottomAnchor constant:-20]
    ]];

    [alert.view.heightAnchor constraintEqualToConstant:120].active = YES;

    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      const char *homeEnv = getenv("SKAPSULE_HOME");
      if (!homeEnv) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Apply Failed"
                                                         message:@"SKapsule home "
                                                                 @"directory is "
                                                                 @"not set."];
                                      }];
          });
          return;
      }

      NSString *home = [NSString stringWithUTF8String:homeEnv];
      NSString *skPath = [home stringByAppendingPathComponent:@"sk"];
      NSString *rsrcDir = [skPath stringByAppendingPathComponent:@"rsrc"];
      NSFileManager *fm = [NSFileManager defaultManager];

      if (![fm fileExistsAtPath:rsrcDir]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Apply Failed"
                                                         message:@"Game is not "
                                                                 @"installed yet. "
                                                                 @"Launch the game "
                                                                 @"first to install "
                                                                 @"game files."];
                                      }];
          });
          return;
      }

      NSString *modsPath = [home stringByAppendingPathComponent:@"sk/mods"];
      NSArray *modFiles = [fm contentsOfDirectoryAtPath:modsPath error:nil];
      NSMutableArray *zipsOrModpacks = [NSMutableArray array];
      for (NSString *file in modFiles) {
          if ([file hasSuffix:@".zip"] || [file hasSuffix:@".modpack"]) {
              [zipsOrModpacks addObject:file];
          }
      }

      if (zipsOrModpacks.count == 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        [self showAlertWithTitle:@"Apply Failed"
                                                         message:@"No mods found in "
                                                                 @"mods folder. "
                                                                 @"Download mods "
                                                                 @"first."];
                                      }];
          });
          return;
      }

      NSSet *protectedFiles = [NSSet
          setWithObjects:@"config/accessory.dat", @"config/accessory.xml", @"config/actor.dat", @"config/actor.xml",
                         @"config/area.dat", @"config/area.xml", @"config/attack.dat", @"config/attack.xml",
                         @"config/battle_sprite.dat", @"config/battle_sprite.xml", @"config/catalog.dat",
                         @"config/catalog.xml", @"config/conversation.dat", @"config/conversation.xml",
                         @"config/cursor.dat", @"config/cursor.xml", @"config/depot_catalog.dat",
                         @"config/depot_catalog.xml", @"config/depth_scale.dat", @"config/depth_scale.xml",
                         @"config/description.dat", @"config/description.xml", @"config/effect.dat",
                         @"config/effect.xml", @"config/emote.dat", @"config/emote.xml", @"config/event.dat",
                         @"config/event.xml", @"config/fire_action.dat", @"config/fire_action.xml", @"config/font.dat",
                         @"config/font.xml", @"config/forge_property.dat", @"config/forge_property.xml",
                         @"config/gift.dat", @"config/gift.xml", @"config/ground.dat", @"config/ground.xml",
                         @"config/harness.dat", @"config/harness.xml", @"config/interact.dat", @"config/interact.xml",
                         @"config/interface_script.dat", @"config/interface_script.xml", @"config/item.dat",
                         @"config/item.xml", @"config/item_depth_weight.dat", @"config/item_depth_weight.xml",
                         @"config/item_property.dat", @"config/item_property.xml", @"config/level_table.dat",
                         @"config/level_table.xml", @"config/material.dat", @"config/material.xml",
                         @"config/mission.dat", @"config/mission.xml", @"config/mission_group.dat",
                         @"config/mission_group.xml", @"config/mission_property.dat", @"config/mission_property.xml",
                         @"config/parameterized_handler.dat", @"config/parameterized_handler.xml", @"config/path.dat",
                         @"config/path.xml", @"config/placeable.dat", @"config/placeable.xml", @"config/recipe.dat",
                         @"config/recipe.xml", @"config/recipe_property.dat", @"config/recipe_property.xml",
                         @"config/render_effect.dat", @"config/render_effect.xml", @"config/render_queue.dat",
                         @"config/render_queue.xml", @"config/render_scheme.dat", @"config/render_scheme.xml",
                         @"config/scene_global.dat", @"config/scene_global.xml", @"config/shader.dat",
                         @"config/shader.xml", @"config/sounder.dat", @"config/sounder.xml",
                         @"config/status_condition.dat", @"config/status_condition.xml", @"config/status_effect.dat",
                         @"config/status_effect.xml", @"config/tileset.dat", @"config/tileset.xml", @"config/toy.dat",
                         @"config/toy.xml", @"config/vfx.dat", @"config/vfx.xml", @"config/view.dat",
                         @"config/view.xml", @"config/weapon.dat", @"config/weapon.xml", nil];

      NSString *codeDir = [skPath stringByAppendingPathComponent:@"code"];
      NSString *classChangesDir = [codeDir stringByAppendingPathComponent:@"class-changes"];
      NSString *localeChangesDir = [codeDir stringByAppendingPathComponent:@"locale-changes"];

      dispatch_async(dispatch_get_main_queue(), ^{
        alert.message = @"Rebuilding game resources…";
      });
      NSArray *rsrcFiles = [fm contentsOfDirectoryAtPath:rsrcDir error:nil];
      NSInteger jarsUnpacked = 0;
      for (NSString *file in rsrcFiles) {
          if ([file hasSuffix:@".jar"]) {
              NSString *jarPath = [rsrcDir stringByAppendingPathComponent:file];
              extractZipFile(jarPath, rsrcDir, NO, nil);
              jarsUnpacked++;
          }
      }

      [fm removeItemAtPath:classChangesDir error:nil];
      [fm createDirectoryAtPath:classChangesDir withIntermediateDirectories:YES attributes:nil error:nil];

      NSString *getdownPath = [skPath stringByAppendingPathComponent:@"getdown.txt"];
      NSString *gameVersion = nil;
      if ([fm fileExistsAtPath:getdownPath]) {
          NSString *gdContent = [NSString stringWithContentsOfFile:getdownPath encoding:NSUTF8StringEncoding error:nil];
          NSArray *lines = [gdContent componentsSeparatedByString:@"\n"];
          for (NSString *line in lines) {
              if ([line hasPrefix:@"version = "]) {
                  gameVersion = [[line substringFromIndex:@"version = ".length]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                  break;
              }
          }
      }

      NSInteger resourceMods = 0;
      NSInteger classMods = 0;
      NSInteger modpacks = 0;
      NSInteger skipped = 0;
      NSMutableArray *warnings = [NSMutableArray array];
      BOOL hasClassMods = NO;

      NSMutableDictionary *globalLocaleChanges = [NSMutableDictionary dictionary];

      for (NSInteger i = 0; i < zipsOrModpacks.count; i++) {
          NSString *modFile = zipsOrModpacks[i];
          NSString *modPath = [modsPath stringByAppendingPathComponent:modFile];

          dispatch_async(dispatch_get_main_queue(), ^{
            alert.message = [NSString
                stringWithFormat:@"Processing (%ld/%ld): %@", (long)(i + 1), (long)zipsOrModpacks.count, modFile];
            progressView.progress = (float)(i) / zipsOrModpacks.count;
          });

          BOOL isModpack = [modFile hasSuffix:@".modpack"];

          NSString *tempExtract = [modsPath stringByAppendingPathComponent:@".temp_meta"];
          [fm removeItemAtPath:tempExtract error:nil];
          [fm createDirectoryAtPath:tempExtract withIntermediateDirectories:YES attributes:nil error:nil];

          extractZipFile(modPath, tempExtract, NO, nil);

          NSString *metaPath = [tempExtract stringByAppendingPathComponent:@"mod.json"];
          NSString *modType = nil;
          NSString *pxVersion = nil;
          NSString *modName = modFile;
          NSDictionary *localeChanges = nil;

          if ([fm fileExistsAtPath:metaPath]) {
              NSData *metaData = [NSData dataWithContentsOfFile:metaPath];
              NSDictionary *json = [NSJSONSerialization JSONObjectWithData:metaData options:0 error:nil];
              NSDictionary *modObj = json[@"mod"] ?: json;
              if ([modObj isKindOfClass:[NSDictionary class]]) {
                  modName = modObj[@"name"] ?: modFile;
                  modType = modObj[@"type"];
                  pxVersion = modObj[@"pxVersion"];
                  localeChanges = modObj[@"locale"];
              }
          }
          [fm removeItemAtPath:tempExtract error:nil];

          BOOL isClassMod = [modType isEqualToString:@"class"];

          if (isModpack) {
              NSString *tempPack = [modsPath stringByAppendingPathComponent:@".temp_pack"];
              [fm removeItemAtPath:tempPack error:nil];
              [fm createDirectoryAtPath:tempPack withIntermediateDirectories:YES attributes:nil error:nil];

              extractZipFile(modPath, tempPack, NO, nil);

              NSArray *innerFiles = [fm contentsOfDirectoryAtPath:tempPack error:nil];
              NSInteger innerApplied = 0;
              for (NSString *innerFile in innerFiles) {
                  if ([innerFile hasSuffix:@".zip"]) {
                      NSString *innerPath = [tempPack stringByAppendingPathComponent:innerFile];

                      NSString *innerTempMeta = [tempPack stringByAppendingPathComponent:@".temp_inner_meta"];
                      [fm removeItemAtPath:innerTempMeta error:nil];
                      [fm createDirectoryAtPath:innerTempMeta withIntermediateDirectories:YES attributes:nil error:nil];
                      extractZipFile(innerPath, innerTempMeta, NO, nil);

                      NSString *innerMetaPath = [innerTempMeta stringByAppendingPathComponent:@"mod.json"];
                      NSString *innerType = nil;
                      NSString *innerPx = nil;
                      NSString *innerName = innerFile;
                      NSDictionary *innerLocale = nil;
                      if ([fm fileExistsAtPath:innerMetaPath]) {
                          NSData *innerMetaD = [NSData dataWithContentsOfFile:innerMetaPath];
                          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:innerMetaD options:0 error:nil];
                          NSDictionary *modObj = json[@"mod"] ?: json;
                          if ([modObj isKindOfClass:[NSDictionary class]]) {
                              innerName = modObj[@"name"] ?: innerFile;
                              innerType = modObj[@"type"];
                              innerPx = modObj[@"pxVersion"];
                              innerLocale = modObj[@"locale"];
                          }
                      }
                      [fm removeItemAtPath:innerTempMeta error:nil];

                      BOOL innerIsClass = [innerType isEqualToString:@"class"];
                      if (innerIsClass) {
                          if (!innerPx || !gameVersion || [innerPx isEqualToString:gameVersion]) {
                              extractZipFile(innerPath, classChangesDir, YES, protectedFiles);
                              classMods++;
                              hasClassMods = YES;
                              innerApplied++;
                          } else {
                              skipped++;
                              [warnings addObject:[NSString stringWithFormat:@"Skipped incompatible inner mod %@",
                                                                             innerName]];
                          }
                      } else {
                          extractZipFile(innerPath, rsrcDir, YES, protectedFiles);
                          resourceMods++;
                          innerApplied++;
                      }

                      if (innerLocale) {
                          for (NSString *bundle in innerLocale) {
                              NSMutableDictionary *bundleChanges = globalLocaleChanges[bundle];
                              if (!bundleChanges) {
                                  bundleChanges = [NSMutableDictionary dictionary];
                                  globalLocaleChanges[bundle] = bundleChanges;
                              }
                              [bundleChanges addEntriesFromDictionary:innerLocale[bundle]];
                          }
                      }
                  }
              }
              if (innerApplied > 0)
                  modpacks++;
              [fm removeItemAtPath:tempPack error:nil];
          } else if (isClassMod) {
              if (!pxVersion || !gameVersion || [pxVersion isEqualToString:gameVersion]) {
                  extractZipFile(modPath, classChangesDir, NO, nil);
                  classMods++;
                  hasClassMods = YES;
              } else {
                  skipped++;
                  [warnings addObject:[NSString stringWithFormat:@"Class mod '%@' requires game "
                                                                 @"version %@ but current is %@",
                                                                 modName, pxVersion, gameVersion]];
              }
          } else {
              extractZipFile(modPath, rsrcDir, NO, nil);
              resourceMods++;
          }

          if (localeChanges) {
              for (NSString *bundle in localeChanges) {
                  NSMutableDictionary *bundleChanges = globalLocaleChanges[bundle];
                  if (!bundleChanges) {
                      bundleChanges = [NSMutableDictionary dictionary];
                      globalLocaleChanges[bundle] = bundleChanges;
                  }
                  [bundleChanges addEntriesFromDictionary:localeChanges[bundle]];
              }
          }
      }

      if (hasClassMods) {
          dispatch_async(dispatch_get_main_queue(), ^{
            alert.message = @"Merging class changes into config.jar…";
          });
          NSString *configJar = [codeDir stringByAppendingPathComponent:@"config.jar"];
          if ([fm fileExistsAtPath:configJar]) {
              extractJarWithoutOverwrite(configJar, classChangesDir);

              NSString *configNewJar = [codeDir stringByAppendingPathComponent:@"config-new.jar"];
              NSString *configOldJar = [codeDir stringByAppendingPathComponent:@"config-old.jar"];

              createZipFile(classChangesDir, configNewJar);

              [fm removeItemAtPath:configOldJar error:nil];
              if ([fm moveItemAtPath:configJar toPath:configOldJar error:nil]) {
                  if ([fm moveItemAtPath:configNewJar toPath:configJar error:nil]) {
                      [fm removeItemAtPath:configOldJar error:nil];
                  } else {
                      [fm moveItemAtPath:configOldJar toPath:configJar error:nil];
                  }
              }
          }
      }
      [fm removeItemAtPath:classChangesDir error:nil];

      if (globalLocaleChanges.count > 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            alert.message = @"Applying locale changes…";
          });
          NSString *projectxConfig = [codeDir stringByAppendingPathComponent:@"projectx-config.jar"];
          if ([fm fileExistsAtPath:projectxConfig]) {
              [fm removeItemAtPath:localeChangesDir error:nil];
              [fm createDirectoryAtPath:localeChangesDir withIntermediateDirectories:YES attributes:nil error:nil];

              extractZipFile(projectxConfig, localeChangesDir, NO, nil);

              NSInteger appliedLocales = 0;
              for (NSString *bundlePath in globalLocaleChanges) {
                  NSString *propsPath = [localeChangesDir
                      stringByAppendingPathComponent:[@"rsrc/i18n/" stringByAppendingString:bundlePath]];
                  if ([fm fileExistsAtPath:propsPath]) {
                      NSString *propsContent = [NSString stringWithContentsOfFile:propsPath
                                                                         encoding:NSUTF8StringEncoding
                                                                            error:nil];
                      NSMutableDictionary *properties = [NSMutableDictionary dictionary];
                      NSArray *lines = [propsContent componentsSeparatedByString:@"\n"];
                      for (NSString *line in lines) {
                          NSString *trimmed =
                              [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                          if ([trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"!"] || trimmed.length == 0)
                              continue;
                          NSRange range = [trimmed rangeOfString:@"="];
                          if (range.location != NSNotFound) {
                              NSString *key = [[trimmed substringToIndex:range.location]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                              NSString *val = [[trimmed substringFromIndex:range.location + 1]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                              properties[key] = val;
                          }
                      }

                      NSDictionary *overrides = globalLocaleChanges[bundlePath];
                      for (NSString *key in overrides) {
                          properties[key] = overrides[key];
                          appliedLocales++;
                      }

                      NSMutableString *newContent = [NSMutableString string];
                      for (NSString *key in properties) {
                          [newContent appendFormat:@"%@=%@\n", key, properties[key]];
                      }
                      [newContent writeToFile:propsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                  }
              }

              NSString *newJar = [codeDir stringByAppendingPathComponent:@"projectx-config-new.jar"];
              NSString *oldJar = [codeDir stringByAppendingPathComponent:@"projectx-config-old.jar"];
              createZipFile(localeChangesDir, newJar);

              [fm removeItemAtPath:oldJar error:nil];
              if ([fm moveItemAtPath:projectxConfig toPath:oldJar error:nil]) {
                  if ([fm moveItemAtPath:newJar toPath:projectxConfig error:nil]) {
                      [fm removeItemAtPath:oldJar error:nil];
                  } else {
                      [fm moveItemAtPath:oldJar toPath:projectxConfig error:nil];
                  }
              }
          }
          [fm removeItemAtPath:localeChangesDir error:nil];
      }

      [fm removeItemAtPath:[rsrcDir stringByAppendingPathComponent:@"mod.json"] error:nil];
      [fm removeItemAtPath:[rsrcDir stringByAppendingPathComponent:@"mod.png"] error:nil];

      dispatch_async(dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES
                                  completion:^{
                                    NSMutableString *msg = [NSMutableString
                                        stringWithFormat:@"Mods applied successfully!\nMods: "
                                                         @"%ld applied (%ld resource, %ld "
                                                         @"class, %ld modpacks)\nJars "
                                                         @"unpacked: %ld\nSkipped: %ld",
                                                         (long)(resourceMods + classMods + modpacks),
                                                         (long)resourceMods, (long)classMods, (long)modpacks,
                                                         (long)jarsUnpacked, (long)skipped];
                                    if (warnings.count > 0) {
                                        [msg appendString:@"\n\nWarnings:"];
                                        for (NSString *warn in warnings) {
                                            [msg appendFormat:@"\n- %@", warn];
                                        }
                                    }
                                    [self showAlertWithTitle:@"Apply Complete" message:msg];
                                  }];
      });
    });
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

@end
