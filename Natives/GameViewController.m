#import "GameViewController.h"
#import "JavaLauncher.h"
#import "SKInstaller.h"
#import "utils.h"

#import <QuartzCore/QuartzCore.h>

@interface GameViewController ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UILabel *bootStatus;
@property (nonatomic, strong) UIView *bootOverlay;
@property (nonatomic, assign) BOOL jvmKicked;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // GL surface placeholder
    self.surfaceView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.surfaceView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.surfaceView];

    // Boot overlay (shown while getdown runs)
    self.bootOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.bootOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.bootOverlay.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.bootOverlay];

    self.bootStatus = [[UILabel alloc] init];
    self.bootStatus.text = @"Starting Java runtime…";
    self.bootStatus.textColor = UIColor.whiteColor;
    self.bootStatus.font = [UIFont systemFontOfSize:14];
    self.bootStatus.textAlignment = NSTextAlignmentCenter;
    self.bootStatus.numberOfLines = 0;
    self.bootStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bootOverlay addSubview:self.bootStatus];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = UIColor.whiteColor;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [self.bootOverlay addSubview:spinner];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:self.bootOverlay.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:self.bootOverlay.centerYAnchor constant:-20],
        [self.bootStatus.centerXAnchor constraintEqualToAnchor:self.bootOverlay.centerXAnchor],
        [self.bootStatus.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:16],
        [self.bootStatus.leadingAnchor constraintEqualToAnchor:self.bootOverlay.leadingAnchor constant:32],
        [self.bootStatus.trailingAnchor constraintEqualToAnchor:self.bootOverlay.trailingAnchor constant:-32],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.jvmKicked) {
        self.jvmKicked = YES;
        [self startJVM];
    }
}

- (void)startJVM {
    // Placeholder: in Phase 1 this will call launchJVM() with full args.
    // For Phase 0 we just show the boot overlay.
    NSLog(@"[GameVC] JVM launch stub (Phase 0). loginMode=%ld", (long)self.loginMode);
    self.bootStatus.text = @"JVM launch not yet implemented (Phase 0).\n"
        "Runtime is installed. Waiting for Phase 1.";
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

@end
