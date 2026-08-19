#import "LauncherViewController.h"
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "GameViewController.h"
#import "SKInstaller.h"
#import "SKModManager.h"
#import "SKZipUtils.h"
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

// JIT status pill (tap to enable via StikJIT)
@property (nonatomic, strong) UIButton *jitStatusButton;
@property (nonatomic, strong) NSTimer *jitStatusTimer;

// Sidebar & Dimming Overlay
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *sidebarView;
@property (nonatomic, strong) NSLayoutConstraint *sidebarTrailingConstraint;
@property (nonatomic, strong) UIButton *btnLogout;
@property (nonatomic, strong) UIView *logoutDivider;
@property (nonatomic, strong) UISwitch *avoidEdgesSwitch;
@property (nonatomic, strong) UIButton *ramMinusButton;
@property (nonatomic, strong) UIButton *ramPlusButton;
@property (nonatomic, strong) UILabel *ramValueLabel;
@property (nonatomic, strong) UILabel *ramFreeLabel;
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

    // 4b. JIT status pill (tap to enable JIT via StikJIT before playing)
    self.jitStatusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jitStatusButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.jitStatusButton.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.jitStatusButton.layer.cornerRadius = 16;
    self.jitStatusButton.layer.borderWidth = 1;
    self.jitStatusButton.clipsToBounds = YES;
    self.jitStatusButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Icon<->title gap added via contentEdgeInsets and cancelled in the title/image
    // insets so the button's intrinsic width stays correct (a bare titleEdgeInsets
    // shifts the label without widening the button, which clips it).
    const CGFloat spacing = 6;
    self.jitStatusButton.contentEdgeInsets = UIEdgeInsetsMake(8, 16 + spacing / 2, 8, 16 + spacing / 2);
    self.jitStatusButton.imageEdgeInsets = UIEdgeInsetsMake(0, -spacing / 2, 0, spacing / 2);
    self.jitStatusButton.titleEdgeInsets = UIEdgeInsetsMake(0, spacing / 2, 0, -spacing / 2);
    [self.jitStatusButton setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                          forAxis:UILayoutConstraintAxisHorizontal];
    [self.jitStatusButton addTarget:self
                             action:@selector(onEnableJITPressed)
                   forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jitStatusButton];

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

    UIButton *btnDownloadMods = [self createSidebarButtonWithTitle:@"Download Modpack"
                                                          iconName:@"icloud.and.arrow.down"
                                                            action:@selector(onDownloadMods)];
    [stackView addArrangedSubview:btnDownloadMods];

    UIButton *btnApplyMods = [self createSidebarButtonWithTitle:@"Apply Mods"
                                                       iconName:@"hammer"
                                                         action:@selector(onApplyMods)];
    [stackView addArrangedSubview:btnApplyMods];

    UIButton *btnRemoveMods = [self createSidebarButtonWithTitle:@"Remove Mods"
                                                        iconName:@"trash"
                                                          action:@selector(onRemoveMods)];
    [stackView addArrangedSubview:btnRemoveMods];

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

    // Max RAM stepper
    UIView *ramRow = [[UIView alloc] init];
    ramRow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *ramLabel = [[UILabel alloc] init];
    ramLabel.text = @"Max RAM";
    ramLabel.textColor = UIColor.whiteColor;
    ramLabel.font = [UIFont systemFontOfSize:14];
    ramLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [ramRow addSubview:ramLabel];

    self.ramMinusButton = [self ramStepperWithTitle:@"\u2212" action:@selector(onRamDecrease)];
    self.ramPlusButton = [self ramStepperWithTitle:@"+" action:@selector(onRamIncrease)];

    self.ramValueLabel = [[UILabel alloc] init];
    self.ramValueLabel.textColor = UIColor.whiteColor;
    self.ramValueLabel.font = [UIFont systemFontOfSize:14];
    self.ramValueLabel.textAlignment = NSTextAlignmentCenter;
    self.ramValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *ramStepper = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.ramMinusButton, self.ramValueLabel, self.ramPlusButton
    ]];
    ramStepper.axis = UILayoutConstraintAxisHorizontal;
    ramStepper.spacing = 4;
    ramStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [ramRow addSubview:ramStepper];
    [stackView addArrangedSubview:ramRow];

    self.ramFreeLabel = [[UILabel alloc] init];
    self.ramFreeLabel.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    self.ramFreeLabel.font = [UIFont systemFontOfSize:12];
    self.ramFreeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView addArrangedSubview:self.ramFreeLabel];
    [self refreshRamLabels];

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
        [self.jitStatusButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.jitStatusButton.topAnchor constraintEqualToAnchor:self.btnLaunch.bottomAnchor constant:16],

        [self.spinner.topAnchor constraintEqualToAnchor:self.jitStatusButton.bottomAnchor constant:16],

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
        [avoidRow.heightAnchor constraintEqualToConstant:50],

        [ramLabel.leadingAnchor constraintEqualToAnchor:ramRow.leadingAnchor constant:8],
        [ramLabel.centerYAnchor constraintEqualToAnchor:ramRow.centerYAnchor],
        [ramStepper.trailingAnchor constraintEqualToAnchor:ramRow.trailingAnchor constant:-8],
        [ramStepper.centerYAnchor constraintEqualToAnchor:ramRow.centerYAnchor],
        [self.ramValueLabel.widthAnchor constraintEqualToConstant:76],
        [ramRow.heightAnchor constraintEqualToConstant:50]
    ]];

    [self setButtonsEnabled:NO];
    [self fetchPlayerCount];
    [self ensureRuntime];

    // Refresh the JIT pill whenever we come back from StikJIT.
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshJITStatus)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    [self refreshJITStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateLogoutButtonVisibility];
    [self refreshJITStatus];
    // Poll while visible so the pill flips to "enabled" the moment JIT is granted.
    [self.jitStatusTimer invalidate];
    self.jitStatusTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                           target:self
                                                         selector:@selector(refreshJITStatus)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.jitStatusTimer invalidate];
    self.jitStatusTimer = nil;
}

- (void)dealloc {
    [self.jitStatusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - JIT status

- (void)refreshJITStatus {
    BOOL enabled = isJITEnabled(NO);
    UIColor *green = [UIColor colorWithRed:0.30 green:0.78 blue:0.42 alpha:1.0];
    UIColor *amber = [UIColor colorWithRed:0.95 green:0.62 blue:0.20 alpha:1.0];
    UIColor *color = enabled ? green : amber;

    [self.jitStatusButton setTitle:(enabled ? @"JIT enabled" : @"Enable JIT") forState:UIControlStateNormal];
    [self.jitStatusButton setTitleColor:color forState:UIControlStateNormal];
    self.jitStatusButton.tintColor = color;
    self.jitStatusButton.layer.borderColor = [color colorWithAlphaComponent:0.6].CGColor;
    self.jitStatusButton.backgroundColor = [color colorWithAlphaComponent:0.12];
    if (@available(iOS 13.0, *)) {
        NSString *icon = enabled ? @"checkmark.seal.fill" : @"bolt.slash.fill";
        [self.jitStatusButton setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    }
    self.jitStatusButton.enabled = !enabled;  // nothing to do once enabled
}

- (void)onEnableJITPressed {
    if (isJITEnabled(NO)) {
        return;
    }
    NSURL *url = skJITEnableURL();
    if (!url) {
        return;
    }
    [[UIApplication sharedApplication]
                  openURL:url
                  options:@{}
        completionHandler:^(BOOL success) {
          if (!success) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlertWithTitle:@"StikJIT not found"
                                 message:@"Install StikJIT (with a paired device) to enable JIT, then tap \"Enable "
                                         @"JIT\" again. JIT is required to run Spiral Knights."];
              });
          }
        }];
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

- (UIButton *)ramStepperWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.3] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    button.layer.cornerRadius = 8;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:44],
        [button.heightAnchor constraintEqualToConstant:36],
    ]];
    return button;
}

- (void)onRamDecrease {
    sk_ram_set_mb(sk_ram_get_mb() - SK_RAM_STEP_MB);
    [self refreshRamLabels];
}

- (void)onRamIncrease {
    sk_ram_set_mb(sk_ram_get_mb() + SK_RAM_STEP_MB);
    [self refreshRamLabels];
}

- (void)refreshRamLabels {
    int current = sk_ram_get_mb();
    int max = sk_ram_max_mb();
    self.ramValueLabel.text = [NSString stringWithFormat:@"%d MB", current];
    self.ramMinusButton.enabled = current > SK_RAM_MIN_MB;
    self.ramPlusButton.enabled = current < max;
    self.ramFreeLabel.text = [NSString stringWithFormat:@"%d MB available, %d MB max",
                              sk_ram_available_mb(), max];
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

    // Include HotSpot crash reports (-XX:ErrorFile writes hs_err_pid*.log here) and
    // the VM GC/code-cache logs (-Xlog writes vmlog-*.log here).
    for (NSString *name in [fileManager contentsOfDirectoryAtPath:home error:nil]) {
        BOOL isCrashReport = [name hasPrefix:@"hs_err_pid"] && [name hasSuffix:@".log"];
        // No suffix test: -Xlog rotation appends an index (vmlog-<pid>.log.0).
        BOOL isVMLog = [name hasPrefix:@"vmlog-"];
        if (isCrashReport || isVMLog) {
            [items addObject:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:name]]];
        }
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

    // textContentType is what puts a password manager in the QuickType bar. The pair has to
    // be username + password on adjacent fields for AutoFill to offer a credential rather
    // than a plain "Passwords" shortcut.
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
      tf.placeholder = @"Steam username";
      tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
      tf.autocorrectionType = UITextAutocorrectionTypeNo;
      tf.spellCheckingType = UITextSpellCheckingTypeNo;
      tf.keyboardType = UIKeyboardTypeASCIICapable;
      tf.textContentType = UITextContentTypeUsername;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
      tf.placeholder = @"Steam password";
      tf.secureTextEntry = YES;
      tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
      tf.autocorrectionType = UITextAutocorrectionTypeNo;
      tf.spellCheckingType = UITextSpellCheckingTypeNo;
      tf.textContentType = UITextContentTypePassword;
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

- (UIAlertController *)createProgressAlertWithTitle:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"Preparing…"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    progressView.progressTintColor = [UIColor colorWithRed:171.0 / 255.0
                                                     green:74.0 / 255.0
                                                      blue:129.0 / 255.0
                                                     alpha:1.0];
    progressView.tag = 999;
    [alert.view addSubview:progressView];

    [NSLayoutConstraint activateConstraints:@[
        [progressView.leadingAnchor constraintEqualToAnchor:alert.view.leadingAnchor constant:20],
        [progressView.trailingAnchor constraintEqualToAnchor:alert.view.trailingAnchor constant:-20],
        [progressView.bottomAnchor constraintEqualToAnchor:alert.view.bottomAnchor constant:-20]
    ]];

    [alert.view.heightAnchor constraintEqualToConstant:120].active = YES;
    return alert;
}

- (void)updateProgressAlert:(UIAlertController *)alert progress:(float)progress message:(NSString *)message {
    alert.message = message;
    UIProgressView *progressView = [alert.view viewWithTag:999];
    if ([progressView isKindOfClass:[UIProgressView class]]) {
        progressView.progress = progress;
    }
}

- (void)onDownloadMods {
    UIAlertController *alert = [self createProgressAlertWithTitle:@"Downloading Mods"];
    [self presentViewController:alert animated:YES completion:nil];

    [[SKModManager sharedManager]
        downloadModsWithProgress:^(float progress, NSString *status) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self updateProgressAlert:alert progress:progress message:status];
          });
        }
        completion:^(BOOL success, NSString *summary, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        if (success) {
                                            [self showAlertWithTitle:@"Download Modpack" message:summary];
                                        } else {
                                            [self showAlertWithTitle:@"Download Failed"
                                                             message:error.localizedDescription];
                                        }
                                      }];
          });
        }];
}

- (void)onApplyMods {
    UIAlertController *alert = [self createProgressAlertWithTitle:@"Applying Mods"];
    [self presentViewController:alert animated:YES completion:nil];

    [[SKModManager sharedManager]
        applyModsWithProgress:^(float progress, NSString *status) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self updateProgressAlert:alert progress:progress message:status];
          });
        }
        completion:^(BOOL success, NSString *summary, NSArray *warnings, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES
                                      completion:^{
                                        if (success) {
                                            NSMutableString *msg = [NSMutableString stringWithString:summary];
                                            if (warnings.count > 0) {
                                                [msg appendString:@"\n\nWarnings:\n"];
                                                for (NSString *warn in warnings) {
                                                    [msg appendFormat:@"- %@\n", warn];
                                                }
                                            }
                                            [self showAlertWithTitle:@"Operation completed successfully."
                                                             message:[msg stringByTrimmingCharactersInSet:
                                                                              [NSCharacterSet
                                                                                  whitespaceAndNewlineCharacterSet]]];
                                        } else {
                                            [self showAlertWithTitle:@"Apply Failed"
                                                             message:error.localizedDescription];
                                        }
                                      }];
          });
        }];
}

- (void)onRemoveMods {
    UIAlertController *alert = [self createProgressAlertWithTitle:@"Removing Mods"];
    [self presentViewController:alert animated:YES completion:nil];

    [[SKModManager sharedManager]
        removeModsWithProgress:^(float progress, NSString *status) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self updateProgressAlert:alert progress:progress message:status];
          });
        }
        completion:^(BOOL success, NSString *summary, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [alert
                dismissViewControllerAnimated:YES
                                   completion:^{
                                     if (success) {
                                         [self showAlertWithTitle:@"Operation completed successfully." message:summary];
                                     } else {
                                         [self showAlertWithTitle:@"Remove Failed" message:error.localizedDescription];
                                     }
                                   }];
          });
        }];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

@end
