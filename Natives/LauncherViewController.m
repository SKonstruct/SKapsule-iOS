#import "LauncherViewController.h"
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "GameViewController.h"
#import "SKBuiltinJIT.h"
#import "SKJITSetupViewController.h"
#import "SKControlsEditorViewController.h"
#import "SKCredentials.h"
#import "SKInstaller.h"
#import "SKModManager.h"
#import "SKNewsFeed.h"
#import "SKReporter.h"
#import "SKServers.h"
#import "SKZipUtils.h"
#import "config.h"
#import "utils.h"

/// Steam only knows Steam players; the count is scaled for standalone installs, as KnightLauncher does.
static const float kPlayerEstimateMult = 1.4f;

@interface LauncherViewController ()
@property (nonatomic, strong) UISegmentedControl *modeSegmentedControl;
@property (nonatomic, strong) UIStackView *serverStack;
@property (nonatomic, strong) UILabel *serverNameLabel;
@property (nonatomic, strong) UIControl *serverPick;
@property (nonatomic, strong) UIButton *serverActionButton;
@property (nonatomic, strong) UIButton *btnLaunch;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *newsCard;
@property (nonatomic, strong) UIImageView *newsImageView;
@property (nonatomic, strong) UILabel *newsEndsInLabel;
@property (nonatomic, strong) NSLayoutConstraint *newsEndsInHeight;
@property (nonatomic, strong) UILabel *newsTitleLabel;
@property (nonatomic, strong) UILabel *newsBodyLabel;
@property (nonatomic, copy) NSString *newsLink;
@property (nonatomic, copy) NSArray<SKNewsItem *> *newsItems;
@property (nonatomic, assign) NSUInteger newsIndex;
@property (nonatomic, strong) NSTimer *newsTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *newsImages;
@property (nonatomic, strong) NSMutableSet<NSString *> *newsImageRequests;
@property (nonatomic, strong) UIColor *newsChipColor;
@property (nonatomic, assign) NSInteger liveSteamPlayers;
@property (nonatomic, assign) NSInteger previewSteamPlayers;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) NSString *updateURL;
@property (nonatomic, strong) UIButton *updateButton;
@property (nonatomic, strong) UIButton *checkUpdatesButton;
@property (nonatomic, assign) BOOL checkingForUpdates;
@property (nonatomic, strong) UILabel *setupStatus;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

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
@property (nonatomic, strong) UISwitch *crashReportSwitch;
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
    [btnOptions setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    btnOptions.tintColor = UIColor.whiteColor;
    btnOptions.translatesAutoresizingMaskIntoConstraints = NO;
    [btnOptions addTarget:self action:@selector(toggleSidebar) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnOptions];

    // 1b. Donate: Buy Me a Coffee, in its brand yellow with its glyph, left of the gear.
    UIButton *btnDonate = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnDonate setImage:[[UIImage imageNamed:@"BuyMeACoffee"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
               forState:UIControlStateNormal];
    btnDonate.tintColor = UIColor.blackColor;
    btnDonate.backgroundColor = [UIColor colorWithRed:1.0 green:221.0 / 255.0 blue:0 alpha:1.0];  // #FFDD00
    btnDonate.layer.cornerRadius = 22;
    btnDonate.imageEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    btnDonate.imageView.contentMode = UIViewContentModeScaleAspectFit;
    btnDonate.accessibilityLabel = @"Support SKapsule on Buy Me a Coffee";
    btnDonate.translatesAutoresizingMaskIntoConstraints = NO;
    [btnDonate addTarget:self action:@selector(onDonate) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnDonate];

    // 2. Title & Subtitle Container
    UILabel *titleLabel = [[UILabel alloc] init];
    self.titleLabel = titleLabel;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont boldSystemFontOfSize:32];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    // Set title with version name
    NSString *verStr = @CONFIG_VERSION;
    titleLabel.text = [NSString stringWithFormat:@"SKapsule v%@", verStr];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = @"Spiral Knights for iOS";
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.subtitleLabel];

    // Its own control: the subtitle is rewritten by the player count and has its own tap.
    self.updateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.updateButton setTitleColor:[UIColor colorWithRed:0.95 green:0.75 blue:0.23 alpha:1.0]
                            forState:UIControlStateNormal];
    self.updateButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.updateButton.hidden = YES;
    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.updateButton addTarget:self action:@selector(onUpdateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.updateButton];

    // 3. Segmented Control
    self.modeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Web", @"Steam"]];
    self.modeSegmentedControl.selectedSegmentIndex = 0;
    self.modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;

    self.modeSegmentedControl.selectedSegmentTintColor = themeColor;

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
    // Server picker above the Web/Steam switch; the switch is Official's only, so showSelectedServer
    // hides it for a private server and the stack closes the gap.
    self.serverStack = [[UIStackView alloc] initWithArrangedSubviews:@[ [self makeServerSelector], self.modeSegmentedControl ]];
    self.serverStack.axis = UILayoutConstraintAxisVertical;
    self.serverStack.alignment = UIStackViewAlignmentCenter;
    self.serverStack.spacing = 12;
    self.serverStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.serverStack];

    // Restore persistent segmented selection
    NSString *savedMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"login_mode"] ?: @"Web";
    if ([savedMode isEqualToString:@"Steam"]) {
        self.modeSegmentedControl.selectedSegmentIndex = 1;
    } else {
        self.modeSegmentedControl.selectedSegmentIndex = 0;
    }


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

    [self.btnLaunch setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    self.btnLaunch.tintColor = UIColor.whiteColor;
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
    self.spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleMedium;
    self.spinner.color = UIColor.whiteColor;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    // 6. Setup Dimming Overlay
    // News card: the current in-game announcement. Hidden until one arrives, so
    // the screen is unchanged when there is nothing to show.
    self.newsCard = [[UIView alloc] init];
    self.newsCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.newsCard.layer.cornerRadius = 12;
    self.newsCard.layer.borderWidth = 1;
    self.newsCard.layer.borderColor = [themeColor colorWithAlphaComponent:0.35].CGColor;
    self.newsCard.clipsToBounds = YES;
    self.newsCard.hidden = YES;
    self.newsCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.newsCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                            initWithTarget:self
                                                    action:@selector(onNewsTapped)]];
    [self.view addSubview:self.newsCard];

    self.newsImageView = [[UIImageView alloc] init];
    self.newsImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.newsImageView.clipsToBounds = YES;
    self.newsImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.newsCard addSubview:self.newsImageView];

    // The banner art is arbitrary, so the text carries its own contrast rather
    // than trusting whatever image arrives.
    UIView *newsScrim = [[UIView alloc] init];
    newsScrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    newsScrim.translatesAutoresizingMaskIntoConstraints = NO;
    [self.newsCard addSubview:newsScrim];

    self.newsEndsInLabel = [[UILabel alloc] init];
    self.newsEndsInLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.newsEndsInLabel.textColor = UIColor.whiteColor;
    self.newsChipColor = [themeColor colorWithAlphaComponent:0.8];
    self.newsEndsInLabel.backgroundColor = self.newsChipColor;
    self.newsEndsInLabel.textAlignment = NSTextAlignmentCenter;
    self.newsEndsInLabel.layer.cornerRadius = 4;
    self.newsEndsInLabel.clipsToBounds = YES;
    self.newsEndsInLabel.translatesAutoresizingMaskIntoConstraints = NO;
    // Collapsed rather than merely hidden when there is no expiry: a hidden view
    // keeps its frame, which would leave the chip's gap above the title.
    self.newsEndsInHeight = [self.newsEndsInLabel.heightAnchor constraintEqualToConstant:18];
    [self.newsCard addSubview:self.newsEndsInLabel];

    self.newsTitleLabel = [[UILabel alloc] init];
    self.newsTitleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.newsTitleLabel.textColor = UIColor.whiteColor;
    self.newsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.newsCard addSubview:self.newsTitleLabel];

    self.newsBodyLabel = [[UILabel alloc] init];
    self.newsBodyLabel.font = [UIFont systemFontOfSize:12];
    self.newsBodyLabel.textColor = [UIColor colorWithWhite:0.87 alpha:1.0];
    self.newsBodyLabel.numberOfLines = 2;
    self.newsBodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.newsCard addSubview:self.newsBodyLabel];

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

    UIButton *btnEditControls = [self createSidebarButtonWithTitle:@"Edit Controls"
                                                          iconName:@"gamecontroller"
                                                            action:@selector(onEditControls)];
    [stackView addArrangedSubview:btnEditControls];

    UIButton *btnJITSetup = [self createSidebarButtonWithTitle:@"JIT Setup"
                                                      iconName:@"bolt.badge.automatic"
                                                        action:@selector(onJITSetup:)];
    [stackView addArrangedSubview:btnJITSetup];

    UIButton *btnCheckUpdates = [self createSidebarButtonWithTitle:@"Check for Updates"
                                                          iconName:@"arrow.triangle.2.circlepath"
                                                            action:@selector(onCheckForUpdates)];
    [stackView addArrangedSubview:btnCheckUpdates];
    self.checkUpdatesButton = btnCheckUpdates;

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
    [self.btnLogout setImage:[UIImage systemImageNamed:@"rectangle.portrait.and.arrow.right"]
                    forState:UIControlStateNormal];
    self.btnLogout.tintColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
    self.btnLogout.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
    self.btnLogout.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
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

    // Max RAM stepper (kept above the avoid-edges row)
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
    ramStepper.spacing = 2;
    ramStepper.alignment = UIStackViewAlignmentCenter;
    // One rounded container around the whole stepper reads better than three separately
    // bordered pieces, and lets the buttons lose their own borders.
    ramStepper.layoutMargins = UIEdgeInsetsMake(2, 2, 2, 2);
    ramStepper.layoutMarginsRelativeArrangement = YES;
    ramStepper.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    ramStepper.layer.cornerRadius = 8;
    ramStepper.layer.borderWidth = 1;
    ramStepper.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    ramStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [ramRow addSubview:ramStepper];
    [stackView addArrangedSubview:ramRow];

    self.ramFreeLabel = [[UILabel alloc] init];
    self.ramFreeLabel.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    self.ramFreeLabel.font = [UIFont systemFontOfSize:12];
    self.ramFreeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView addArrangedSubview:self.ramFreeLabel];
    [self refreshRamLabels];

    [stackView addArrangedSubview:avoidRow];

    // Crash reporting row
    UIView *crashRow = [[UIView alloc] init];
    crashRow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *crashLabel = [[UILabel alloc] init];
    crashLabel.text = @"Send crash reports";
    crashLabel.textColor = UIColor.whiteColor;
    crashLabel.font = [UIFont systemFontOfSize:14];
    crashLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [crashRow addSubview:crashLabel];

    self.crashReportSwitch = [[UISwitch alloc] init];
    self.crashReportSwitch.onTintColor = themeColor;
    self.crashReportSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    // Defaults to on, so an absent key must read as YES rather than boolForKey's NO.
    id crashPref = [NSUserDefaults.standardUserDefaults objectForKey:SKReportingEnabledKey];
    self.crashReportSwitch.on = crashPref == nil ? YES : [crashPref boolValue];
    [self.crashReportSwitch addTarget:self
                               action:@selector(onCrashReportingChanged:)
                     forControlEvents:UIControlEventValueChanged];
    [crashRow addSubview:self.crashReportSwitch];
    [stackView addArrangedSubview:crashRow];

    UILabel *crashNote = [[UILabel alloc] init];
    crashNote.text = @"Anonymous: device model, iOS version, app build and JVM crash logs.";
    crashNote.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    crashNote.font = [UIFont systemFontOfSize:12];
    crashNote.numberOfLines = 0;
    crashNote.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView addArrangedSubview:crashNote];

    // Layout Constraints
    self.sidebarTrailingConstraint = [self.sidebarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                                                     constant:280];

    [NSLayoutConstraint activateConstraints:@[
        // Options Button
        [btnOptions.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [btnOptions.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [btnOptions.widthAnchor constraintEqualToConstant:44], [btnOptions.heightAnchor constraintEqualToConstant:44],
        [btnDonate.centerYAnchor constraintEqualToAnchor:btnOptions.centerYAnchor],
        [btnDonate.trailingAnchor constraintEqualToAnchor:btnOptions.leadingAnchor constant:-12],
        [btnDonate.widthAnchor constraintEqualToConstant:44], [btnDonate.heightAnchor constraintEqualToConstant:44],

        // Title & Subtitle Layout
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:self.subtitleLabel.topAnchor constant:-4],

        [self.subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.serverStack.topAnchor constant:-30],
        [self.updateButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.updateButton.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:2],
        [self.updateButton.heightAnchor constraintEqualToConstant:26],

        // Server picker + segmented control
        [self.serverStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.serverStack.bottomAnchor constraintEqualToAnchor:self.btnLaunch.topAnchor constant:-20],
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

        // Pinned to the bottom; the >= keeps it from colliding with the status
        // line on a short screen rather than overlapping it.
        [self.newsCard.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
                                                   constant:24],
        [self.newsCard.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                                                     constant:-24],
        [self.newsCard.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                   constant:-24],
        [self.newsCard.heightAnchor constraintEqualToConstant:112],
        [self.newsCard.topAnchor constraintGreaterThanOrEqualToAnchor:self.setupStatus.bottomAnchor
                                                            constant:16],

        [self.newsImageView.topAnchor constraintEqualToAnchor:self.newsCard.topAnchor],
        [self.newsImageView.bottomAnchor constraintEqualToAnchor:self.newsCard.bottomAnchor],
        [self.newsImageView.leadingAnchor constraintEqualToAnchor:self.newsCard.leadingAnchor],
        [self.newsImageView.trailingAnchor constraintEqualToAnchor:self.newsCard.trailingAnchor],
        [newsScrim.topAnchor constraintEqualToAnchor:self.newsCard.topAnchor],
        [newsScrim.bottomAnchor constraintEqualToAnchor:self.newsCard.bottomAnchor],
        [newsScrim.leadingAnchor constraintEqualToAnchor:self.newsCard.leadingAnchor],
        [newsScrim.trailingAnchor constraintEqualToAnchor:self.newsCard.trailingAnchor],

        [self.newsEndsInLabel.topAnchor constraintEqualToAnchor:self.newsCard.topAnchor constant:12],
        [self.newsEndsInLabel.leadingAnchor constraintEqualToAnchor:self.newsCard.leadingAnchor
                                                           constant:12],
        self.newsEndsInHeight,
        [self.newsEndsInLabel.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [self.newsTitleLabel.topAnchor constraintEqualToAnchor:self.newsEndsInLabel.bottomAnchor
                                                      constant:6],
        [self.newsTitleLabel.leadingAnchor constraintEqualToAnchor:self.newsCard.leadingAnchor
                                                          constant:12],
        [self.newsTitleLabel.trailingAnchor constraintEqualToAnchor:self.newsCard.trailingAnchor
                                                           constant:-12],
        [self.newsBodyLabel.topAnchor constraintEqualToAnchor:self.newsTitleLabel.bottomAnchor
                                                     constant:2],
        [self.newsBodyLabel.leadingAnchor constraintEqualToAnchor:self.newsCard.leadingAnchor
                                                         constant:12],
        [self.newsBodyLabel.trailingAnchor constraintEqualToAnchor:self.newsCard.trailingAnchor
                                                          constant:-12],

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

        [crashLabel.leadingAnchor constraintEqualToAnchor:crashRow.leadingAnchor constant:8],
        [crashLabel.centerYAnchor constraintEqualToAnchor:crashRow.centerYAnchor],
        [self.crashReportSwitch.leadingAnchor constraintGreaterThanOrEqualToAnchor:crashLabel.trailingAnchor
                                                                         constant:8],
        [self.crashReportSwitch.trailingAnchor constraintEqualToAnchor:crashRow.trailingAnchor constant:-8],
        [self.crashReportSwitch.centerYAnchor constraintEqualToAnchor:crashRow.centerYAnchor],
        [crashRow.heightAnchor constraintEqualToConstant:44],

        [ramLabel.leadingAnchor constraintEqualToAnchor:ramRow.leadingAnchor constant:8],
        [ramLabel.centerYAnchor constraintEqualToAnchor:ramRow.centerYAnchor],
        [ramStepper.trailingAnchor constraintEqualToAnchor:ramRow.trailingAnchor constant:-8],
        [ramStepper.centerYAnchor constraintEqualToAnchor:ramRow.centerYAnchor],
        // The label had no trailing constraint, so nothing kept it clear of the stepper.
        [ramStepper.leadingAnchor constraintGreaterThanOrEqualToAnchor:ramLabel.trailingAnchor
                                                             constant:8],
        [self.ramValueLabel.widthAnchor constraintEqualToConstant:62],
        [ramRow.heightAnchor constraintEqualToConstant:40]
    ]];

    [self setButtonsEnabled:NO];
    [self fetchPlayerCount];
    [self fetchNews];
    [self checkForUpdate];
    // After init_redirectStdio has rotated latestlog.txt -> latestlog.old.txt, so the
    // tail we attach belongs to the run that crashed.
    // Order matters: the scan closes the previous session as "crashed" if it finds an
    // hs_err, so it has to run before the new one opens.
    // Off the main thread: it reads and scrubs files of up to half a megabyte each. Both calls
    // stay in one block so the order above holds.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      SKReportScanCrashArtifacts();
      SKReportSessionStart();
    });
    [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
                  SKReportSessionEnd(@"exited");
                }];
    [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
                  // Without this everything after the first background sits outside any
                  // session, so later crashes are never attributed and adoption undercounts.
                  SKReportSessionStart();
                }];
    [self ensureRuntime];

    // Refresh the JIT pill whenever we come back from StikJIT.
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshJITStatus)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    [self refreshJITStatus];
}

/**
 * Re-assert portrait when the launcher comes back.
 *
 * supportedInterfaceOrientations already says portrait-only, but iOS does not
 * re-evaluate it on its own after the landscape game controller is dismissed --
 * the launcher would stay sideways until the device was physically rotated.
 */
- (void)enforcePortraitOrientation {
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *scene = self.view.window.windowScene;
    if (scene) {
        UIWindowSceneGeometryPreferencesIOS *portrait =
          [[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [scene requestGeometryUpdateWithPreferences:portrait errorHandler:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Not viewDidLoad: presenting from there silently drops the alert, and the trap is
    // marked reported either way, so the one chance to explain it would be lost.
    [self warnIfJITTrapWentUnserviced];
    // In viewDidAppear, not viewWillAppear: the window scene is nil until the view
    // is actually in a window, and the scene is what performs the rotation.
    [self enforcePortraitOrientation];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showSelectedServer];
    [self updateLogoutButtonVisibility];
    [self refreshJITStatus];
    [self startNewsRotation];
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
    [self.newsTimer invalidate];
    self.newsTimer = nil;
}

- (void)dealloc {
    [self.jitStatusTimer invalidate];
    [self.newsTimer invalidate];
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
    NSString *icon = enabled ? @"checkmark.seal.fill" : @"bolt.slash.fill";
    [self.jitStatusButton setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    // Not `enabled`: a disabled UIButton draws in UIControlStateDisabled, which ignores the
    // colours set above for UIControlStateNormal and greys the badge out exactly when it
    // should be green. This keeps the normal appearance and just stops taps.
    self.jitStatusButton.userInteractionEnabled = !enabled;
}

- (void)onEnableJITPressed {
    if (isJITEnabled(NO)) {
        return;
    }
    // Built-in JIT with nothing paired yet has only one thing to offer: the way to pair.
    if (SKBuiltinJIT.selected && !SKBuiltinJIT.hasPairingFile) {
        [self onJITSetup:self.jitStatusButton];
        return;
    }
    [SKBuiltinJIT requestJITWithFailure:^(NSString *message) {
      UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't enable JIT"
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"JIT Setup"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
                                                [self onJITSetup:self.jitStatusButton];
                                              }]];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
      [self presentViewController:alert animated:YES completion:nil];
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
    [btn setImage:[UIImage systemImageNamed:iconName] forState:UIControlStateNormal];
    btn.tintColor = UIColor.whiteColor;
    btn.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
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
    button.layer.cornerRadius = 6;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:34],
        [button.heightAnchor constraintEqualToConstant:30],
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
    self.ramFreeLabel.text = [NSString stringWithFormat:@"%d MB free of %d MB",
                              sk_ram_available_mb(), sk_ram_total_mb()];
}

- (void)onSegmentChanged:(UISegmentedControl *)sender {
    NSString *mode = (sender.selectedSegmentIndex == 1) ? @"Steam" : @"Web";
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:@"login_mode"];
}


- (void)onCrashReportingChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:SKReportingEnabledKey];
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
        BOOL isVMLog = [name hasPrefix:@"vmlog-"] || [name hasPrefix:@"vmout-"];
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

/**
 * The one JIT failure the pill cannot see. isJITEnabled() only checks that *a*
 * debugger is attached, so StikDebug attached without skapsule-jit.js assigned to
 * this bundle id looks identical to a working setup -- and the launch then dies on
 * an unserviced trap with no crash report to explain it. Say so plainly instead.
 */
- (void)warnIfJITTrapWentUnserviced {
    // viewDidAppear runs again after every modal dismiss and on returning from the game,
    // and the underlying check stays true for the whole launch -- so gate it here or the
    // alert re-appears every time.
    static BOOL warned = NO;
    if (warned) return;
    if (!SKPreviousRunDiedOnJITTrap()) return;
    warned = YES;
    [self showAlertWithTitle:@"JIT was not enabled"
                     message:@"The last launch stopped when the runtime asked for its JIT "
                             @"memory and nothing answered.\n\nIn StikDebug, import "
                             @"skapsule-jit.js and assign it to this app, then enable JIT "
                             @"again. A debugger attached without that script is not enough."];
}

#pragma mark - News

/**
 * Fills the home-screen card from the feed and, when it carries more than one event,
 * rotates through them as KnightLauncher does: a random first event, then the next every
 * SKNewsRotateInterval. The card stays hidden when there is nothing to show, and only
 * rotates while this screen is visible.
 */
- (void)fetchNews {
    __weak typeof(self) weakSelf = self;
    SKNewsFetch(^(NSArray<SKNewsItem *> *items) {
      typeof(self) self = weakSelf;
      if (!self || items.count == 0) return;
      self.newsItems = items;
      self.newsImages = [NSMutableDictionary dictionary];
      self.newsImageRequests = [NSMutableSet set];
      self.newsIndex = arc4random_uniform((uint32_t)items.count);
      self.newsCard.hidden = NO;
      [self showNewsItem:items[self.newsIndex] animated:NO];
      [self startNewsRotation];
    });
}

- (void)startNewsRotation {
    [self.newsTimer invalidate];
    self.newsTimer = nil;
    // The feed can land after the game screen was pushed; viewWillAppear restarts it.
    if (self.newsItems.count < 2 || !self.viewIfLoaded.window) return;
    __weak typeof(self) weakSelf = self;
    self.newsTimer = [NSTimer scheduledTimerWithTimeInterval:SKNewsRotateInterval
                                                     repeats:YES
                                                       block:^(NSTimer *timer) {
                                                         [weakSelf advanceNews];
                                                       }];
    [self loadNewsImage:self.newsItems[(self.newsIndex + 1) % self.newsItems.count]];
}

- (void)advanceNews {
    self.newsIndex = (self.newsIndex + 1) % self.newsItems.count;
    [self showNewsItem:self.newsItems[self.newsIndex] animated:YES];
    // Have the next banner ready by the time we rotate to it.
    [self loadNewsImage:self.newsItems[(self.newsIndex + 1) % self.newsItems.count]];
}

/// Fetches an event's banner into newsImages, then shows it if that event is still up.
/// Each URL is requested once per feed load, so a failing one is not retried every rotation.
- (void)loadNewsImage:(SKNewsItem *)item {
    if (!item.imageURL || [self.newsImageRequests containsObject:item.imageURL]) return;
    [self.newsImageRequests addObject:item.imageURL];
    __weak typeof(self) weakSelf = self;
    SKNewsFetchImage(item.imageURL, ^(UIImage *image) {
      typeof(self) self = weakSelf;
      if (!self || !image) return;
      self.newsImages[item.imageURL] = image;
      if (self.newsItems[self.newsIndex] == item) self.newsImageView.image = image;
    });
}

- (void)showNewsItem:(SKNewsItem *)item animated:(BOOL)animated {
    void (^apply)(void) = ^{
      self.newsLink = item.link;
      NSString *status = SKNewsStatusLabel(item.startsAt, item.endsAt);
      // Evergreen events carry no window; drop the chip rather than inventing a countdown.
      self.newsEndsInLabel.hidden = (status == nil);
      self.newsEndsInHeight.constant = status ? 18 : 0;
      self.newsEndsInLabel.text = status ? [NSString stringWithFormat:@"  %@  ", status] : @"";
      // KnightLauncher's CustomColors.WARNING, with dark text as on its badge.
      BOOL endingSoon = item.isEndingSoon;
      self.newsEndsInLabel.backgroundColor =
        endingSoon ? [UIColor colorWithRed:251 / 255.0 green:198 / 255.0 blue:91 / 255.0 alpha:1.0] : self.newsChipColor;
      self.newsEndsInLabel.textColor = endingSoon ? [UIColor colorWithWhite:0.125 alpha:1.0] : UIColor.whiteColor;
      self.newsTitleLabel.text = item.title;
      self.newsBodyLabel.text = item.body;
      self.newsImageView.image = item.imageURL ? self.newsImages[item.imageURL] : nil;
    };
    if (animated) {
        [UIView transitionWithView:self.newsCard
                          duration:0.35
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }
    [self loadNewsImage:item];
}

- (void)onNewsTapped {
    if (self.newsLink) [self openURLWithSafariFallback:self.newsLink];
}

#pragma mark - Update check

/// The dotted numeric part of a version: a leading "v" and any "-dev" / "-rc.1" / "+build" suffix
/// are dropped, so a suffix cannot add components or throw off the comparison.
static NSArray<NSString *> *SKVersionParts(NSString *version) {
    NSRange suffix = [version rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"]];
    if (suffix.location != NSNotFound) version = [version substringToIndex:suffix.location];
    if ([version hasPrefix:@"v"]) version = [version substringFromIndex:1];
    return [version componentsSeparatedByString:@"."];
}

/// Compares dotted numeric versions; a component that is not a number counts as 0.
/// Returns -1 if a < b, 1 if a > b, 0 if equal.
static int SKCompareVersions(NSString *a, NSString *b) {
    NSArray<NSString *> *ap = SKVersionParts(a);
    NSArray<NSString *> *bp = SKVersionParts(b);
    NSUInteger n = MAX(ap.count, bp.count);
    for (NSUInteger i = 0; i < n; i++) {
        int av = i < ap.count ? ap[i].intValue : 0;
        int bv = i < bp.count ? bp[i].intValue : 0;
        if (av != bv) return av < bv ? -1 : 1;
    }
    return 0;
}

/// A sideloaded app cannot install its own update, so iOS only notifies and links out.
/// The API allows 60 unauthenticated requests an hour per IP, so a good response is
/// cached for six hours rather than re-fetched on every launch.
- (void)checkForUpdate {
    [self checkForUpdateForced:NO completion:nil];
}

/// `force` skips the six-hour cache, for when the user asks to check. `completion`, if given,
/// runs on the main queue with the latest release ({version, url}), or nil if it could not be read.
- (void)checkForUpdateForced:(BOOL)force completion:(void (^)(NSDictionary *result))completion {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDate *lastCheck = [defaults objectForKey:@"update_check_time"];
    NSDictionary *cached = [defaults dictionaryForKey:@"update_check_result"];
    // A cached answer belongs to the version that fetched it: after an update it was written when
    // "latest" was something else, and would call a fresh install a development build.
    BOOL cacheIsCurrent = [[defaults stringForKey:@"update_check_app_version"] isEqualToString:@CONFIG_VERSION];
    if (!force && cacheIsCurrent && cached && lastCheck && -lastCheck.timeIntervalSinceNow < 6 * 60 * 60) {
        [self applyUpdateResult:cached];
        if (completion) completion(cached);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://api.github.com/repos/SKonstruct/"
                                            @"SKapsule-iOS/releases/latest"]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"SKapsule-iOS" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 10;

    __weak typeof(self) weakSelf = self;
    void (^fail)(void) = ^{
      if (!completion) return;
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil);
      });
    };
    [[NSURLSession.sharedSession
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || ((NSHTTPURLResponse *)response).statusCode != 200 || !data) { fail(); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:NSDictionary.class]) { fail(); return; }
            NSString *tag = json[@"tag_name"];
            NSString *htmlURL = json[@"html_url"];
            if (![tag isKindOfClass:NSString.class] || ![htmlURL isKindOfClass:NSString.class] ||
                tag.length == 0 || htmlURL.length == 0) {
                { fail(); return; }
            }
            NSDictionary *result = @{
                @"version" : [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag,
                @"url" : htmlURL,
            };
            [defaults setObject:result forKey:@"update_check_result"];
            [defaults setObject:NSDate.date forKey:@"update_check_time"];
            [defaults setObject:@CONFIG_VERSION forKey:@"update_check_app_version"];
            dispatch_async(dispatch_get_main_queue(), ^{
              [weakSelf applyUpdateResult:result];
              if (completion) completion(result);
            });
          }] resume];
}

/// The sidebar's Check for Updates. Unlike the quiet check at launch it always answers.
- (void)onCheckForUpdates {
    // A second tap while the first request is out would only stack another request.
    if (self.checkingForUpdates) return;
    self.checkingForUpdates = YES;
    UIButton *button = self.checkUpdatesButton;
    NSString *idleTitle = [button titleForState:UIControlStateNormal];
    [button setTitle:@"  Checking…" forState:UIControlStateNormal];
    button.enabled = NO;
    [self checkForUpdateForced:YES
                    completion:^(NSDictionary *result) {
                      self.checkingForUpdates = NO;
                      [button setTitle:idleTitle forState:UIControlStateNormal];
                      button.enabled = YES;
                      NSString *remote = result[@"version"];
                      NSString *url = result[@"url"];
                      if (![remote isKindOfClass:NSString.class] || ![url isKindOfClass:NSString.class]) {
                          [self showAlertWithTitle:@"Couldn't Check for Updates"
                                           message:@"Check your connection and try again. GitHub also limits "
                                                   @"how often a network can ask, so a busy network may need "
                                                   @"to wait a while."];
                          return;
                      }
                      int cmp = SKCompareVersions(@CONFIG_VERSION, remote);
                      if (cmp > 0) {
                          [self showAlertWithTitle:@"Development Build"
                                           message:[NSString stringWithFormat:@"You're on v%s, which is newer than "
                                                                              @"the latest release (v%@).",
                                                                              CONFIG_VERSION, remote]];
                          return;
                      }
                      if (cmp == 0) {
                          // A stale answer may have painted the title as a development build.
                          self.titleLabel.text = [NSString stringWithFormat:@"SKapsule v%s", CONFIG_VERSION];
                          self.titleLabel.textColor = UIColor.whiteColor;
                          [self showAlertWithTitle:@"Up to Date"
                                           message:[NSString stringWithFormat:@"You're on the latest version (v%s).",
                                                                              CONFIG_VERSION]];
                          return;
                      }
                      UIAlertController *alert = [UIAlertController
                          alertControllerWithTitle:@"Update Available"
                                           message:[NSString stringWithFormat:@"v%@ is out; you have v%s. Download "
                                                                              @"the new IPA from the release page "
                                                                              @"and install it the same way you "
                                                                              @"installed this one.",
                                                                              remote, CONFIG_VERSION]
                                    preferredStyle:UIAlertControllerStyleAlert];
                      [alert addAction:[UIAlertAction actionWithTitle:@"View Release"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction *action) {
                                                                [self openURLWithSafariFallback:url];
                                                              }]];
                      [alert addAction:[UIAlertAction actionWithTitle:@"Not Now"
                                                                style:UIAlertActionStyleCancel
                                                              handler:nil]];
                      [self presentViewController:alert animated:YES completion:nil];
                    }];
}

- (void)applyUpdateResult:(NSDictionary *)result {
    NSString *remote = result[@"version"];
    NSString *url = result[@"url"];
    if (![remote isKindOfClass:NSString.class] || ![url isKindOfClass:NSString.class]) return;

    int cmp = SKCompareVersions(@CONFIG_VERSION, remote);
    if (cmp > 0) {
        // Ahead of the newest release: a local build between tags.
        self.titleLabel.text = [NSString stringWithFormat:@"SKapsule v%s-dev", CONFIG_VERSION];
        self.titleLabel.textColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.23 alpha:1.0];
        self.updateButton.hidden = YES;
        return;
    }
    if (cmp == 0) {
        self.updateButton.hidden = YES;
        return;
    }

    self.updateURL = url;
    [self.updateButton setTitle:[NSString stringWithFormat:@"Update available - v%@", remote]
                       forState:UIControlStateNormal];
    self.updateButton.hidden = NO;
}

- (void)onUpdateTapped {
    if (self.updateURL) [self openURLWithSafariFallback:self.updateURL];
}

- (void)openURLWithSafariFallback:(NSString *)urlString {
    // SFSafariViewController raises for anything but http(s), and the string can come from the network.
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url.host.length || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return;
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

/// Opens the touch-control editor without launching the game.
- (void)onEditControls {
    // The sidebar is a sibling view, not a presented one, so it would still be sitting
    // there behind the editor when we come back.
    if (self.sidebarOpen) {
        [self toggleSidebar];
    }
    SKControlsEditorViewController *editor = [[SKControlsEditorViewController alloc] init];
    editor.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)onOpenFolder {
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docsDir) {
        [self showAlertWithTitle:@"Open Folder" message:@"Could not locate Documents directory."];
        return;
    }
    NSURL *docsURL = [NSURL fileURLWithPath:docsDir];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.folder"]]];
    picker.directoryURL = docsURL;
    picker.delegate = (id)self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)onGitHub {
    [self openURLWithSafariFallback:@"https://github.com/SKonstruct/SKapsule-iOS"];
}

- (void)onDonate {
    [self openURLWithSafariFallback:@"https://buymeacoffee.com/sirdankk"];
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

#pragma mark - JIT setup

/// The JIT walkthrough, as a bottom sheet: ways to get JIT, their steps, and the pairing.
- (void)onJITSetup:(UIView *)sender {
    [self presentViewController:[SKJITSetupViewController sheet] animated:YES completion:nil];
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
    NSDictionary *server = SKServers.selectedServer;
    // Steam tickets belong to Official; a private server gets the stock logon window instead.
    if (server) mode = SKLoginModeWeb;
    [self pointGameAtServer:server then:^{
      if (mode == SKLoginModeSteam) {
          [self onPlaySteam];
      } else {
          [self onPlayWeb];
      }
    }];
}

/// Writes the server's connection settings (Official's when nil) into the game's config.jar, then runs
/// @c proceed. Official is written too, so a game left pointing at a private server is healed before
/// anything of Official's (a Steam token) is sent; that write failing stops the launch.
- (void)pointGameAtServer:(NSDictionary *)server then:(void (^)(void))proceed {
    const char *homeEnv = getenv("SKAPSULE_HOME");
    NSString *jar = homeEnv ? [[[NSString stringWithUTF8String:homeEnv] stringByAppendingPathComponent:@"sk"]
                                  stringByAppendingPathComponent:@"code/config.jar"]
                            : nil;
    [self setButtonsEnabled:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSError *error = nil;
      BOOL ok = NO;
      if (jar) {
          [SKModManager preservePristineCodeJarNamed:@"config.jar"];
          ok = [SKServers applyServer:server toConfigJar:jar error:&error];
      }
      BOOL updatePending = ok && server && [SKServers updatePendingForGameAtPath:[jar stringByDeletingLastPathComponent].stringByDeletingLastPathComponent];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self setButtonsEnabled:YES];
        BOOL notInstalled = !ok && jar && error.code == 1;
        if (updatePending) {
            [self showAlertWithTitle:@"Servers"
                             message:@"The game has an update. Select Official and launch once so it updates, "
                                     @"then connect to this server."];
        } else if (ok || (notInstalled && !server)) {
            // Not installed yet and heading for Official: the first launch downloads Official's files.
            proceed();
        } else if (notInstalled) {
            [self showAlertWithTitle:@"Servers"
                             message:@"Launch the game once on Official first, so its files are downloaded, "
                                     @"then connect to this server."];
        } else {
            [self showAlertWithTitle:@"Servers"
                             message:[NSString stringWithFormat:@"Couldn't point the game at this server: %@",
                                                                error.localizedDescription ?: @"unknown error"]];
        }
      });
    });
}

/// The picker above the Web/Steam switch: a split control, the server name (tap to choose) and
/// an action (add when Official is selected, edit for a private server).
- (UIView *)makeServerSelector {
    UIColor *dim = [UIColor colorWithWhite:0.6 alpha:1.0];
    UIView *box = [[UIView alloc] init];
    box.layer.cornerRadius = 24;
    box.layer.borderWidth = 1;
    box.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    box.clipsToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *pick = [UIButton buttonWithType:UIButtonTypeCustom];
    pick.translatesAutoresizingMaskIntoConstraints = NO;
    pick.isAccessibilityElement = YES;
    pick.accessibilityTraits = UIAccessibilityTraitButton;
    pick.accessibilityHint = @"Choose a server";
    // A dropdown: the menu opens from the control itself (rebuilt on every open, so it is never stale).
    pick.showsMenuAsPrimaryAction = YES;
    pick.menu = [UIMenu menuWithChildren:@[ [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
                 completion([self serverMenuItems]);
               }] ]];
    [pick addTarget:self action:@selector(onServerPickDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [pick addTarget:self
                  action:@selector(onServerPickUp:)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel |
                         UIControlEventTouchDragExit | UIControlEventMenuActionTriggered];
    self.serverPick = pick;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"server.rack"]];
    icon.tintColor = dim;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    UILabel *caption = [[UILabel alloc] init];
    caption.text = @"Server";
    caption.font = [UIFont systemFontOfSize:11];
    caption.textColor = dim;
    self.serverNameLabel = [[UILabel alloc] init];
    self.serverNameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.serverNameLabel.textColor = UIColor.whiteColor;
    self.serverNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[ caption, self.serverNameLabel ]];
    labels.axis = UILayoutConstraintAxisVertical;
    labels.userInteractionEnabled = NO;
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chevron.tintColor = dim;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    for (UIView *v in @[ icon, labels, chevron ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.userInteractionEnabled = NO;
        [pick addSubview:v];
    }

    UIView *divider = [[UIView alloc] init];
    divider.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    self.serverActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.serverActionButton.tintColor = UIColor.whiteColor;
    self.serverActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.serverActionButton addTarget:self action:@selector(onServerAction) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[ pick, divider, self.serverActionButton ]) [box addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [box.widthAnchor constraintEqualToConstant:240], [box.heightAnchor constraintEqualToConstant:48],
        [pick.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [pick.topAnchor constraintEqualToAnchor:box.topAnchor],
        [pick.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [pick.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],
        [divider.widthAnchor constraintEqualToConstant:1], [divider.heightAnchor constraintEqualToConstant:24],
        [divider.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:self.serverActionButton.leadingAnchor],
        [self.serverActionButton.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [self.serverActionButton.topAnchor constraintEqualToAnchor:box.topAnchor],
        [self.serverActionButton.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [self.serverActionButton.widthAnchor constraintEqualToConstant:48],
        [icon.leadingAnchor constraintEqualToAnchor:pick.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:pick.centerYAnchor], [icon.widthAnchor constraintEqualToConstant:18],
        [labels.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [labels.centerYAnchor constraintEqualToAnchor:pick.centerYAnchor],
        [labels.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-6],
        [chevron.trailingAnchor constraintEqualToAnchor:pick.trailingAnchor constant:-8],
        [chevron.centerYAnchor constraintEqualToAnchor:pick.centerYAnchor], [chevron.widthAnchor constraintEqualToConstant:18],
    ]];
    return box;
}

- (void)onServerPickDown:(UIControl *)pick {
    pick.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)onServerPickUp:(UIControl *)pick {
    pick.backgroundColor = UIColor.clearColor;
}

/// The "Fight alongside ~N other Spiral Knights!" subtitle, or nil until a count has arrived.
- (nullable NSString *)playerCountText {
    NSInteger total = (NSInteger)roundf(self.liveSteamPlayers * kPlayerEstimateMult) +
                      (NSInteger)roundf(self.previewSteamPlayers * kPlayerEstimateMult);
    return total > 0 ? [NSString stringWithFormat:@"Fight alongside ~%ld other Spiral Knights!", (long)total] : nil;
}

/// Shows which server Play connects to. Steam sign-in belongs to Official, so the Web/Steam switch is
/// hidden for a private server and Play uses Web (onLaunchPressed); the saved choice is left alone.
- (void)showSelectedServer {
    NSDictionary *server = SKServers.selectedServer;
    NSString *name = server[SKServerNameKey] ?: @"Official";
    self.serverNameLabel.text = name;
    self.serverPick.accessibilityLabel = [NSString stringWithFormat:@"Server: %@", name];
    [self.serverActionButton setImage:[UIImage systemImageNamed:server ? @"pencil" : @"plus"] forState:UIControlStateNormal];
    self.serverActionButton.accessibilityLabel = server ? @"Edit server" : @"Add server";
    self.modeSegmentedControl.hidden = server != nil;
    // The player count is Official's.
    self.subtitleLabel.text = (server ? nil : [self playerCountText]) ?: @"Spiral Knights for iOS";
}

/// The pencil edits the selected private server; the plus (Official selected) adds one.
- (void)onServerAction {
    [self presentServerForm:SKServers.selectedServer draft:nil];
}

/// The dropdown's rows: Official and the saved servers (a check on the one in use), then Add Server.
/// The pencil beside the picker edits the selected one.
- (NSArray<UIMenuElement *> *)serverMenuItems {
    NSDictionary *selected = SKServers.selectedServer;
    __weak typeof(self) weakSelf = self;
    UIAction *official = [UIAction actionWithTitle:@"Official"
                                             image:[UIImage systemImageNamed:@"globe"]
                                        identifier:nil
                                           handler:^(UIAction *action) {
                                             [SKServers selectServerWithId:nil];
                                             [weakSelf showSelectedServer];
                                           }];
    official.state = selected ? UIMenuElementStateOff : UIMenuElementStateOn;
    NSMutableArray<UIMenuElement *> *rows = [NSMutableArray arrayWithObject:official];
    for (NSDictionary *server in SKServers.servers) {
        UIAction *row = [UIAction actionWithTitle:server[SKServerNameKey]
                                            image:[UIImage systemImageNamed:@"server.rack"]
                                       identifier:nil
                                          handler:^(UIAction *action) {
                                            [SKServers selectServerWithId:server[SKServerIdKey]];
                                            [weakSelf showSelectedServer];
                                          }];
        row.state = [server[SKServerIdKey] isEqualToString:selected[SKServerIdKey]] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [rows addObject:row];
    }
    UIAction *add = [UIAction actionWithTitle:@"Add Server…"
                                        image:[UIImage systemImageNamed:@"plus"]
                                   identifier:nil
                                      handler:^(UIAction *action) {
                                        [weakSelf presentServerForm:nil draft:nil];
                                      }];
    return @[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:rows],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ add ]],
    ];
}

/// Add a server, or edit or delete @c existing. @c draft holds what was typed when a previous try was rejected.
- (void)presentServerForm:(NSDictionary *)existing draft:(NSDictionary *)draft {
    NSDictionary *shown = draft ?: existing;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:existing ? @"Edit Server" : @"Add Server"
                         message:@"Leave the key and URLs blank to use Official's."
                  preferredStyle:UIAlertControllerStyleAlert];
    NSArray *fields = @[
        @[@"Name", SKServerNameKey], @[@"Address", SKServerHostKey], @[@"Port", SKServerPortKey],
        @[@"Public key (modulus#exponent)", SKServerPublicKeyKey], @[@"Client URL (optional)", SKServerClientURLKey],
        @[@"Content URL (optional)", SKServerContentURLKey],
        @[@"Username (optional, for quick login)", @"loginUser"],
        @[@"Password (optional)", @"loginPass"],
    ];
    NSDictionary *savedLogin = existing ? [SKCredentials loginForServerId:existing[SKServerIdKey]] : nil;
    for (NSArray *field in fields) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
          tf.placeholder = field[0];
          id value = shown[field[1]];
          if (!value && [field[1] isEqualToString:SKServerPortKey]) value = @47624;
          if ([field[1] isEqualToString:@"loginUser"]) value = draft ? draft[@"loginUser"] : savedLogin[@"username"];
          if ([field[1] isEqualToString:@"loginPass"]) {
              value = nil;
              tf.secureTextEntry = YES;
              if (savedLogin) tf.placeholder = @"New password (blank keeps it)";
          }
          tf.text = [value isKindOfClass:NSNumber.class] ? [value stringValue] : value;
          tf.autocorrectionType = UITextAutocorrectionTypeNo;
          tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
          tf.keyboardType = [field[1] isEqualToString:SKServerPortKey] ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
        }];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (existing) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
                                                  [SKServers deleteServerWithId:existing[SKServerIdKey]];
                                                  [SKCredentials deleteLoginForServerId:existing[SKServerIdKey]];
                                                  [self showSelectedServer];
                                                }]];
    }
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              NSArray<UITextField *> *tf = weakAlert.textFields;
                                              NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
                                              NSDictionary *candidate = @{
                                                  SKServerIdKey: existing[SKServerIdKey] ?: [SKServers newServerId],
                                                  SKServerNameKey: [tf[0].text stringByTrimmingCharactersInSet:ws] ?: @"",
                                                  SKServerHostKey: [tf[1].text stringByTrimmingCharactersInSet:ws] ?: @"",
                                                  SKServerPortKey: @([[tf[2].text stringByTrimmingCharactersInSet:ws] integerValue]),
                                                  SKServerPublicKeyKey: [tf[3].text stringByTrimmingCharactersInSet:ws] ?: @"",
                                                  SKServerClientURLKey: [tf[4].text stringByTrimmingCharactersInSet:ws] ?: @"",
                                                  SKServerContentURLKey: [tf[5].text stringByTrimmingCharactersInSet:ws] ?: @"",
                                              };
                                              NSString *loginUser = [tf[6].text stringByTrimmingCharactersInSet:ws] ?: @"";
                                              NSString *typedPass = tf[7].text ?: @"";
                                              NSString *loginPass = typedPass.length ? typedPass : (savedLogin[@"password"] ?: @"");
                                              // The draft keeps the username across a rejected try; the password is never kept.
                                              NSMutableDictionary *draftForRetry = [candidate mutableCopy];
                                              draftForRetry[@"loginUser"] = loginUser;
                                              SKServerProblem problem = [SKServers validateServer:candidate against:SKServers.servers];
                                              BOOL badLogin = (!loginUser.length && typedPass.length) || (loginUser.length && !loginPass.length) ||
                                                              [[loginUser stringByAppendingString:typedPass] containsString:@"\n"] ||
                                                              loginUser.length > 100 || typedPass.length > 100;
                                              if (problem != SKServerProblemNone || badLogin) {
                                                  [self presentServerProblem:problem retry:^{
                                                    [self presentServerForm:existing draft:draftForRetry];
                                                  }];
                                                  return;
                                              }
                                              [SKServers saveServer:candidate];
                                              if (loginUser.length) {
                                                  if (![SKCredentials saveUsername:loginUser password:loginPass forServerId:candidate[SKServerIdKey]]) {
                                                      [self showAlertWithTitle:@"Servers" message:@"Couldn't save the login on this device."];
                                                  }
                                              } else {
                                                  [SKCredentials deleteLoginForServerId:candidate[SKServerIdKey]];
                                              }
                                              // A server you just added or edited is the one you mean to play on.
                                              [SKServers selectServerWithId:candidate[SKServerIdKey]];
                                              [self showSelectedServer];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentServerProblem:(SKServerProblem)problem retry:(void (^)(void))retry {
    NSString *text = @"Check the server's details.";
    switch (problem) {
        case SKServerProblemName: text = @"Enter a name of up to 40 characters."; break;
        case SKServerProblemDuplicate: text = @"A server with that name already exists."; break;
        case SKServerProblemHost: text = @"Enter a valid server address."; break;
        case SKServerProblemPort: text = @"Enter a port from 1 to 65535."; break;
        case SKServerProblemKey: text = @"The key must look like modulus#exponent, in hex."; break;
        case SKServerProblemURL: text = @"URLs must start with http:// or https://."; break;
        case SKServerProblemNone: text = @"Enter both a username and a password, or leave both blank."; break;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Servers"
                                                                   message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              retry();
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setButtonsEnabled:(BOOL)enabled {
    self.btnLaunch.enabled = enabled;
    self.btnLaunch.alpha = enabled ? 1.0 : 0.4;
}

- (void)ensureRuntime {
    if ([SKInstaller isInstalled]) {
        NSLog(@"[Launcher] Runtime already installed");
        // Still refresh the jars: an update built from the same commit leaves the version
        // marker untouched, and the game would keep loading the old ones. Launch stays
        // disabled until it finishes -- starting the JVM mid-copy would load half a jar.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          [SKInstaller refreshStagedJars];
          dispatch_async(dispatch_get_main_queue(), ^{
            [self setButtonsEnabled:YES];
          });
        });
        return;
    }

    [self.spinner startAnimating];
    self.setupStatus.text = @"Setting up runtime…";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      BOOL ok = [SKInstaller installWithProgress:^(NSString *status) {
        dispatch_async(dispatch_get_main_queue(), ^{
          self.setupStatus.text = status;
        });
      }];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
        if (ok) {
            self.setupStatus.text = @"";
            [self setButtonsEnabled:YES];
        } else {
            self.setupStatus.text = @"Setup failed. Check your internet connection and relaunch.";
            SKReportFailure(@"runtime_install_failed", @"SKInstaller reported failure", nil);
        }
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
                                            message:@"Enter your Steam credentials. Your password goes straight to "
                                                    @"the game's Steam login and is not saved. A login token is "
                                                    @"stored encrypted on this device so you stay signed in."
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
                                alert.textFields[1].text = @"";
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
    // A private server's saved login, if it has one; the game withholds it unless it is set up for that server.
    NSDictionary *server = SKServers.selectedServer;
    if (mode == SKLoginModeWeb && server) {
        NSDictionary *login = [SKCredentials loginForServerId:server[SKServerIdKey]];
        gameVC.webUser = login[@"username"];
        gameVC.webPass = login[@"password"];
        gameVC.loginHost = [SKServers connectionPropertiesForServer:server][@"server_host"];
    }
    gameVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:gameVC animated:YES completion:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

/**
 * Steam only knows about Steam players, so both servers' counts are scaled by
 * kPlayerEstimateMult to account for standalone installs and then summed -- the
 * same arithmetic KnightLauncher does, so the two agree.
 */
- (void)fetchPlayerCount {
    static const int kAppIdLive = 99900;
    static const int kAppIdPreview = 99920;

    dispatch_group_t group = dispatch_group_create();
    __block NSInteger live = -1, preview = -1;

    for (int i = 0; i < 2; i++) {
        BOOL isLive = (i == 0);
        NSString *urlString =
          [NSString stringWithFormat:@"https://api.steampowered.com/ISteamUserStats/"
                                     @"GetNumberOfCurrentPlayers/v1/?appid=%d",
                                     isLive ? kAppIdLive : kAppIdPreview];
        dispatch_group_enter(group);
        [[NSURLSession.sharedSession
            dataTaskWithURL:[NSURL URLWithString:urlString]
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                     options:0
                                                                       error:nil];
                NSDictionary *resp = json[@"response"];
                if ([resp isKindOfClass:NSDictionary.class] && resp[@"player_count"]) {
                    NSInteger count = [resp[@"player_count"] integerValue];
                    if (isLive) live = count; else preview = count;
                }
            }
            dispatch_group_leave(group);
          }] resume];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
      typeof(self) self = weakSelf;
      if (!self) return;
      // Only give up when neither server answered; a dead preview leg must not
      // hide the live number.
      if (live < 0 && preview < 0) return;

      self.liveSteamPlayers = MAX(live, 0);
      self.previewSteamPlayers = MAX(preview, 0);
      // The count is Official's.
      NSString *countText = [self playerCountText];
      if (countText && !SKServers.selectedServer) {
          self.subtitleLabel.text = countText;
          // Once: this runs on every refresh, and stacked recognizers would fire together.
          if (!self.subtitleLabel.userInteractionEnabled) {
              self.subtitleLabel.userInteractionEnabled = YES;
              [self.subtitleLabel addGestureRecognizer:
                                    [[UITapGestureRecognizer alloc]
                                        initWithTarget:self
                                                action:@selector(onPlayerCountTapped)]];
          }
      }
    });
}

/// Explains where the number in the subtitle comes from.
- (void)onPlayerCountTapped {
    if (SKServers.selectedServer) return;
    NSInteger live = (NSInteger)roundf(self.liveSteamPlayers * 1.4f);
    NSInteger preview = (NSInteger)roundf(self.previewSteamPlayers * 1.4f);
    [self showAlertWithTitle:@"Players online"
                     message:[NSString stringWithFormat:
                                         @"This is an approximation based on the players "
                                         @"currently online through Steam, increased by 1.4x "
                                         @"to account for standalone players as well.\n\n"
                                         @"Live server: %ld on Steam, %ld estimated\n"
                                         @"Preview server: %ld on Steam, %ld estimated",
                                         (long)self.liveSteamPlayers, (long)live,
                                         (long)self.previewSteamPlayers, (long)preview]];
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
                                            if (!(error.code == 8 && [error.domain isEqualToString:@"SKModManagerDomain"]))
                                                SKReportFailure(@"mods_apply_failed",
                                                                error.localizedDescription, nil);
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
