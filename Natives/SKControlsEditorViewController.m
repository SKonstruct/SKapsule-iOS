#import "SKControlsEditorViewController.h"
#import "SKTouchControlOverlay.h"
#import "utils.h"

/**
 * Hosts the same SKTouchControlOverlay the game uses, in edit mode, over a plain backdrop
 * — so the controls can be arranged from the launcher instead of booting the JVM and
 * logging in first. In edit mode the overlay reports no input and touches neither GL nor
 * the JVM, so there is nothing here to stand in for the game.
 *
 * Landscape, because the layout is stored as percentages of the landscape game surface;
 * arranging it in portrait would put everything somewhere else in play. The overlay is
 * inset exactly as GameViewController insets it, for the same reason.
 */
@interface SKControlsEditorViewController ()
@property (nonatomic, strong) SKTouchControlOverlay *overlay;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIButton *doneButton;
@end

@implementation SKControlsEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // Stands in for the game: marks out the play area so the edges are visible.
    self.backdrop = [[UIView alloc] initWithFrame:CGRectZero];
    self.backdrop.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
    self.backdrop.layer.borderWidth = 1;
    self.backdrop.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    self.backdrop.layer.cornerRadius = 4;
    [self.view addSubview:self.backdrop];

    // No delegate: its one method reports a render-scale change to the live GL surface,
    // and there isn't one. The scale is still persisted by the overlay itself.
    self.overlay = [[SKTouchControlOverlay alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.overlay];

    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.doneButton setTitle:@"Done" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.doneButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.doneButton.backgroundColor = [UIColor colorWithRed:171.0 / 255.0
                                                      green:74.0 / 255.0
                                                       blue:129.0 / 255.0
                                                      alpha:1.0];
    self.doneButton.layer.cornerRadius = 12;
    self.doneButton.contentEdgeInsets = UIEdgeInsetsMake(8, 20, 8, 20);
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.doneButton addTarget:self
                        action:@selector(onDone)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.doneButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                                  constant:16],
        [self.doneButton.trailingAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                           constant:-16],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // Same rect the game gives the overlay, insets included -- otherwise a control parked
    // against an edge here lands somewhere else once the game is running.
    BOOL avoidEdges = [[NSUserDefaults.standardUserDefaults objectForKey:@"avoid_screen_edges"]
      boolValue];
    CGRect bounds = self.view.bounds;
    if (avoidEdges) {
        bounds = UIEdgeInsetsInsetRect(bounds, SKGameSafeAreaInsets(self.view));
    }
    self.backdrop.frame = CGRectInset(bounds, 4, 4);
    self.overlay.frame = bounds;

    // After the first layout: the overlay places its controls from its own bounds, so
    // entering edit mode any earlier would arrange them against an empty rect.
    if (!self.overlay.isEditing && !CGRectIsEmpty(bounds)) {
        [self.overlay toggleEditMode];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // iOS does not re-evaluate supportedInterfaceOrientations just because a modal was
    // presented, so ask for landscape outright -- the launcher behind us is portrait-only.
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *scene = self.view.window.windowScene;
    if (scene) {
        UIWindowSceneGeometryPreferencesIOS *landscape =
          [[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
        [scene requestGeometryUpdateWithPreferences:landscape errorHandler:nil];
    }
}

- (void)onDone {
    // Leaving edit mode is what writes the layout to disk, so it must happen before the
    // controller goes away -- and exactly once.
    if (self.overlay.isEditing) {
        [self.overlay toggleEditMode];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

@end
