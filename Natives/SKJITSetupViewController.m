#import "SKJITSetupViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SKBuiltinJIT.h"
#import "SKJITAdvice.h"
#import "SKJITPairing.h"
#import "utils.h"

#pragma mark - Theme

static UIColor *SKAccent(void) {
    return [UIColor colorWithRed:171.0 / 255.0 green:74.0 / 255.0 blue:129.0 / 255.0 alpha:1.0];
}
static UIColor *SKBackdrop(void) { return [UIColor colorWithWhite:0.06 alpha:1.0]; }
static UIColor *SKCardFill(void) { return [UIColor colorWithWhite:1.0 alpha:0.07]; }
static UIColor *SKDimText(void) { return [UIColor colorWithWhite:0.64 alpha:1.0]; }

static UIFont *SKFont(UIFontTextStyle style, CGFloat size, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
}

static NSString *SKDeviceKind(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
}

/// Text with `**bold**` spans, the one bit of markup the steps use.
static NSAttributedString *SKStepText(NSString *text, UIColor *color) {
    UIFont *regular = SKFont(UIFontTextStyleSubheadline, 15, UIFontWeightRegular);
    UIFont *bold = SKFont(UIFontTextStyleSubheadline, 15, UIFontWeightSemibold);
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    [[text componentsSeparatedByString:@"**"] enumerateObjectsUsingBlock:^(NSString *part, NSUInteger i, BOOL *stop) {
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:part
                                          attributes:@{NSFontAttributeName : i % 2 ? bold : regular, NSForegroundColorAttributeName : color}]];
    }];
    return out;
}

#pragma mark - Row

/// A tappable card: icon tile, title, detail, and a chevron (or a check once that way is set up).
@interface SKJITRow : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail done:(BOOL)done;
@end

@implementation SKJITRow

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail done:(BOOL)done {
    if (!(self = [super init])) return nil;
    self.backgroundColor = SKCardFill();
    self.layer.cornerRadius = 16;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [SKAccent() colorWithAlphaComponent:0.18];
    tile.layer.cornerRadius = 10;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = SKAccent();
    icon.contentMode = UIViewContentModeCenter;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = SKFont(UIFontTextStyleBody, 16, UIFontWeightSemibold);
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.numberOfLines = 0;
    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.text = detail;
    detailLabel.font = SKFont(UIFontTextStyleFootnote, 13, UIFontWeightRegular);
    detailLabel.textColor = SKDimText();
    detailLabel.numberOfLines = 0;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, detailLabel ]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 3;

    UIImageView *accessory = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:done ? @"checkmark.circle.fill" : @"chevron.right"]];
    accessory.tintColor = done ? UIColor.systemGreenColor : [SKDimText() colorWithAlphaComponent:0.7];
    accessory.contentMode = UIViewContentModeCenter;
    accessory.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:done ? 18 : 13 weight:UIImageSymbolWeightSemibold];

    for (UIView *v in @[ tile, icon, text, accessory ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.userInteractionEnabled = NO;
    }
    [self addSubview:tile];
    [tile addSubview:icon];
    [self addSubview:text];
    [self addSubview:accessory];
    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [tile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [tile.widthAnchor constraintEqualToConstant:36], [tile.heightAnchor constraintEqualToConstant:36],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:14],
        [text.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
        [text.trailingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:-8],
        [accessory.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [accessory.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], [accessory.widthAnchor constraintEqualToConstant:20],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:64],
    ]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;
    self.accessibilityValue = [detail stringByAppendingString:done ? @". Set up." : @""];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = !self.enabled ? 0.5 : highlighted ? 0.6 : 1.0;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.5;
    if (!enabled) self.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
}

@end

#pragma mark - Page

@interface SKJITSetupViewController () <UIDocumentPickerDelegate>
@property (nonatomic) SKJITPage page;
@property (nonatomic, strong) UIStackView *content;
@property (nonatomic, strong) UIStackView *actions;
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) NSTimer *poll;
@property (nonatomic) BOOL lastJIT;
// Enable page.
@property (nonatomic) BOOL busy, prepared;
@property (nonatomic, copy) NSString *status, *error;
@end

@implementation SKJITSetupViewController

+ (UINavigationController *)sheet {
    return [self sheetStartingAt:SKJITPageChoose];
}

+ (UINavigationController *)sheetStartingAt:(SKJITPage)page {
    SKJITSetupViewController *root = [[self alloc] initWithPage:page];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.view.backgroundColor = SKBackdrop();
    nav.view.tintColor = SKAccent();
    nav.navigationBar.tintColor = SKAccent();
    UINavigationBarAppearance *bar = [[UINavigationBarAppearance alloc] init];
    [bar configureWithTransparentBackground];
    nav.navigationBar.standardAppearance = bar;
    nav.navigationBar.scrollEdgeAppearance = bar;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 28;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    return nav;
}

- (instancetype)initWithPage:(SKJITPage)page {
    if (!(self = [super init])) return nil;
    _page = page;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SKBackdrop();
    __weak typeof(self) weakSelf = self;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                      primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
                        [weakSelf dismissViewControllerAnimated:YES completion:nil];
                      }]];
    self.navigationItem.rightBarButtonItem.tintColor = SKAccent();
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.alwaysBounceVertical = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.content = [[UIStackView alloc] init];
    self.content.axis = UILayoutConstraintAxisVertical;
    self.content.spacing = 16;
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:self.content];

    self.actionBar = [[UIView alloc] init];
    self.actionBar.backgroundColor = SKBackdrop();
    self.actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *hairline = [[UIView alloc] init];
    hairline.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    self.actions = [[UIStackView alloc] init];
    self.actions.axis = UILayoutConstraintAxisVertical;
    self.actions.spacing = 8;
    self.actions.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionBar addSubview:hairline];
    [self.actionBar addSubview:self.actions];

    [self.view addSubview:scroll];
    [self.view addSubview:self.actionBar];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.actionBar.topAnchor],
        [self.content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [self.content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [self.content.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:22],
        [self.content.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-22],
        [self.actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.actionBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [hairline.topAnchor constraintEqualToAnchor:self.actionBar.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:self.actionBar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:self.actionBar.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [self.actions.topAnchor constraintEqualToAnchor:self.actionBar.topAnchor constant:12],
        [self.actions.leadingAnchor constraintEqualToAnchor:self.actionBar.leadingAnchor constant:22],
        [self.actions.trailingAnchor constraintEqualToAnchor:self.actionBar.trailingAnchor constant:-22],
        [self.actions.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.page == SKJITPagePair) [SKJITPairing reset];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reload)
                                               name:SKJITPairingDidChange
                                             object:nil];
    self.lastJIT = isJITEnabled(NO);
    __weak typeof(self) weakSelf = self;
    self.poll = [NSTimer scheduledTimerWithTimeInterval:1
                                                repeats:YES
                                                  block:^(NSTimer *t) {
                                                    BOOL on = isJITEnabled(NO);
                                                    if (on == weakSelf.lastJIT) return;
                                                    weakSelf.lastJIT = on;
                                                    if (on) weakSelf.busy = NO;
                                                    [weakSelf reload];
                                                  }];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.poll invalidate];
    self.poll = nil;
}

- (void)reload {
    for (UIStackView *stack in @[ self.content, self.actions ]) {
        for (UIView *v in stack.arrangedSubviews) {
            [stack removeArrangedSubview:v];
            [v removeFromSuperview];
        }
    }
    switch (self.page) {
        case SKJITPageChoose: [self buildChoose]; break;
        case SKJITPagePair: [self buildPair]; break;
        case SKJITPageImport: [self buildImport]; break;
        case SKJITPageConnect: [self buildConnect]; break;
        case SKJITPageEnable: [self buildEnable]; break;
        case SKJITPageStikDebug: [self buildStikDebug]; break;
        case SKJITPageTrollStore: [self buildTrollStore]; break;
        case SKJITPageJailbreak: [self buildJailbreak]; break;
    }
    self.actionBar.hidden = self.actions.arrangedSubviews.count == 0;
}

- (void)push:(SKJITPage)page {
    [self.navigationController pushViewController:[[SKJITSetupViewController alloc] initWithPage:page] animated:YES];
}

#pragma mark - Pieces

- (UIView *)cardAround:(UIView *)inner highlighted:(BOOL)highlighted {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = highlighted ? [SKAccent() colorWithAlphaComponent:0.14] : SKCardFill();
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    if (highlighted) {
        card.layer.borderWidth = 1;
        card.layer.borderColor = [SKAccent() colorWithAlphaComponent:0.4].CGColor;
    }
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return card;
}

- (UILabel *)labelText:(NSString *)text style:(UIFontTextStyle)style size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = SKFont(style, size, weight);
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (void)addHeader:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [SKAccent() colorWithAlphaComponent:0.18];
    tile.layer.cornerRadius = 16;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = SKAccent();
    icon.contentMode = UIViewContentModeCenter;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
    UIView *wrap = [[UIView alloc] init];
    for (UIView *v in @[ tile, icon ]) v.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:tile];
    [tile addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor], [tile.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [tile.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [tile.widthAnchor constraintEqualToConstant:56], [tile.heightAnchor constraintEqualToConstant:56],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    UILabel *titleLabel = [self labelText:title style:UIFontTextStyleTitle1 size:28 weight:UIFontWeightSemibold color:UIColor.whiteColor];
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.content addArrangedSubview:wrap];
    [self.content addArrangedSubview:titleLabel];
    [self.content addArrangedSubview:[self labelText:subtitle style:UIFontTextStyleSubheadline size:15 weight:UIFontWeightRegular color:SKDimText()]];
}

/// Numbered steps in one card; `steps` are @[text, @(done)], with **bold** spans.
- (void)addSteps:(NSArray<NSArray *> *)steps {
    UIStackView *list = [[UIStackView alloc] init];
    list.axis = UILayoutConstraintAxisVertical;
    list.spacing = 14;
    [steps enumerateObjectsUsingBlock:^(NSArray *step, NSUInteger i, BOOL *stop) {
      BOOL done = [step[1] boolValue];
      UILabel *badge = [[UILabel alloc] init];
      badge.textAlignment = NSTextAlignmentCenter;
      badge.layer.cornerRadius = 13;
      badge.layer.masksToBounds = YES;
      if (done) {
          badge.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.18];
          NSTextAttachment *check = [[NSTextAttachment alloc] init];
          check.image = [[UIImage systemImageNamed:@"checkmark"] imageWithTintColor:UIColor.systemGreenColor
                                                                       renderingMode:UIImageRenderingModeAlwaysOriginal];
          badge.attributedText = [NSAttributedString attributedStringWithAttachment:check];
      } else {
          badge.backgroundColor = [SKAccent() colorWithAlphaComponent:0.18];
          badge.text = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
          badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
          badge.textColor = SKAccent();
      }
      UILabel *text = [[UILabel alloc] init];
      text.attributedText = SKStepText(step[0], UIColor.whiteColor);
      text.numberOfLines = 0;
      text.adjustsFontForContentSizeCategory = YES;
      UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ badge, text ]];
      row.spacing = 12;
      row.alignment = UIStackViewAlignmentTop;
      [badge.widthAnchor constraintEqualToConstant:26].active = YES;
      [badge.heightAnchor constraintEqualToConstant:26].active = YES;
      [list addArrangedSubview:row];
    }];
    [self.content addArrangedSubview:[self cardAround:list highlighted:NO]];
}

- (void)addOutcome:(NSString *)text ok:(BOOL)ok {
    UIImageView *icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:ok ? @"checkmark.circle.fill" : @"exclamationmark.triangle.fill"]];
    icon.tintColor = ok ? UIColor.systemGreenColor : UIColor.systemRedColor;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *label = [self labelText:text style:UIFontTextStyleSubheadline size:14 weight:UIFontWeightMedium color:UIColor.whiteColor];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label ]];
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentTop;
    [self.content addArrangedSubview:[self cardAround:row highlighted:NO]];
}

- (void)addBusy:(NSString *)text {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = SKAccent();
    [spinner startAnimating];
    UILabel *label = [self labelText:text style:UIFontTextStyleSubheadline size:14 weight:UIFontWeightMedium color:UIColor.whiteColor];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ spinner, label ]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    [self.content addArrangedSubview:[self cardAround:row highlighted:YES]];
}

- (void)addNote:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = color;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *label = [self labelText:text style:UIFontTextStyleFootnote size:13 weight:UIFontWeightRegular color:color];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label ]];
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentTop;
    [self.content addArrangedSubview:row];
}

- (UIButton *)buttonTitle:(NSString *)title symbol:(nullable NSString *)symbol primary:(BOOL)primary destructive:(BOOL)destructive handler:(void (^)(void))handler {
    UIButtonConfiguration *config = primary ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration plainButtonConfiguration];
    config.title = title;
    if (symbol) {
        config.image = [UIImage systemImageNamed:symbol];
        config.imagePadding = 8;
    }
    if (primary) {
        config.baseBackgroundColor = SKAccent();
        config.baseForegroundColor = UIColor.whiteColor;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    } else {
        config.baseForegroundColor = destructive ? UIColor.systemRedColor : SKAccent();
    }
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *out = [attrs mutableCopy];
        out[NSFontAttributeName] = SKFont(UIFontTextStyleBody, primary ? 17 : 15, primary ? UIFontWeightBold : UIFontWeightMedium);
        return out;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config
                                           primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
                                             handler();
                                           }]];
    return button;
}

- (UIButton *)primary:(NSString *)title symbol:(nullable NSString *)symbol handler:(void (^)(void))handler {
    UIButton *b = [self buttonTitle:title symbol:symbol primary:YES destructive:NO handler:handler];
    [self.actions addArrangedSubview:b];
    return b;
}

- (UIButton *)plain:(NSString *)title destructive:(BOOL)destructive handler:(void (^)(void))handler {
    UIButton *b = [self buttonTitle:title symbol:nil primary:NO destructive:destructive handler:handler];
    [self.actions addArrangedSubview:b];
    return b;
}

- (SKJITRow *)addWay:(NSString *)title symbol:(NSString *)symbol detail:(NSString *)detail done:(BOOL)done enabled:(BOOL)enabled page:(SKJITPage)page {
    SKJITRow *row = [[SKJITRow alloc] initWithSymbol:symbol title:title detail:detail done:done];
    row.enabled = enabled;
    __weak typeof(self) weakSelf = self;
    [row addAction:[UIAction actionWithHandler:^(UIAction *a) {
           [weakSelf push:page];
         }]
        forControlEvents:UIControlEventTouchUpInside];
    [self.content addArrangedSubview:row];
    return row;
}

- (void)openURLString:(NSString *)url {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

static BOOL SKLocalDevVPNInstalled(void) {
    return [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"localdevvpn://"]];
}

/// LocalDevVPN switches the VPN on and returns here; without it installed, the App Store page.
- (void)openLocalDevVPN {
    [self openURLString:SKLocalDevVPNInstalled() ? @"localdevvpn://enable?scheme=skapsule"
                                                 : @"https://apps.apple.com/us/app/localdevvpn/id6755608044"];
}

- (NSString *)methodSummary {
    switch (SKBuiltinJIT.resolvedMethod) {
        case SKJITMethodBuiltin: return SKBuiltinJIT.method == SKJITMethodAutomatic ? @"Automatic (built-in)" : @"Built-in";
        case SKJITMethodStikDebug: return SKBuiltinJIT.method == SKJITMethodAutomatic ? @"Automatic (StikDebug app)" : @"StikDebug app";
        case SKJITMethodTrollStore: return @"TrollStore";
        case SKJITMethodJailbreak: return @"Jailbreak";
        default: return @"Automatic";
    }
}

#pragma mark - Choose

- (void)buildChoose {
    BOOL on = isJITEnabled(NO);
    NSString *device = SKDeviceKind();
    [self addHeader:@"bolt.fill"
              title:@"Turn on JIT"
           subtitle:[NSString stringWithFormat:@"The game's engine needs memory it can write and then run, which on iOS only an "
                                               @"attached debugger can grant. Choose how your %@ gets one.", device]];

    UILabel *state = [self labelText:[NSString stringWithFormat:@"%@\nMethod: %@", on ? @"JIT is on" : @"JIT is off", [self methodSummary]]
                               style:UIFontTextStyleSubheadline size:14 weight:UIFontWeightMedium color:UIColor.whiteColor];
    UIImageView *stateIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:on ? @"checkmark.seal.fill" : @"bolt.slash.fill"]];
    stateIcon.tintColor = on ? UIColor.systemGreenColor : SKDimText();
    [stateIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *stateRow = [[UIStackView alloc] initWithArrangedSubviews:@[ stateIcon, state ]];
    stateRow.spacing = 12;
    stateRow.alignment = UIStackViewAlignmentCenter;
    [self.content addArrangedSubview:[self cardAround:stateRow highlighted:on]];

    NSString *reason = SKBuiltinJIT.unavailableReason;
    NSString *source = SKBuiltinJIT.pairingSource;
    BOOL canPair = SKJITPairing.supported;
    [self addWay:[NSString stringWithFormat:@"Pair on this %@", device]
          symbol:@"iphone.radiowaves.left.and.right"
          detail:reason ?: !canPair ? @"Needs iOS 27 or later."
                 : [source isEqualToString:@"onDevice"] ? [NSString stringWithFormat:@"Paired on this %@.", device]
                 : @"No computer needed. Pairs from Settings in a minute."
            done:[source isEqualToString:@"onDevice"]
         enabled:!reason && canPair
            page:SKJITPagePair];
    [self addWay:@"Use a pairing file"
          symbol:@"doc.badge.plus"
          detail:reason ?: [source isEqualToString:@"imported"] ? @"Pairing file imported." : @"Import one made on a computer."
            done:[source isEqualToString:@"imported"]
         enabled:!reason
            page:SKJITPageImport];
    [self addWay:@"Use StikDebug"
          symbol:@"ant"
          detail:SKBuiltinJIT.stikDebugInstalled ? @"StikDebug is installed." : @"Enable JIT through the StikDebug app."
            done:SKBuiltinJIT.method == SKJITMethodStikDebug
         enabled:YES
            page:SKJITPageStikDebug];
    BOOL own = SKBuiltinJIT.canGrantOwnJIT;
    [self addWay:@"Use TrollStore"
          symbol:@"sparkles"
          detail:!own ? @"Works before iOS 26 only."
                 : SKBuiltinJIT.installedWithTrollStore ? @"Installed with TrollStore."
                 : @"For an install made with TrollStore."
            done:SKBuiltinJIT.method == SKJITMethodTrollStore
         enabled:own
            page:SKJITPageTrollStore];
    [self addWay:@"Use a jailbreak"
          symbol:@"lock.open"
          detail:!own ? @"Works before iOS 26 only."
                 : SKBuiltinJIT.debuggedAtLaunch ? @"JIT was already on when SKapsule opened."
                 : SKBuiltinJIT.jailbreakPresent ? @"A jailbreak was found."
                 : @"For a jailbreak that allows JIT in apps."
            done:SKBuiltinJIT.method == SKJITMethodJailbreak || SKBuiltinJIT.debuggedAtLaunch
         enabled:own
            page:SKJITPageJailbreak];

    __weak typeof(self) weakSelf = self;
    if (SKBuiltinJIT.hasPairingFile && !reason) {
        [self primary:@"Continue with the current pairing" symbol:@"arrow.right" handler:^{ [weakSelf push:SKJITPageConnect]; }];
    }
    if (SKBuiltinJIT.method != SKJITMethodAutomatic) {
        [self plain:@"Choose automatically" destructive:NO handler:^{
          SKBuiltinJIT.method = SKJITMethodAutomatic;
          [weakSelf reload];
        }];
    }
}

#pragma mark - Pair on this device

- (void)buildPair {
    NSString *device = SKDeviceKind();
    SKJITPairingPhase phase = SKJITPairing.phase;
    BOOL paired = phase == SKJITPairingPhasePaired;
    [self addHeader:@"iphone.radiowaves.left.and.right"
              title:[NSString stringWithFormat:@"Pair on this %@", device]
           subtitle:[NSString stringWithFormat:@"SKapsule pretends to be a computer on your Wi-Fi, and your %@ pairs with it the way "
                                               @"it would with a Mac.", device]];
    [self addSteps:@[
        @[ @"Turn on Wi-Fi, tap **Start pairing** below and allow Local Network access.", @(phase != SKJITPairingPhaseIdle) ],
        @[ @"Open **Settings › Privacy & Security › Developer Mode**, scroll down and tap **Pair with SKapsule**.",
           @(phase == SKJITPairingPhasePin || paired) ],
        @[ @"Enter the code SKapsule shows. It also appears in a banner and a notification, so you don't have to switch back.", @(paired) ],
        @[ @"Come back to SKapsule.", @(paired) ],
    ]];

    __weak typeof(self) weakSelf = self;
    switch (phase) {
        case SKJITPairingPhaseIdle:
            break;
        case SKJITPairingPhaseWaiting: {
            [self addBusy:[NSString stringWithFormat:@"Waiting for your %@…", device]];
            if (SKJITPairing.backgroundLimited) {
                [self addNote:@"This install can only wait about 30 seconds in the background, so go to Settings straight away."
                       symbol:@"exclamationmark.circle"
                        color:UIColor.systemOrangeColor];
            }
            break;
        }
        case SKJITPairingPhasePin: {
            NSString *pin = SKJITPairing.pin ?: @"";
            UILabel *hint = [self labelText:[NSString stringWithFormat:@"Enter this code on your %@", device]
                                      style:UIFontTextStyleSubheadline size:14 weight:UIFontWeightRegular color:SKDimText()];
            hint.textAlignment = NSTextAlignmentCenter;
            UILabel *code = [[UILabel alloc] init];
            code.attributedText = [[NSAttributedString alloc]
                initWithString:pin
                    attributes:@{
                        NSFontAttributeName : [UIFont monospacedSystemFontOfSize:40 weight:UIFontWeightBold],
                        NSKernAttributeName : @6,
                        NSForegroundColorAttributeName : UIColor.whiteColor,
                    }];
            code.textAlignment = NSTextAlignmentCenter;
            code.adjustsFontSizeToFitWidth = YES;
            NSMutableArray<NSString *> *digits = [NSMutableArray array];
            for (NSUInteger i = 0; i < pin.length; i++) [digits addObject:[pin substringWithRange:NSMakeRange(i, 1)]];
            code.accessibilityLabel = [NSString stringWithFormat:@"Pairing code %@", [digits componentsJoinedByString:@" "]];
            UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ hint, code ]];
            stack.axis = UILayoutConstraintAxisVertical;
            stack.spacing = 8;
            [self.content addArrangedSubview:[self cardAround:stack highlighted:YES]];
            break;
        }
        case SKJITPairingPhasePaired:
            [self addOutcome:[NSString stringWithFormat:@"Paired with %@", SKJITPairing.deviceName ?: device] ok:YES];
            break;
        case SKJITPairingPhaseFailed:
            [self addOutcome:SKJITPairing.failure ?: @"Pairing failed. Try again." ok:NO];
            break;
    }

    switch (phase) {
        case SKJITPairingPhaseIdle:
        case SKJITPairingPhaseFailed: {
            [self primary:@"Start pairing" symbol:@"dot.radiowaves.left.and.right" handler:^{ [SKJITPairing start]; }];
            break;
        }
        case SKJITPairingPhaseWaiting:
        case SKJITPairingPhasePin: {
            [self plain:@"Open Settings" destructive:NO handler:^{ [weakSelf openURLString:UIApplicationOpenSettingsURLString]; }];
            [self plain:@"Cancel pairing" destructive:YES handler:^{ [SKJITPairing cancel]; }];
            break;
        }
        case SKJITPairingPhasePaired: {
            [self primary:@"Continue" symbol:nil handler:^{ [weakSelf push:SKJITPageConnect]; }];
            break;
        }
    }
}

#pragma mark - Pairing file

- (void)buildImport {
    NSString *device = SKDeviceKind();
    BOOL have = [SKBuiltinJIT.pairingSource isEqualToString:@"imported"];
    [self addHeader:@"doc.badge.plus"
              title:@"Use a pairing file"
           subtitle:[NSString stringWithFormat:@"A pairing file made on a computer lets SKapsule talk to this %@ the same way.", device]];
    [self addSteps:@[
        @[ @"On a computer, make this device's pairing file with the **StikDebug pairing-file guide**.", @(have) ],
        @[ [NSString stringWithFormat:@"Save it to Files, or AirDrop it to this %@.", device], @(have) ],
        @[ @"Tap **Choose pairing file** and pick it.", @(have) ],
    ]];
    [self addNote:@"The pairing file stays in SKapsule's private storage and is only sent to its own helper."
           symbol:@"lock.fill"
            color:SKDimText()];
    if (self.error) [self addOutcome:self.error ok:NO];

    __weak typeof(self) weakSelf = self;
    if (have) {
        [self primary:@"Continue" symbol:nil handler:^{ [weakSelf push:SKJITPageConnect]; }];
        [self plain:@"Choose another file" destructive:NO handler:^{ [weakSelf choosePairingFile]; }];
    } else {
        [self primary:@"Choose pairing file" symbol:@"folder" handler:^{ [weakSelf choosePairingFile]; }];
    }
    [self plain:@"Open the pairing-file guide" destructive:NO handler:^{
      [weakSelf openURLString:@"https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md"];
    }];
}

- (void)choosePairingFile {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypePropertyList, UTTypeData ] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    self.error = [SKBuiltinJIT importPairingFileFromURL:urls.firstObject];
    // The picker handed us a private copy of a device credential; nothing else needs it.
    [NSFileManager.defaultManager removeItemAtURL:urls.firstObject error:nil];
    [self reload];
}

#pragma mark - LocalDevVPN

- (void)buildConnect {
    NSString *device = SKDeviceKind();
    [self addHeader:@"network.badge.shield.half.filled"
              title:@"Connect LocalDevVPN"
           subtitle:[NSString stringWithFormat:@"SKapsule's helper reaches this %@'s debugging service through a local VPN. "
                                               @"Nothing leaves your %@.", device, device]];
    [self addSteps:@[
        @[ @"Install **LocalDevVPN** from the App Store.", @(SKLocalDevVPNInstalled()) ],
        @[ @"Tap **Connect LocalDevVPN**. It switches the VPN on and comes straight back to SKapsule.", @NO ],
        @[ @"Leave it connected whenever you turn JIT on.", @NO ],
    ]];
    __weak typeof(self) weakSelf = self;
    [self primary:SKLocalDevVPNInstalled() ? @"Connect LocalDevVPN" : @"Get LocalDevVPN" symbol:nil handler:^{ [weakSelf openLocalDevVPN]; }];
    [self plain:@"It's connected" destructive:NO handler:^{ [weakSelf push:SKJITPageEnable]; }];
}

#pragma mark - Enable

- (void)buildEnable {
    BOOL attached = isJITEnabled(NO);
    [self addHeader:@"bolt.badge.checkmark"
              title:@"Turn on JIT"
           subtitle:@"The first check downloads and mounts Apple's Developer Disk Image, which can take a minute."];
    [self addSteps:@[
        @[ @"Tap **Check setup**. SKapsule checks LocalDevVPN and prepares the Developer Disk Image.", @(self.prepared || attached) ],
        @[ @"Tap **Enable JIT**. The helper attaches and the game can start.", @(attached) ],
    ]];

    __weak typeof(self) weakSelf = self;
    if (self.busy && !attached) {
        [self addBusy:self.status ?: @"Working…"];
    } else if (attached) {
        [self addOutcome:@"JIT is on. You can launch the game." ok:YES];
    } else if (self.error) {
        [self addOutcome:self.error ok:NO];
        SKJITConnectionProblem problem = SKJITProblemFromMessage(self.error);
        if (problem == SKJITProblemPairing) {
            [self plain:SKJITPairing.supported ? @"Pair again" : @"Import a new pairing file" destructive:NO handler:^{
              [weakSelf.navigationController popToRootViewControllerAnimated:NO];
              SKJITSetupViewController *root = weakSelf.navigationController.viewControllers.firstObject;
              [root push:SKJITPairing.supported ? SKJITPagePair : SKJITPageImport];
            }];
        }
        if (problem != SKJITProblemNone) [self plain:@"Connect LocalDevVPN" destructive:NO handler:^{ [weakSelf openLocalDevVPN]; }];
    } else if (self.status) {
        [self addOutcome:self.status ok:YES];
    }

    if (attached) {
        [self primary:@"Done" symbol:nil handler:^{ [weakSelf dismissViewControllerAnimated:YES completion:nil]; }];
    } else if (self.prepared) {
        UIButton *b = [self primary:@"Enable JIT" symbol:@"bolt.fill" handler:^{ [weakSelf enableNow]; }];
        b.enabled = !self.busy;
    } else {
        UIButton *b = [self primary:@"Check setup" symbol:nil handler:^{ [weakSelf checkSetup]; }];
        b.enabled = !self.busy;
    }
    if (!attached) {
        UIButton *reset = [self plain:@"Reset Developer Disk Image" destructive:YES handler:^{ [weakSelf resetDDI]; }];
        reset.enabled = !self.busy;
    }
}

- (void)checkSetup {
    self.busy = YES;
    self.error = nil;
    self.status = @"Checking LocalDevVPN and the Developer Disk Image…";
    [self reload];
    [SKBuiltinJIT perform:@"prepare"
               completion:^(BOOL ok, NSString *message) {
                 self.busy = NO;
                 self.prepared = ok;
                 self.status = ok ? message : nil;
                 self.error = ok ? nil : message;
                 [self reload];
               }];
}

- (void)enableNow {
    self.busy = YES;
    self.error = nil;
    self.status = @"Attaching… keep SKapsule open.";
    [self reload];
    [SKBuiltinJIT enableBuiltInWithFailure:^(NSString *message) {
      self.busy = NO;
      self.error = message;
      [self reload];
    }];
}

- (void)resetDDI {
    self.busy = YES;
    self.error = nil;
    self.status = @"Clearing the Developer Disk Image…";
    self.prepared = NO;
    [self reload];
    [SKBuiltinJIT perform:@"reset"
               completion:^(BOOL ok, NSString *message) {
                 self.busy = NO;
                 self.status = ok ? message : nil;
                 self.error = ok ? nil : message;
                 [self reload];
               }];
}

#pragma mark - StikDebug, TrollStore, jailbreak

/// Sets the method and goes back to the list, where the way now shows as done.
- (void)useMethod:(SKJITMethod)method {
    SKBuiltinJIT.method = method;
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)buildStikDebug {
    NSString *device = SKDeviceKind();
    [self addHeader:@"ant"
              title:@"Use StikDebug"
           subtitle:@"StikDebug is a separate app that attaches to SKapsule. SKapsule sends it the JIT script itself, so nothing "
                    @"needs configuring for SKapsule inside StikDebug."];
    [self addSteps:@[
        @[ @"Install **StikDebug**.", @(SKBuiltinJIT.stikDebugInstalled) ],
        @[ [NSString stringWithFormat:@"Import this %@'s pairing file into StikDebug.", device], @NO ],
        @[ @"Install and connect **LocalDevVPN**.", @(SKLocalDevVPNInstalled()) ],
        @[ @"Whenever the game starts, SKapsule opens StikDebug, which attaches and comes back.", @NO ],
    ]];
    __weak typeof(self) weakSelf = self;
    [self primary:@"Use StikDebug" symbol:nil handler:^{ [weakSelf useMethod:SKJITMethodStikDebug]; }];
    [self plain:@"Get StikDebug" destructive:NO handler:^{
      [weakSelf openURLString:@"https://github.com/StikDebug/StikDebug/releases/latest"];
    }];
}

- (void)buildTrollStore {
    NSString *device = SKDeviceKind();
    [self addHeader:@"sparkles"
              title:@"Use TrollStore"
           subtitle:@"TrollStore can enable JIT for apps it installed, with no pairing file, VPN or computer."];
    NSString *whenStarts = @"Whenever the game starts, SKapsule asks TrollStore to enable JIT. TrollStore reopens SKapsule, "
                           @"attaches for a moment and lets go, which leaves it allowed to run code it wrote.";
    [self addSteps:@[
        @[ @"Install SKapsule through TrollStore, on an iOS version TrollStore supports.", @(SKBuiltinJIT.installedWithTrollStore) ],
        @[ @"In TrollStore's settings, turn on **URL Scheme**. TrollStore ignores enable-jit requests without it.", @NO ],
        @[ whenStarts, @NO ],
    ]];
    if (!SKBuiltinJIT.canGrantOwnJIT) {
        [self addNote:[NSString stringWithFormat:@"This %@ runs iOS 26 or later, where JIT also needs a debugger that stays attached. "
                                                 @"TrollStore alone is not enough.", device]
               symbol:@"info.circle"
                color:UIColor.systemOrangeColor];
    }
    __weak typeof(self) weakSelf = self;
    UIButton *use = [self primary:@"Use TrollStore" symbol:nil handler:^{ [weakSelf useMethod:SKJITMethodTrollStore]; }];
    use.enabled = SKBuiltinJIT.canGrantOwnJIT;
}

- (void)buildJailbreak {
    NSString *device = SKDeviceKind();
    [self addHeader:@"lock.open"
              title:@"Use a jailbreak"
           subtitle:@"On a device jailbroken with Dopamine, JIT is a setting: the jailbreak marks every app as debugged when it "
                    @"opens, and a debugged app may run code it wrote. SKapsule needs nothing else."];
    [self addSteps:@[
        @[ @"Open Dopamine and go to its settings.", @(SKBuiltinJIT.jailbreakPresent) ],
        @[ @"Turn on **Allow JIT in Apps**.", @NO ],
        @[ @"Close SKapsule completely and open it again. The setting applies to apps as they start.", @(SKBuiltinJIT.debuggedAtLaunch) ],
    ]];
    if (SKBuiltinJIT.debuggedAtLaunch) {
        [self addNote:@"SKapsule was marked as debugged when it opened, so JIT is on." symbol:@"checkmark.circle.fill" color:UIColor.systemGreenColor];
    } else if (!SKBuiltinJIT.jailbreakPresent) {
        [self addNote:[NSString stringWithFormat:@"No jailbreak was found on this %@.", device] symbol:@"info.circle" color:SKDimText()];
    }
    if (!SKBuiltinJIT.canGrantOwnJIT) {
        [self addNote:@"On iOS 26 or later JIT also needs a debugger that stays attached, so a jailbreak setting alone is not enough."
               symbol:@"info.circle"
                color:UIColor.systemOrangeColor];
    }
    __weak typeof(self) weakSelf = self;
    UIButton *use = [self primary:@"Use the jailbreak" symbol:nil handler:^{ [weakSelf useMethod:SKJITMethodJailbreak]; }];
    use.enabled = SKBuiltinJIT.canGrantOwnJIT;
}

@end
