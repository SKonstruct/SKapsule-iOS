#define GLES_SILENCE_DEPRECATION 1
#import "GameViewController.h"
#import "JavaLauncher.h"
#import "NativeBridge.h"
#import "SKInstaller.h"
#import "utils.h"

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

EAGLContext *gEAGLContext = nil;
CAEAGLLayer *gEAGLLayer = nil;
GLuint gRenderbuffer = 0;
GLuint gFramebuffer = 0;

@interface EAGLView : UIView
@end
@implementation EAGLView
+ (Class)layerClass { return [CAEAGLLayer class]; }
@end

typedef NS_ENUM(NSInteger, SKLoginMode);

@interface GameViewController ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UILabel *bootStatus;
@property (nonatomic, strong) UIView *bootOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL jvmKicked;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // GL surface
    self.surfaceView = [[EAGLView alloc] initWithFrame:self.view.bounds];
    self.surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.surfaceView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.surfaceView];

    gEAGLLayer = (CAEAGLLayer *)self.surfaceView.layer;
    gEAGLLayer.opaque = YES;
    gEAGLLayer.drawableProperties = @{
        kEAGLDrawablePropertyRetainedBacking: @(NO),
        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
    };

    gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!gEAGLContext) {
        gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    [EAGLContext setCurrentContext:gEAGLContext];

    glGenRenderbuffers(1, &gRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    [gEAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gEAGLLayer];

    glGenFramebuffers(1, &gFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gRenderbuffer);

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

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = UIColor.whiteColor;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.spinner startAnimating];
    [self.bootOverlay addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.bootOverlay.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.bootOverlay.centerYAnchor constant:-20],
        [self.bootStatus.centerXAnchor constraintEqualToAnchor:self.bootOverlay.centerXAnchor],
        [self.bootStatus.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:16],
        [self.bootStatus.leadingAnchor constraintEqualToAnchor:self.bootOverlay.leadingAnchor constant:32],
        [self.bootStatus.trailingAnchor constraintEqualToAnchor:self.bootOverlay.trailingAnchor constant:-32],
    ]];

    // Register NativeBridge callbacks
    __weak typeof(self) weakSelf = self;

    [SKNativeBridge setBootStatusHandler:^(NSString *message) {
        weakSelf.bootStatus.text = message;
    }];

    [SKNativeBridge setRenderReadyHandler:^{
        [UIView animateWithDuration:0.3 animations:^{
            weakSelf.bootOverlay.alpha = 0;
        } completion:^(BOOL finished) {
            [weakSelf.bootOverlay removeFromSuperview];
        }];
    }];

    [SKNativeBridge setPromptDeviceCodeHandler:^NSString *(BOOL prevWrong) {
        return [weakSelf showSteamGuardPromptWithTitle:@"Steam Guard"
            message:prevWrong
                ? @"Incorrect code. Enter your Steam Guard authenticator code:"
                : @"Enter your Steam Guard authenticator code:"];
    }];

    [SKNativeBridge setPromptEmailCodeHandler:^NSString *(NSString *email, BOOL prevWrong) {
        NSString *msg = prevWrong
            ? [NSString stringWithFormat:@"Incorrect code. Enter the code sent to %@:", email]
            : [NSString stringWithFormat:@"Enter the Steam Guard code sent to %@:", email];
        return [weakSelf showSteamGuardPromptWithTitle:@"Steam Guard (Email)" message:msg];
    }];
}

// Blocking Steam Guard prompt: dispatches to main thread, parks caller via semaphore
- (NSString *)showSteamGuardPromptWithTitle:(NSString *)title message:(NSString *)message {
    __block NSString *result = @"";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title message:message
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"Code";
            tf.keyboardType = UIKeyboardTypeNumberPad;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                result = alert.textFields.firstObject.text ?: @"";
                dispatch_semaphore_signal(sem);
            }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
            handler:^(UIAlertAction *action) {
                result = @"";
                dispatch_semaphore_signal(sem);
            }]];

        [self presentViewController:alert animated:YES completion:nil];
    });

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (gEAGLContext) {
        [EAGLContext setCurrentContext:gEAGLContext];
        glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
        [gEAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gEAGLLayer];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.jvmKicked) {
        self.jvmKicked = YES;
        [self startJVM];
    }
}

- (void)startJVM {
    BOOL isSteam = (self.loginMode == 1); // SKLoginModeSteam
    CGSize screenSize = self.view.bounds.size;
    CGFloat scale = UIScreen.mainScreen.scale;
    int w = (int)(screenSize.width * scale);
    int h = (int)(screenSize.height * scale);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int ret = launchJVM(self.steamUser ?: @"",
                            self.steamPass ?: @"",
                            isSteam, w, h);
        NSLog(@"[GameVC] JVM exited with code %d", ret);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.bootStatus.text = [NSString stringWithFormat:@"JVM exited (code %d)", ret];
            [self.spinner stopAnimating];
        });
    });
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
