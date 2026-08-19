#define GLES_SILENCE_DEPRECATION 1
#import "GameViewController.h"
#import "JavaLauncher.h"
#import "NativeBridge.h"
#import "SKInstaller.h"
#import "utils.h"
#import "SKTouchControlOverlay.h"
#import "SKKeyboardBridge.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <mach/mach.h>
#include <os/proc.h>
#import <GameController/GameController.h>

extern void sk_input_push_cursor(int x, int y);
extern void sk_input_push_framebuffer_size(int width, int height);
extern void sk_gl_request_resize(void);
extern void sk_input_push_mouse_button(int button, BOOL pressed);
extern void sk_input_push_key(int key, int action, int modifiers);
extern void sk_input_push_char(int codepoint);
extern void sk_gamepad_set_virtual_active(BOOL active);
extern void sk_gamepad_set_physical_active(BOOL active);
extern void sk_gamepad_set_button(int index, BOOL pressed);
extern void sk_gamepad_set_axis(int index, float value);

enum {
    SKGamepadButtonA,
    SKGamepadButtonB,
    SKGamepadButtonX,
    SKGamepadButtonY,
    SKGamepadButtonLeftBumper,
    SKGamepadButtonRightBumper,
    SKGamepadButtonBack,
    SKGamepadButtonStart,
    SKGamepadButtonGuide,
    SKGamepadButtonLeftThumb,
    SKGamepadButtonRightThumb,
    SKGamepadButtonDpadUp,
    SKGamepadButtonDpadRight,
    SKGamepadButtonDpadDown,
    SKGamepadButtonDpadLeft,
};

enum {
    SKGamepadAxisLeftX,
    SKGamepadAxisLeftY,
    SKGamepadAxisRightX,
    SKGamepadAxisRightY,
    SKGamepadAxisLeftTrigger,
    SKGamepadAxisRightTrigger,
};

static const CGFloat SKAxisDeadzone = 0.15;

EAGLContext *gEAGLContext = nil;
CAEAGLLayer *gEAGLLayer = nil;
GLuint gRenderbuffer = 0;
GLuint gFramebuffer = 0;
GLuint gDepthRenderbuffer = 0;

static int glfw_key_code(UIKeyboardHIDUsage usage) {
    if (usage >= UIKeyboardHIDUsageKeyboardA && usage <= UIKeyboardHIDUsageKeyboardZ) {
        return 'A' + (int)(usage - UIKeyboardHIDUsageKeyboardA);
    }
    if (usage >= UIKeyboardHIDUsageKeyboard1 && usage <= UIKeyboardHIDUsageKeyboard9) {
        return '1' + (int)(usage - UIKeyboardHIDUsageKeyboard1);
    }
    if (usage >= UIKeyboardHIDUsageKeyboardF1 && usage <= UIKeyboardHIDUsageKeyboardF12) {
        return 290 + (int)(usage - UIKeyboardHIDUsageKeyboardF1);
    }
    if (usage >= UIKeyboardHIDUsageKeypad1 && usage <= UIKeyboardHIDUsageKeypad9) {
        return 321 + (int)(usage - UIKeyboardHIDUsageKeypad1);
    }

    switch (usage) {
        case UIKeyboardHIDUsageKeyboard0: return '0';
        case UIKeyboardHIDUsageKeyboardSpacebar: return 32;
        case UIKeyboardHIDUsageKeyboardQuote: return 39;
        case UIKeyboardHIDUsageKeyboardComma: return 44;
        case UIKeyboardHIDUsageKeyboardHyphen: return 45;
        case UIKeyboardHIDUsageKeyboardPeriod: return 46;
        case UIKeyboardHIDUsageKeyboardSlash: return 47;
        case UIKeyboardHIDUsageKeyboardSemicolon: return 59;
        case UIKeyboardHIDUsageKeyboardEqualSign: return 61;
        case UIKeyboardHIDUsageKeyboardOpenBracket: return 91;
        case UIKeyboardHIDUsageKeyboardBackslash: return 92;
        case UIKeyboardHIDUsageKeyboardCloseBracket: return 93;
        case UIKeyboardHIDUsageKeyboardGraveAccentAndTilde: return 96;
        case UIKeyboardHIDUsageKeyboardEscape: return 256;
        case UIKeyboardHIDUsageKeyboardReturnOrEnter: return 257;
        case UIKeyboardHIDUsageKeypadEnter: return 257;
        case UIKeyboardHIDUsageKeyboardTab: return 258;
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: return 259;
        case UIKeyboardHIDUsageKeyboardInsert: return 260;
        case UIKeyboardHIDUsageKeyboardDeleteForward: return 261;
        case UIKeyboardHIDUsageKeyboardRightArrow: return 262;
        case UIKeyboardHIDUsageKeyboardLeftArrow: return 263;
        case UIKeyboardHIDUsageKeyboardDownArrow: return 264;
        case UIKeyboardHIDUsageKeyboardUpArrow: return 265;
        case UIKeyboardHIDUsageKeyboardPageUp: return 266;
        case UIKeyboardHIDUsageKeyboardPageDown: return 267;
        case UIKeyboardHIDUsageKeyboardHome: return 268;
        case UIKeyboardHIDUsageKeyboardEnd: return 269;
        case UIKeyboardHIDUsageKeyboardCapsLock: return 280;
        case UIKeyboardHIDUsageKeyboardScrollLock: return 281;
        case UIKeyboardHIDUsageKeypadNumLock: return 282;
        case UIKeyboardHIDUsageKeyboardPrintScreen: return 283;
        case UIKeyboardHIDUsageKeyboardPause: return 284;
        case UIKeyboardHIDUsageKeypadPeriod: return 330;
        case UIKeyboardHIDUsageKeypadSlash: return 331;
        case UIKeyboardHIDUsageKeypadAsterisk: return 332;
        case UIKeyboardHIDUsageKeypadHyphen: return 333;
        case UIKeyboardHIDUsageKeypadPlus: return 334;
        case UIKeyboardHIDUsageKeypad0: return 320;
        case UIKeyboardHIDUsageKeypadEqualSign: return 336;
        case UIKeyboardHIDUsageKeyboardLeftShift: return 340;
        case UIKeyboardHIDUsageKeyboardLeftControl: return 341;
        case UIKeyboardHIDUsageKeyboardLeftAlt: return 342;
        case UIKeyboardHIDUsageKeyboardLeftGUI: return 343;
        case UIKeyboardHIDUsageKeyboardRightShift: return 344;
        case UIKeyboardHIDUsageKeyboardRightControl: return 345;
        case UIKeyboardHIDUsageKeyboardRightAlt: return 346;
        case UIKeyboardHIDUsageKeyboardRightGUI: return 347;
        default: return -1;
    }
}

static int glfw_modifiers(UIKeyModifierFlags flags) {
    int modifiers = 0;
    if (flags & UIKeyModifierShift) modifiers |= 0x0001;
    if (flags & UIKeyModifierControl) modifiers |= 0x0002;
    if (flags & UIKeyModifierAlternate) modifiers |= 0x0004;
    if (flags & UIKeyModifierCommand) modifiers |= 0x0008;
    if (flags & UIKeyModifierAlphaShift) modifiers |= 0x0010;
    return modifiers;
}

static void push_characters(NSString *characters) {
    for (NSUInteger index = 0; index < characters.length; index++) {
        unichar character = [characters characterAtIndex:index];
        if (character < 0x20 || character == 0x7F) continue;
        int codepoint = character;
        if (CFStringIsSurrogateHighCharacter(character) && index + 1 < characters.length) {
            unichar low = [characters characterAtIndex:index + 1];
            if (CFStringIsSurrogateLowCharacter(low)) {
                codepoint = (int)CFStringGetLongCharacterForSurrogatePair(character, low);
                index++;
            }
        }
        sk_input_push_char(codepoint);
    }
}

static BOOL push_key_event(UIKey *key, int action) {
    if (!key) return NO;
    int glfwKey = glfw_key_code(key.keyCode);
    if (glfwKey >= 0) sk_input_push_key(glfwKey, action, glfw_modifiers(key.modifierFlags));
    if (action != 0 && key.characters.length > 0) push_characters(key.characters);
    return glfwKey >= 0 || key.characters.length > 0;
}

@interface EAGLView : UIView
@property (nonatomic, weak) GameViewController *inputDelegate;
@end
@implementation EAGLView
+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputDelegate touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputDelegate touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputDelegate touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputDelegate touchesCancelled:touches withEvent:event];
}
@end

typedef NS_ENUM(NSInteger, SKLoginMode);

@interface GameViewController () <SKTouchControlOverlayDelegate>
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) SKTouchControlOverlay *touchControls;
@property (nonatomic, strong) UIButton *editLayoutButton;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) SKKeyboardBridge *keyboardBridge;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, assign) CGFloat renderScaleFactor;
@property (nonatomic, strong) UILabel *bootStatus;
@property (nonatomic, strong) UIView *bootOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITouch *primaryTouch;
@property (nonatomic, assign) BOOL jvmKicked;
@property (nonatomic, strong) UIAlertController *jitWaitAlert;
@property (nonatomic, assign) BOOL jitWaitCancelled;
@property (nonatomic, strong) NSTimer *heapWatchdog;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // GL surface
    EAGLView *surfaceView = [[EAGLView alloc] initWithFrame:self.view.bounds];
    surfaceView.inputDelegate = self;
    self.surfaceView = surfaceView;
    self.surfaceView.autoresizingMask = UIViewAutoresizingNone;
    self.surfaceView.backgroundColor = UIColor.blackColor;
    self.surfaceView.multipleTouchEnabled = YES;
    [self.view addSubview:self.surfaceView];

    gEAGLLayer = (CAEAGLLayer *)self.surfaceView.layer;
    gEAGLLayer.opaque = YES;
    // Render scale is a framebuffer divisor: render smaller and let CoreAnimation upscale.
    // It has to be in place before the first renderbufferStorage below, or SK asks
    // nativeGetSurfaceSize during init, gets the full-resolution size, and lays its HUD out
    // for a framebuffer that no longer exists.
    //
    // Set it through the view's contentScaleFactor, never on the layer: UIKit re-applies
    // contentScaleFactor to layer.contentsScale whenever the view joins a window or lays
    // out, so a value written straight to the layer here is silently reset to the screen
    // scale and the game comes up at full resolution.
    self.renderScaleFactor = UIScreen.mainScreen.scale * [SKTouchLayout loadLayout].renderScale;
    self.surfaceView.contentScaleFactor = self.renderScaleFactor;
    NSLog(@"[gl] render scale %.2f -> contentsScale %.2f",
          [SKTouchLayout loadLayout].renderScale, self.renderScaleFactor);
    gEAGLLayer.drawableProperties =
        @{kEAGLDrawablePropertyRetainedBacking: @(NO), kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8};

    gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!gEAGLContext) {
        gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    [EAGLContext setCurrentContext:gEAGLContext];

    glGenRenderbuffers(1, &gRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);

    // Sized to the surface rather than the view: with "avoid screen edges" on they differ,
    // and controls laid out against the view would sit outside the game.
    self.touchControls = [[SKTouchControlOverlay alloc] initWithFrame:self.surfaceView.frame];
    self.touchControls.delegate = self;
    [self.view addSubview:self.touchControls];

    self.keyboardBridge = [[SKKeyboardBridge alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.keyboardBridge];

    self.editLayoutButton = [self chromeButtonWithTitle:@"⚙" action:@selector(onToggleEditLayout)];
    self.keyboardButton = [self chromeButtonWithTitle:@"Keyboard" action:@selector(onToggleKeyboard)];

    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(handlePointerHover:)];
    [self.surfaceView addGestureRecognizer:hover];
    [self setupGameControllers];
    [gEAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gEAGLLayer];

    glGenFramebuffers(1, &gFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gRenderbuffer);

    glGenRenderbuffers(1, &gDepthRenderbuffer);

    GLint width, height;
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);

    glBindRenderbuffer(GL_RENDERBUFFER, gDepthRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);

    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    self.lastDrawableSize = CGSizeMake(width, height);
    [EAGLContext setCurrentContext:nil];

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

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
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
      [UIApplication sharedApplication].idleTimerDisabled = YES;
      [UIView animateWithDuration:0.3
          animations:^{
            weakSelf.bootOverlay.alpha = 0;
          }
          completion:^(BOOL finished) {
            [weakSelf.bootOverlay removeFromSuperview];
          }];
    }];

    [SKNativeBridge setPromptDeviceCodeHandler:^(BOOL prevWrong) {
      [weakSelf showSteamGuardPromptWithTitle:@"Steam Guard"
                                      message:prevWrong ? @"Incorrect code. Enter your Steam Guard authenticator code:"
                                                        : @"Enter your Steam Guard authenticator code:"];
    }];

    [SKNativeBridge setPromptEmailCodeHandler:^(NSString *email, BOOL prevWrong) {
      NSString *msg = prevWrong ? [NSString stringWithFormat:@"Incorrect code. Enter the code sent to %@:", email]
                                : [NSString stringWithFormat:@"Enter the Steam Guard code sent to %@:", email];
      [weakSelf showSteamGuardPromptWithTitle:@"Steam Guard (Email)" message:msg];
    }];
}

- (void)setupGameControllers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(controllerConnected:) name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(controllerDisconnected:) name:GCControllerDidDisconnectNotification object:nil];
    for (GCController *controller in GCController.controllers) {
        [self registerController:controller];
    }
    [self refreshGamepadPresence];
}

- (void)controllerConnected:(NSNotification *)notification {
    [self registerController:notification.object];
    [self refreshGamepadPresence];
}

- (void)controllerDisconnected:(NSNotification *)notification {
    [self unregisterController:notification.object];
    [self refreshGamepadPresence];
}

- (void)refreshGamepadPresence {
    BOOL present = NO;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) {
            present = YES;
            break;
        }
    }
    sk_gamepad_set_physical_active(present);
}

- (void)registerController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (!gamepad) return;

    gamepad.leftShoulder.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonLeftBumper, pressed);
    };
    gamepad.rightShoulder.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonRightBumper, pressed);
    };
    gamepad.leftTrigger.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_axis(SKGamepadAxisLeftTrigger, value * 2.0f - 1.0f);
    };
    gamepad.rightTrigger.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_axis(SKGamepadAxisRightTrigger, value * 2.0f - 1.0f);
    };
    gamepad.buttonOptions.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonBack, pressed);
    };
    gamepad.buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonStart, pressed);
    };
    gamepad.buttonHome.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonGuide, pressed);
    };
    gamepad.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonA, pressed);
    };
    gamepad.buttonB.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonB, pressed);
    };
    gamepad.buttonX.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonX, pressed);
    };
    gamepad.buttonY.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonY, pressed);
    };
    gamepad.dpad.up.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonDpadUp, pressed);
    };
    gamepad.dpad.right.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonDpadRight, pressed);
    };
    gamepad.dpad.down.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonDpadDown, pressed);
    };
    gamepad.dpad.left.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonDpadLeft, pressed);
    };
    gamepad.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *stick, float xValue, float yValue) {
      sk_gamepad_set_axis(SKGamepadAxisLeftX, fabsf(xValue) < SKAxisDeadzone ? 0.0f : xValue);
      sk_gamepad_set_axis(SKGamepadAxisLeftY, fabsf(yValue) < SKAxisDeadzone ? 0.0f : yValue);
    };
    gamepad.rightThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *stick, float xValue, float yValue) {
      sk_gamepad_set_axis(SKGamepadAxisRightX, fabsf(xValue) < SKAxisDeadzone ? 0.0f : xValue);
      sk_gamepad_set_axis(SKGamepadAxisRightY, fabsf(yValue) < SKAxisDeadzone ? 0.0f : yValue);
    };
    gamepad.leftThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonLeftThumb, pressed);
    };
    gamepad.rightThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonRightThumb, pressed);
    };
}

- (void)unregisterController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    gamepad.leftShoulder.pressedChangedHandler = nil;
    gamepad.rightShoulder.pressedChangedHandler = nil;
    gamepad.leftTrigger.valueChangedHandler = nil;
    gamepad.rightTrigger.valueChangedHandler = nil;
    gamepad.buttonOptions.pressedChangedHandler = nil;
    gamepad.buttonMenu.pressedChangedHandler = nil;
    gamepad.buttonHome.pressedChangedHandler = nil;
    gamepad.buttonA.pressedChangedHandler = nil;
    gamepad.buttonB.pressedChangedHandler = nil;
    gamepad.buttonX.pressedChangedHandler = nil;
    gamepad.buttonY.pressedChangedHandler = nil;
    gamepad.dpad.up.pressedChangedHandler = nil;
    gamepad.dpad.right.pressedChangedHandler = nil;
    gamepad.dpad.down.pressedChangedHandler = nil;
    gamepad.dpad.left.pressedChangedHandler = nil;
    gamepad.leftThumbstick.valueChangedHandler = nil;
    gamepad.rightThumbstick.valueChangedHandler = nil;
    gamepad.leftThumbstickButton.pressedChangedHandler = nil;
    gamepad.rightThumbstickButton.pressedChangedHandler = nil;
}

/// Points -> framebuffer pixels. Read from the size recorded when the drawable was last
/// built, never by querying GL: this runs on the main thread for every touch move and
/// hover, while SK's render thread has gEAGLContext current. Two threads issuing commands
/// into one EAGLContext corrupts the driver's heap -- it is what made every libmalloc
/// "corruption of free block" abort land in AppleMetalGLRenderer.
- (CGFloat)pointToPixelScale {
    CGFloat width = self.surfaceView.bounds.size.width;
    if (width <= 0 || self.lastDrawableSize.width <= 0)
        return self.surfaceView.contentScaleFactor;
    return self.lastDrawableSize.width / width;
}

- (void)pushCursorAtPoint:(CGPoint)point {
    CGFloat scale = [self pointToPixelScale];
    sk_input_push_cursor((int)lround(point.x * scale), (int)lround(point.y * scale));
}

- (void)handlePointerHover:(UIHoverGestureRecognizer *)hover {
    [self pushCursorAtPoint:[hover locationInView:self.surfaceView]];
}

- (void)sendCursorForTouch:(UITouch *)touch {
    [self pushCursorAtPoint:[touch locationInView:self.surfaceView]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.primaryTouch) return;
    self.primaryTouch = touches.anyObject;
    [self sendCursorForTouch:self.primaryTouch];
    sk_input_push_mouse_button(0, YES);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.primaryTouch && [touches containsObject:self.primaryTouch]) {
        [self sendCursorForTouch:self.primaryTouch];
    }
}

- (void)endPrimaryTouch:(NSSet<UITouch *> *)touches {
    if (!self.primaryTouch || ![touches containsObject:self.primaryTouch]) return;
    [self sendCursorForTouch:self.primaryTouch];
    sk_input_push_mouse_button(0, NO);
    self.primaryTouch = nil;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endPrimaryTouch:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endPrimaryTouch:touches];
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) handled |= push_key_event(press.key, 1);
    if (!handled) [super pressesBegan:presses withEvent:event];
}

- (void)pressesChanged:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) handled |= push_key_event(press.key, 2);
    if (!handled) [super pressesChanged:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) handled |= push_key_event(press.key, 0);
    if (!handled) [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self pressesEnded:presses withEvent:event];
}

// Steam Guard prompt: alerts on main thread and submits asynchronously
- (void)showSteamGuardPromptWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
      tf.placeholder = @"Code";
      tf.keyboardType = UIKeyboardTypeNumberPad;
      tf.autocorrectionType = UITextAutocorrectionTypeNo;
      // Lets iOS offer the code straight from Messages, and password managers offer their
      // stored TOTP for the Steam entry.
      tf.textContentType = UITextContentTypeOneTimeCode;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Submit"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              NSString *code = alert.textFields.firstObject.text ?: @"";
                                              [SKNativeBridge submitCode:code];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
                                              [SKNativeBridge submitCode:@""];
                                            }]];

    [self presentViewController:alert animated:YES completion:nil];
}

/// UIKit's safe area is far too generous for a fullscreen game: in landscape it applies the
/// sensor-housing inset to *both* sides for symmetry and reserves the whole home-indicator
/// strip, which on an iPhone 15 Pro costs 118 of 2556 px horizontally and 63 px vertically
/// for nothing. Inset the sensor-housing edge only (so the surface runs right up to the
/// Dynamic Island with no gap) and give the other three edges a small corner allowance.
///
/// A rect inset by ~0.29 * cornerRadius exactly touches the corner arc; the Android port
/// uses radius/3 (0.33) and stays fully clear. We deliberately go under that, trading a few
/// clipped corner pixels for a lot of rendered ones -- which is what the edges are for.
- (UIEdgeInsets)gameSafeAreaInsets {
    // Along an edge's middle the display curve clips nothing -- only the corners do -- so
    // the long edges can be inset far less than the short ones. 8pt on the sides matches
    // what looks right on device; 2pt top and bottom keeps the corners from eating HUD
    // while reclaiming the strip that was going to waste.
    static const CGFloat kSideAllowance = 8.0f;
    static const CGFloat kEndAllowance = 2.0f;

    // UIKit's inset on the sensor-housing side clears the housing *and* adds its own
    // margin, which shows up as a visible gap between the Dynamic Island and the game.
    // That margin is ~11pt on Island devices (portrait: island ends ~48pt down, safe area
    // is 59pt). Give it back. Clamped so a device with a smaller inset can't go negative.
    static const CGFloat kHousingMargin = 11.0f;

    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) insets = self.view.safeAreaInsets;

    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    if (@available(iOS 13.0, *)) orientation = self.view.window.windowScene.interfaceOrientation;

    // UIInterfaceOrientation is defined against the *device* orientation it corresponds to,
    // which inverts the reading its name suggests: LandscapeRight == UIDeviceOrientation-
    // LandscapeLeft == home-button edge on the right, so the top of the device -- and with
    // it the sensor housing -- is on the LEFT. Confirmed on device; getting this backwards
    // paints the game under the Dynamic Island, which is the whole thing this avoids.
    CGFloat housing = MAX(MAX(insets.left, insets.right) - kHousingMargin, 0.0f);
    CGFloat left = kSideAllowance, right = kSideAllowance;
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        left = housing;
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        right = housing;
    } else {
        // Orientation not known yet (first layout pass): keep both sides clear rather than
        // guessing wrong and painting under the island.
        left = right = housing;
    }

    return UIEdgeInsetsMake(MAX(insets.top, kEndAllowance), left, kEndAllowance, right);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    BOOL avoidEdges = NO;
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"avoid_screen_edges"];
    if (val) {
        avoidEdges = [val boolValue];
    }

    CGRect bounds = self.view.bounds;
    if (avoidEdges) {
        bounds = UIEdgeInsetsInsetRect(bounds, [self gameSafeAreaInsets]);
    }
    self.surfaceView.frame = bounds;

    self.touchControls.frame = bounds;
    [self layoutChromeButtons];

    // Rebuilding the drawable is GL work on the main thread. That is only safe before SK's
    // render thread takes gEAGLContext; afterwards the two would be issuing commands into
    // one context, which corrupts the driver's heap. The scale is applied once at layer
    // creation (see viewDidLoad), so in practice there is nothing to do here after boot.
    // Re-assert on every layout: UIKit resets it from the screen scale behind our back.
    // Cheap, not a GL call, safe at any point in the session.
    if (self.renderScaleFactor > 0)
        self.surfaceView.contentScaleFactor = self.renderScaleFactor;

    if (gEAGLContext && !self.jvmKicked) {
        [EAGLContext setCurrentContext:gEAGLContext];
        CGFloat contentsScale = self.renderScaleFactor;

        // Rebuilding the renderbuffer re-enters layout, so bail unless the target actually
        // moved -- otherwise this spins forever.
        CGSize target = CGSizeMake(round(bounds.size.width * contentsScale), round(bounds.size.height * contentsScale));
        if (CGSizeEqualToSize(target, self.lastDrawableSize)) {
            [EAGLContext setCurrentContext:nil];
            return;
        }
        self.lastDrawableSize = target;

        glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
        [gEAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gEAGLLayer];

        if (gDepthRenderbuffer) {
            glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
            GLint width, height;
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);

            glBindRenderbuffer(GL_RENDERBUFFER, gDepthRenderbuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, width, height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
        }

        // Hand the context back: anything else running on the main thread must not inherit
        // the renderer's context.
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    if (!self.jvmKicked) {
        self.jvmKicked = YES;
        [self startJVM];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self resignFirstResponder];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

static BOOL skJITReady(void) {
    // isJITEnabled is TXM-aware: on iOS 26 TXM devices it only reports ready when
    // a debugger (StikJIT) running the JIT script is attached to service the VM's
    // brk codegen syscalls; a plain attached debugger (e.g. Xcode lldb) is not
    // enough there and would crash at BreakGetJITMapping.
    return isJITEnabled(NO);
}

- (void)startJVM {
    if (skJITReady() || [[NSUserDefaults standardUserDefaults] boolForKey:@"debug_skip_wait_jit"]) {
        [self launchJVMNow];
    } else {
        [self waitForJITThenLaunch];
    }
}

- (void)waitForJITThenLaunch {
    self.bootStatus.text = @"Waiting for JIT…";
    [self.spinner startAnimating];

    // Nudge StikJIT to enable JIT for us. On TXM devices you must first import
    // UniversalJIT26.js into StikJIT (Tools) and assign it to SKapsule; this URL
    // only triggers the enable. If StikJIT isn't installed the open is a no-op.
    NSURL *enableURL = skJITEnableURL();
    if (enableURL) {
        [[UIApplication sharedApplication] openURL:enableURL options:@{} completionHandler:nil];
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Waiting for JIT"
                         message:@"Spiral Knights needs JIT. Enable it for SKapsule in StikJIT (import + assign "
                                 @"UniversalJIT26.js once, then Enable JIT) and the game will continue automatically."
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
                                              __strong typeof(weakSelf) self = weakSelf;
                                              if (!self) return;
                                              self.jitWaitCancelled = YES;
                                              self.jitWaitAlert = nil;
                                              [self dismissViewControllerAnimated:YES completion:nil];
                                            }]];
    self.jitWaitAlert = alert;
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      while (!skJITReady()) {
          __strong typeof(weakSelf) self = weakSelf;
          if (!self || self.jitWaitCancelled) return;
          usleep(200 * 1000);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.jitWaitCancelled) return;
        [self.jitWaitAlert dismissViewControllerAnimated:YES completion:nil];
        self.jitWaitAlert = nil;
        [self launchJVMNow];
      });
    });
}

- (void)launchJVMNow {
    self.bootStatus.text = @"Launching Spiral Knights…";
    [self.spinner startAnimating];

    BOOL isSteam = (self.loginMode == 1);  // SKLoginModeSteam
    // Deliberately the unscaled screen scale: this sizes Cacio's virtual AWT screen
    // (dialogs, cursor), which must not shrink with the render-scale divisor.
    CGSize surfaceSize = self.surfaceView.frame.size;
    CGFloat scale = UIScreen.mainScreen.scale;
    int w = (int)(surfaceSize.width * scale);
    int h = (int)(surfaceSize.height * scale);

    [self startHeapWatchdog];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      int ret = launchJVM(self.steamUser ?: @"", self.steamPass ?: @"", isSteam, w, h);
      NSLog(@"[GameVC] JVM exited with code %d", ret);
      dispatch_async(dispatch_get_main_queue(), ^{
        self.bootStatus.text = [NSString stringWithFormat:@"JVM exited (code %d)", ret];
        [self.spinner stopAnimating];
      });
    });
}

// Three crashes in this port have been the same disease with a different victim each
// time (G1's nmethod table, the GL driver's object table, then libmalloc's own freelist,
// which trapped with "memory corruption of free block"). Walking the zone on a timer
// brackets the corruption to a 5s window so it can be correlated with the game log.
#pragma mark - Chrome buttons

static NSString *const kChromePrefsKey = @"game_chrome_prefs";
static const CGFloat kChromeDragSlop = 20.0f;

- (UIButton *)chromeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    button.layer.cornerRadius = 8;
    button.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button sizeToFit];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleChromeDrag:)];
    [button addGestureRecognizer:pan];

    [self.view addSubview:button];
    return button;
}

- (void)chromePositionForKey:(NSString *)key defaultX:(CGFloat)dx defaultY:(CGFloat)dy into:(CGPoint *)out {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kChromePrefsKey];
    NSNumber *x = prefs[[key stringByAppendingString:@"_x"]];
    NSNumber *y = prefs[[key stringByAppendingString:@"_y"]];
    out->x = x ? x.doubleValue : dx;
    out->y = y ? y.doubleValue : dy;
}

- (void)layoutChromeButtons {
    CGRect bounds = self.surfaceView.frame;
    if (CGRectIsEmpty(bounds)) return;

    CGFloat alpha = MAX(self.touchControls.layout.globalOpacity, 0.2);
    CGPoint fraction;

    [self chromePositionForKey:@"gear" defaultX:0.94 defaultY:0.06 into:&fraction];
    self.editLayoutButton.center = CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * fraction.x,
                                               CGRectGetMinY(bounds) + bounds.size.height * fraction.y);
    self.editLayoutButton.alpha = alpha;

    [self chromePositionForKey:@"kb" defaultX:0.78 defaultY:0.06 into:&fraction];
    self.keyboardButton.center = CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * fraction.x,
                                             CGRectGetMinY(bounds) + bounds.size.height * fraction.y);
    self.keyboardButton.alpha = alpha;
}

- (void)handleChromeDrag:(UIPanGestureRecognizer *)pan {
    // Only movable while laying out controls, so a mis-swipe during play still presses.
    if (!self.touchControls.isEditing) return;

    UIView *button = pan.view;
    CGPoint translation = [pan translationInView:self.view];
    if (hypot(translation.x, translation.y) < kChromeDragSlop && pan.state != UIGestureRecognizerStateEnded) return;

    if (pan.state == UIGestureRecognizerStateChanged) {
        button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
        [pan setTranslation:CGPointZero inView:self.view];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self persistChromePosition:button];
    }
}

- (void)persistChromePosition:(UIView *)button {
    CGRect bounds = self.surfaceView.frame;
    if (CGRectIsEmpty(bounds)) return;
    NSString *key = (button == self.editLayoutButton) ? @"gear" : @"kb";

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *prefs = [([defaults dictionaryForKey:kChromePrefsKey] ?: @{}) mutableCopy];
    prefs[[key stringByAppendingString:@"_x"]] = @((button.center.x - CGRectGetMinX(bounds)) / bounds.size.width);
    prefs[[key stringByAppendingString:@"_y"]] = @((button.center.y - CGRectGetMinY(bounds)) / bounds.size.height);
    [defaults setObject:prefs forKey:kChromePrefsKey];
}

- (void)onToggleEditLayout {
    [self.touchControls toggleEditMode];
    [self.editLayoutButton setTitle:self.touchControls.isEditing ? @"Done" : @"⚙" forState:UIControlStateNormal];
    [self.editLayoutButton sizeToFit];
    [self layoutChromeButtons];
}

- (void)onToggleKeyboard {
    [self.keyboardBridge toggle];
}

- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeRenderScale:(CGFloat)renderScale {
    self.renderScaleFactor = UIScreen.mainScreen.scale * renderScale;
    // contentScaleFactor is a UIKit property, not GL -- safe on the main thread, and it is
    // what CoreAnimation hands to renderbufferStorage:fromDrawable:.
    self.surfaceView.contentScaleFactor = self.renderScaleFactor;

    CGSize bounds = self.surfaceView.bounds.size;
    self.lastDrawableSize = CGSizeMake(round(bounds.width * self.renderScaleFactor),
                                       round(bounds.height * self.renderScaleFactor));

    // The rebuild itself has to happen on the thread that owns the context. Before the JVM
    // is up there is no render thread yet, so do it inline via the layout path instead.
    if (self.jvmKicked)
        sk_gl_request_resize();
    else
        [self.view setNeedsLayout];
}

- (void)startHeapWatchdog {
    if (self.heapWatchdog) return;
    __weak typeof(self) weakSelf = self;
    __block int tick = 0;
    // 1s while the scene loads -- every corruption crash so far has landed inside the
    // first ~10s of GL activity, and a 5s period barely sampled that window at all.
    self.heapWatchdog = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        repeats:YES
                                                          block:^(NSTimer *timer) {
        if (!weakSelf) { [timer invalidate]; return; }
        ++tick;
        BOOL settled = tick > 60;
        if (settled && (tick % 5)) return;

        task_vm_info_data_t info;
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            NSLog(@"[mem] t=%ds footprint=%lluMB available=%lluMB", tick,
                  (unsigned long long)(info.phys_footprint >> 20),
                  (unsigned long long)(os_proc_available_memory() >> 20));
        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"[mem] *** memory warning, available=%lluMB ***",
          (unsigned long long)(os_proc_available_memory() >> 20));
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (void)dealloc {
    [self.heapWatchdog invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (GCController *controller in GCController.controllers) {
        [self unregisterController:controller];
    }
    sk_gamepad_set_virtual_active(NO);
}

@end
