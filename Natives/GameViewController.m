#define GLES_SILENCE_DEPRECATION 1
#import "GameViewController.h"
#import "JavaLauncher.h"
#import "NativeBridge.h"
#import "SKBuiltinJIT.h"
#import "SKInstaller.h"
#import "SKKeyboardBridge.h"
#import "SKMouseButtons.h"
#import "SKReporter.h"
#import "SKLayoutLibrary.h"
#import "SKTouchControlOverlay.h"
#import "utils.h"

#import <GameController/GameController.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach.h>
#include <math.h>
#include <os/proc.h>

extern void sk_input_push_cursor(int x, int y);
extern void sk_input_push_framebuffer_size(int width, int height);
extern void sk_gl_request_resize(void);
extern int sk_gl_context_taken(void);
extern void sk_gl_set_drawable_size(int width, int height);
extern void sk_gl_set_gfx_config(int enabled, float scale, float sharpen, int hud, int nativeWidth, int nativeHeight);
extern uint64_t sk_gfx_frame_count(void);
#import "SKGfxSettings.h"
extern void sk_gl_reset_render_ready(void);
extern void sk_input_push_mouse_button(int button, BOOL pressed);
extern void sk_input_push_scroll(int ticks);
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
        case UIKeyboardHIDUsageKeyboard0:
            return '0';
        case UIKeyboardHIDUsageKeyboardSpacebar:
            return 32;
        case UIKeyboardHIDUsageKeyboardQuote:
            return 39;
        case UIKeyboardHIDUsageKeyboardComma:
            return 44;
        case UIKeyboardHIDUsageKeyboardHyphen:
            return 45;
        case UIKeyboardHIDUsageKeyboardPeriod:
            return 46;
        case UIKeyboardHIDUsageKeyboardSlash:
            return 47;
        case UIKeyboardHIDUsageKeyboardSemicolon:
            return 59;
        case UIKeyboardHIDUsageKeyboardEqualSign:
            return 61;
        case UIKeyboardHIDUsageKeyboardOpenBracket:
            return 91;
        case UIKeyboardHIDUsageKeyboardBackslash:
            return 92;
        case UIKeyboardHIDUsageKeyboardCloseBracket:
            return 93;
        case UIKeyboardHIDUsageKeyboardGraveAccentAndTilde:
            return 96;
        case UIKeyboardHIDUsageKeyboardEscape:
            return 256;
        case UIKeyboardHIDUsageKeyboardReturnOrEnter:
            return 257;
        case UIKeyboardHIDUsageKeypadEnter:
            return 257;
        case UIKeyboardHIDUsageKeyboardTab:
            return 258;
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace:
            return 259;
        case UIKeyboardHIDUsageKeyboardInsert:
            return 260;
        case UIKeyboardHIDUsageKeyboardDeleteForward:
            return 261;
        case UIKeyboardHIDUsageKeyboardRightArrow:
            return 262;
        case UIKeyboardHIDUsageKeyboardLeftArrow:
            return 263;
        case UIKeyboardHIDUsageKeyboardDownArrow:
            return 264;
        case UIKeyboardHIDUsageKeyboardUpArrow:
            return 265;
        case UIKeyboardHIDUsageKeyboardPageUp:
            return 266;
        case UIKeyboardHIDUsageKeyboardPageDown:
            return 267;
        case UIKeyboardHIDUsageKeyboardHome:
            return 268;
        case UIKeyboardHIDUsageKeyboardEnd:
            return 269;
        case UIKeyboardHIDUsageKeyboardCapsLock:
            return 280;
        case UIKeyboardHIDUsageKeyboardScrollLock:
            return 281;
        case UIKeyboardHIDUsageKeypadNumLock:
            return 282;
        case UIKeyboardHIDUsageKeyboardPrintScreen:
            return 283;
        case UIKeyboardHIDUsageKeyboardPause:
            return 284;
        case UIKeyboardHIDUsageKeypadPeriod:
            return 330;
        case UIKeyboardHIDUsageKeypadSlash:
            return 331;
        case UIKeyboardHIDUsageKeypadAsterisk:
            return 332;
        case UIKeyboardHIDUsageKeypadHyphen:
            return 333;
        case UIKeyboardHIDUsageKeypadPlus:
            return 334;
        case UIKeyboardHIDUsageKeypad0:
            return 320;
        case UIKeyboardHIDUsageKeypadEqualSign:
            return 336;
        case UIKeyboardHIDUsageKeyboardLeftShift:
            return 340;
        case UIKeyboardHIDUsageKeyboardLeftControl:
            return 341;
        case UIKeyboardHIDUsageKeyboardLeftAlt:
            return 342;
        case UIKeyboardHIDUsageKeyboardLeftGUI:
            return 343;
        case UIKeyboardHIDUsageKeyboardRightShift:
            return 344;
        case UIKeyboardHIDUsageKeyboardRightControl:
            return 345;
        case UIKeyboardHIDUsageKeyboardRightAlt:
            return 346;
        case UIKeyboardHIDUsageKeyboardRightGUI:
            return 347;
        default:
            return -1;
    }
}

static int glfw_modifiers(UIKeyModifierFlags flags) {
    int modifiers = 0;
    if (flags & UIKeyModifierShift)
        modifiers |= 0x0001;
    if (flags & UIKeyModifierControl)
        modifiers |= 0x0002;
    if (flags & UIKeyModifierAlternate)
        modifiers |= 0x0004;
    if (flags & UIKeyModifierCommand)
        modifiers |= 0x0008;
    if (flags & UIKeyModifierAlphaShift)
        modifiers |= 0x0010;
    return modifiers;
}

static void push_characters(NSString *characters) {
    for (NSUInteger index = 0; index < characters.length; index++) {
        unichar character = [characters characterAtIndex:index];
        if (character < 0x20 || character == 0x7F)
            continue;
        if (character >= 0xF700 && character <= 0xF8FF)
            continue;  // UIKeyInput* arrows/F-keys
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

/// `emitCharacters` is NO for pressesChanged, which fires when an already-held key's
/// properties change (force, modifier flags) rather than on a repeat -- emitting there
/// types the character a second time.
static BOOL push_key_event(UIKey *key, int action, BOOL emitCharacters) {
    if (!key)
        return NO;
    int glfwKey = glfw_key_code(key.keyCode);
    if (glfwKey >= 0)
        sk_input_push_key(glfwKey, action, glfw_modifiers(key.modifierFlags));
    if (emitCharacters && action != 0 && key.characters.length > 0)
        push_characters(key.characters);
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
/// Presets and export/import for the in-game editor (the standalone editor has its own).
@property (nonatomic, strong) SKLayoutLibrary *layoutLibrary;
@property (nonatomic, strong) UIButton *editLayoutButton;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) SKKeyboardBridge *keyboardBridge;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, assign) CGFloat renderScaleFactor;
@property (nonatomic, assign) CGFloat layoutRenderScale;  // the resolution slider's value
@property (nonatomic, assign) BOOL gfxOffscreen;          // the offscreen pass is on (see SKGfxSettings.h)
@property (nonatomic, strong) UIView *fpsPill;
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) NSTimer *fpsTimer;
@property (nonatomic, assign) uint64_t fpsLastFrames;
@property (nonatomic, assign) NSTimeInterval fpsLastTime;
@property (nonatomic, strong) UILabel *bootStatus;
@property (nonatomic, strong) UIView *bootOverlay;
@property (nonatomic, strong) UIView *signInOverlay;
@property (nonatomic, strong) UIImageView *signInQR;
@property (nonatomic, strong) UIStackView *signInRow;
@property (nonatomic, strong) UIStackView *signInText;
/// Raised when the portrait sign-in phase ends: the drawable still has the portrait size.
@property (nonatomic, assign) BOOL resyncDrawableAfterPortrait;
@property (nonatomic, strong) UILabel *signInBody;
@property (nonatomic, copy) NSString *signInURL;
@property (nonatomic, assign) UIBackgroundTaskIdentifier signInTask;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITouch *primaryTouch;
@property (nonatomic, assign) BOOL jvmKicked;
@property (nonatomic, strong) UIAlertController *jitWaitAlert;
@property (nonatomic, assign) BOOL jitWaitCancelled;
@property (nonatomic, strong) NSTimer *heapWatchdog;
@property (nonatomic, strong) NSTimer *bootWatchdog;
@property (nonatomic, strong) UIButton *buttonsToggle;
@property (nonatomic, assign) int primaryTouchButton;
/// Mouse buttons last reported down (bit 0 left, 1 right, 2 middle); a finger leaves this 0.
@property (nonatomic, assign) unsigned pointerButtons;
@property (nonatomic, assign) BOOL primaryTouchIsPointer;
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
    self.layoutRenderScale = [SKTouchLayout loadLayout].renderScale;
    [self applyGfxConfig];
    self.surfaceView.contentScaleFactor = self.renderScaleFactor;
    NSLog(@"[gl] render scale %.2f -> contentsScale %.2f%@", self.layoutRenderScale, self.renderScaleFactor,
          self.gfxOffscreen ? @" (offscreen pass)" : @"");
    gEAGLLayer.drawableProperties =
        @{kEAGLDrawablePropertyRetainedBacking: @(NO), kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8};

    // The flag latches once per process; a second game launch would otherwise skip
    // the render-ready callback and leave the boot overlay up forever.
    sk_gl_reset_render_ready();
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
    // The handler is what reveals the panel's "Layouts…" button.
    self.layoutLibrary = [[SKLayoutLibrary alloc] initWithPresenter:self overlay:self.touchControls];
    __weak typeof(self) weakLibraryOwner = self;
    self.touchControls.layoutLibraryHandler = ^{ [weakLibraryOwner.layoutLibrary show]; };

    self.keyboardBridge = [[SKKeyboardBridge alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.keyboardBridge];

    self.editLayoutButton = [self chromeButtonWithSymbol:@"gearshape"
                                                  action:@selector(onToggleEditLayout)];
    self.keyboardButton = [self chromeButtonWithSymbol:@"keyboard"
                                                action:@selector(onToggleKeyboard)];
    // Shortcut for the editor's "Show Buttons" switch, for hiding the controls to see the
    // screen without opening the editor first.
    self.buttonsToggle = [self chromeButtonWithSymbol:@"eye" action:@selector(onToggleButtons)];
    [self refreshButtonsToggleIcon];
    [self migrateChromeLayoutOnce];
    [self setupFpsPill];

    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handlePointerHover:)];
    [self.surfaceView addGestureRecognizer:hover];

    // Scroll wheel / two-finger trackpad scroll. A pan restricted to discrete scroll only
    // fires for real scroll input, so it cannot swallow touches meant for the game.
    UIPanGestureRecognizer *scroll =
      [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScroll:)];
    scroll.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
    scroll.allowedTouchTypes = @[];  // scroll devices only, never fingers
    [self.surfaceView addGestureRecognizer:scroll];
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
    [self setDrawableSize:CGSizeMake(width, height)];
    [EAGLContext setCurrentContext:nil];

    // Boot overlay (shown while getdown runs)
    self.bootOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.bootOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.bootOverlay.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.bootOverlay];

    self.bootStatus = [[UILabel alloc] init];
    self.bootStatus.text = NSLocalizedString(@"Starting Java runtime…", nil);
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
    self.signInTask = UIBackgroundTaskInvalid;

    [SKNativeBridge setBootStatusHandler:^(NSString *message) {
      weakSelf.bootStatus.text = message;
      // A first launch downloads the game, which takes minutes while status keeps arriving:
      // only a silence of kBootTimeout is a stall.
      if (weakSelf.bootWatchdog.valid) [weakSelf startBootWatchdog];
    }];

    [SKNativeBridge setRenderReadyHandler:^{
      [UIApplication sharedApplication].idleTimerDisabled = YES;
      [weakSelf.bootWatchdog invalidate];
      weakSelf.bootWatchdog = nil;
      [UIView animateWithDuration:0.3
          animations:^{
            weakSelf.bootOverlay.alpha = 0;
          }
          completion:^(BOOL finished) {
            [weakSelf.bootOverlay removeFromSuperview];
          }];
    }];

    [SKNativeBridge setShowSignInHandler:^(NSString *url, NSString *modules) {
      [weakSelf showSignInURL:url modules:modules];
    }];

    [SKNativeBridge setHideSignInHandler:^{
      [weakSelf hideSignIn];
    }];
}

- (void)setupGameControllers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(controllerConnected:)
                   name:GCControllerDidConnectNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(controllerDisconnected:)
                   name:GCControllerDidDisconnectNotification
                 object:nil];
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
    if (!gamepad)
        return;

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
    // GCControllerDirectionPad reports +1 for up. GLFW's standard layout, Android's
    // MotionEvent.AXIS_Y, and both of our own touch joysticks are all up-negative, so the
    // Y axes have to be flipped or a controller drives the character the wrong way while
    // the on-screen stick works.
    gamepad.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *stick, float xValue, float yValue) {
      sk_gamepad_set_axis(SKGamepadAxisLeftX, fabsf(xValue) < SKAxisDeadzone ? 0.0f : xValue);
      sk_gamepad_set_axis(SKGamepadAxisLeftY, fabsf(yValue) < SKAxisDeadzone ? 0.0f : -yValue);
    };
    gamepad.rightThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *stick, float xValue, float yValue) {
      sk_gamepad_set_axis(SKGamepadAxisRightX, fabsf(xValue) < SKAxisDeadzone ? 0.0f : xValue);
      sk_gamepad_set_axis(SKGamepadAxisRightY, fabsf(yValue) < SKAxisDeadzone ? 0.0f : -yValue);
    };
    gamepad.leftThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
      sk_gamepad_set_button(SKGamepadButtonLeftThumb, pressed);
    };
    gamepad.rightThumbstickButton.pressedChangedHandler =
        ^(GCControllerButtonInput *button, float value, BOOL pressed) {
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
- (void)setDrawableSize:(CGSize)size {
    self.lastDrawableSize = size;
    sk_gl_set_drawable_size((int)size.width, (int)size.height);
}

- (CGFloat)pointToPixelScale {
    CGFloat width = self.surfaceView.bounds.size.width;
    if (width <= 0 || self.lastDrawableSize.width <= 0)
        return self.surfaceView.contentScaleFactor;
    CGFloat gameWidth = self.lastDrawableSize.width;
    if (self.gfxOffscreen) {
        // The drawable is native-sized; the game believes it is the scene's size (the full size with Sharp HUD).
        int gameW, gameH;
        SKGfxGameSize((int)self.lastDrawableSize.width, (int)self.lastDrawableSize.height,
                      (float)self.layoutRenderScale, SKGfxSharpHud(), &gameW, &gameH);
        gameWidth = gameW;
    }
    return gameWidth / width;
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

- (void)handleScroll:(UIPanGestureRecognizer *)recognizer API_AVAILABLE(ios(13.4)) {
    CGPoint delta = [recognizer translationInView:self.surfaceView];
    // ~16pt per notch, matching how far a discrete wheel step moves a scroll view. Only
    // the consumed whole notches are subtracted: zeroing the translation outright would
    // throw away the remainder, and a device reporting less than a notch per event would
    // never scroll at all.
    static const CGFloat kPointsPerNotch = 16.0;
    int ticks = (int)(delta.y / kPointsPerNotch);
    if (ticks == 0) return;

    [recognizer setTranslation:CGPointMake(delta.x, delta.y - ticks * kPointsPerNotch)
                        inView:self.surfaceView];
    sk_input_push_scroll(ticks);
}

/// Sends the press or release of every mouse button whose state differs from the last report.
- (void)syncPointerButtons:(unsigned)mask {
    unsigned pressed, released;
    SKMouseButtonChanges(self.pointerButtons, mask, &pressed, &released);
    self.pointerButtons = mask;
    for (int button = 0; button < 3; button++) {
        if (released & (1u << button)) sk_input_push_mouse_button(button, NO);
        if (pressed & (1u << button)) sk_input_push_mouse_button(button, YES);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (self.primaryTouch) {
        // Another button of the pointer already held down, if UIKit reports it as a new touch.
        if (self.primaryTouchIsPointer && touch.type == UITouchTypeIndirectPointer) {
            [self sendCursorForTouch:touch];
            [self syncPointerButtons:(unsigned)event.buttonMask];
        }
        return;
    }
    self.primaryTouch = touch;
    self.primaryTouchIsPointer = touch.type == UITouchTypeIndirectPointer;
    [self sendCursorForTouch:touch];
    if (self.primaryTouchIsPointer) {
        self.pointerButtons = 0;
        // A press that reports no button is the primary one.
        [self syncPointerButtons:(unsigned)event.buttonMask ?: 1u];
    } else {
        self.primaryTouchButton = 0;
        sk_input_push_mouse_button(0, YES);
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.primaryTouch && [touches containsObject:self.primaryTouch]) {
        [self sendCursorForTouch:self.primaryTouch];
        // A button pressed or released while another is held shows up here as a new mask.
        if (self.primaryTouchIsPointer && event.buttonMask != 0) {
            [self syncPointerButtons:(unsigned)event.buttonMask];
        }
    }
}

- (void)endPrimaryTouch:(NSSet<UITouch *> *)touches {
    if (!self.primaryTouch || ![touches containsObject:self.primaryTouch])
        return;
    [self sendCursorForTouch:self.primaryTouch];
    if (self.primaryTouchIsPointer) {
        // The pointer lifting ends every button still held.
        [self syncPointerButtons:0];
    } else {
        sk_input_push_mouse_button(self.primaryTouchButton, NO);
    }
    self.primaryTouch = nil;
    self.primaryTouchButton = 0;
    self.primaryTouchIsPointer = NO;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endPrimaryTouch:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endPrimaryTouch:touches];
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses)
        handled |= push_key_event(press.key, 1, YES);
    if (!handled)
        [super pressesBegan:presses withEvent:event];
}

- (void)pressesChanged:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses)
        handled |= push_key_event(press.key, 2, NO);
    if (!handled)
        [super pressesChanged:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses)
        handled |= push_key_event(press.key, 0, NO);
    if (!handled)
        [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self pressesEnded:presses withEvent:event];
}

#pragma mark - Steam sign-in

/// The module grid as an image: whitespace-free rows of '1' (dark) and '0', a white 4-module quiet zone,
/// and an integer pixel size per module so scaling never blurs an edge.
static UIImage *skQRImage(NSString *modules) {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSUInteger cols = 0;
    for (NSString *row in [modules componentsSeparatedByString:@"\n"]) {
        if (row.length == 0) continue;
        [rows addObject:row];
        cols = MAX(cols, row.length);
    }
    if (rows.count == 0 || cols == 0) return nil;

    const NSUInteger quiet = 4;
    NSUInteger totalW = cols + 2 * quiet, totalH = rows.count + 2 * quiet;
    NSUInteger px = MAX(1, 480 / MAX(totalW, totalH));

    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, totalW * px, totalH * px, 8, 0, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!ctx) return nil;

    CGContextSetGrayFillColor(ctx, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, totalW * px, totalH * px));
    CGContextSetGrayFillColor(ctx, 0, 1);
    for (NSUInteger r = 0; r < rows.count; r++) {
        NSString *row = rows[r];
        for (NSUInteger c = 0; c < row.length; c++) {
            if ([row characterAtIndex:c] != '1') continue;
            // The context's origin is bottom-left.
            CGContextFillRect(ctx, CGRectMake((c + quiet) * px, (totalH - 1 - (r + quiet)) * px, px, px));
        }
    }
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return image;
}

- (void)buildSignInOverlay {
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    card.layer.cornerRadius = 16;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:card];

    UIImageView *qr = [[UIImageView alloc] init];
    qr.contentMode = UIViewContentModeScaleAspectFit;
    qr.layer.magnificationFilter = kCAFilterNearest;
    qr.layer.cornerRadius = 6;
    qr.clipsToBounds = YES;
    qr.isAccessibilityElement = YES;
    qr.accessibilityLabel = NSLocalizedString(@"Steam sign-in QR code", nil);
    qr.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [qr.widthAnchor constraintEqualToConstant:200],
        [qr.heightAnchor constraintEqualToConstant:200],
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.text = NSLocalizedString(@"Sign in to Steam", nil);
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];

    UILabel *body = [[UILabel alloc] init];
    body.text = NSLocalizedString(@"Scan this code with the Steam mobile app on another device and approve the sign-in, or "
                @"open the Steam app on this one.", nil);
    body.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    body.font = [UIFont systemFontOfSize:14];
    body.numberOfLines = 0;

    UIButtonConfiguration *openConfig = [UIButtonConfiguration filledButtonConfiguration];
    openConfig.title = NSLocalizedString(@"Open Steam app", nil);
    openConfig.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *open = [UIButton buttonWithConfiguration:openConfig primaryAction:nil];
    [open addTarget:self action:@selector(onSignInOpenSteam) forControlEvents:UIControlEventTouchUpInside];

    UIButtonConfiguration *cancelConfig = [UIButtonConfiguration plainButtonConfiguration];
    cancelConfig.title = NSLocalizedString(@"Cancel", nil);
    UIButton *cancel = [UIButton buttonWithConfiguration:cancelConfig primaryAction:nil];
    [cancel addTarget:self action:@selector(onSignInCancel) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[ open, cancel ]];
    buttons.spacing = 8;
    buttons.alignment = UIStackViewAlignmentCenter;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[ title, body, buttons ]];
    text.axis = UILayoutConstraintAxisVertical;
    text.alignment = UIStackViewAlignmentLeading;
    text.spacing = 12;
    NSLayoutConstraint *textWidth = [text.widthAnchor constraintEqualToConstant:300];
    textWidth.priority = UILayoutPriorityDefaultHigh;
    textWidth.active = YES;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ qr, text ]];
    row.spacing = 24;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];

    UILayoutGuide *safe = overlay.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:16],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
    ]];

    self.signInOverlay = overlay;
    self.signInQR = qr;
    self.signInBody = body;
    self.signInRow = row;
    self.signInText = text;
    [self updateSignInLayout];
}

/// QR beside the text in landscape, QR above it in portrait (where the sign-in normally runs).
- (void)updateSignInLayout {
    if (!self.signInRow) return;
    BOOL portrait = self.view.bounds.size.width < self.view.bounds.size.height;
    self.signInRow.axis = portrait ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.signInRow.spacing = portrait ? 20 : 24;
    self.signInText.alignment = portrait ? UIStackViewAlignmentCenter : UIStackViewAlignmentLeading;
    self.signInBody.textAlignment = portrait ? NSTextAlignmentCenter : NSTextAlignmentNatural;
}

/// Called again each time Steam rotates the challenge, so it updates the one overlay in place.
- (void)showSignInURL:(NSString *)url modules:(NSString *)modules {
    // A Cancel that landed first wins over a rotation already in flight.
    if ([SKNativeBridge signInCancelled]) return;
    UIImage *image = skQRImage(modules);
    if (!image) {
        NSLog(@"[GameVC] Unusable QR grid; cancelling sign-in");
        [SKNativeBridge cancelSignIn];
        return;
    }
    if (!self.signInOverlay) [self buildSignInOverlay];
    self.signInURL = url;
    self.signInQR.image = image;
    if (!self.signInOverlay.superview) [self.view addSubview:self.signInOverlay];
    [self.view bringSubviewToFront:self.signInOverlay];

    // Approving in the Steam app backgrounds this one. The window iOS grants is short, so
    // frenchpress starts a new challenge if the connection dies meanwhile.
    if (self.signInTask == UIBackgroundTaskInvalid) {
        __weak typeof(self) weakSelf = self;
        self.signInTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"SKapsule steam sign-in"
                                                                     expirationHandler:^{
                                                                       [weakSelf endSignInBackgroundTask];
                                                                     }];
    }
}

- (void)hideSignIn {
    [self.signInOverlay removeFromSuperview];
    self.signInURL = nil;
    [self endSignInBackgroundTask];
    // SkBootstrap hides once more when the sign-in phase is over, even if it never showed a code.
    [self endPortraitSignInPhase];
}

/// The sign-in runs in portrait and the game is landscape-only, so turn once it is over. iOS does
/// not re-evaluate the supported orientations by itself (see the launcher's enforcePortraitOrientation).
- (void)endPortraitSignInPhase {
    if (!self.signInInPortrait) return;
    self.signInInPortrait = NO;
    self.resyncDrawableAfterPortrait = YES;
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *scene = self.view.window.windowScene;
    if (scene) {
        UIWindowSceneGeometryPreferencesIOS *landscape =
          [[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
        [scene requestGeometryUpdateWithPreferences:landscape errorHandler:nil];
    }
}

- (void)endSignInBackgroundTask {
    if (self.signInTask == UIBackgroundTaskInvalid) return;
    [UIApplication.sharedApplication endBackgroundTask:self.signInTask];
    self.signInTask = UIBackgroundTaskInvalid;
}

- (void)onSignInOpenSteam {
    NSURL *url = self.signInURL ? [NSURL URLWithString:self.signInURL] : nil;
    if (!url) return;
    // Universal links only: without the Steam app this fails here instead of opening a web page.
    [UIApplication.sharedApplication openURL:url
                                     options:@{UIApplicationOpenURLOptionUniversalLinksOnly : @YES}
                           completionHandler:^(BOOL opened) {
                             if (opened) return;
                             self.signInBody.text = NSLocalizedString(@"The Steam app did not open. Scan the code from another device "
                                                    @"that has the Steam app, or install Steam on this one.", nil);
                           }];
}

- (void)onSignInCancel {
    [SKNativeBridge cancelSignIn];
    [self hideSignIn];
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
    // Shared with the standalone control editor: both must inset the overlay identically
    // or a control placed against an edge lands somewhere else in play.
    return SKGameSafeAreaInsets(self.view);
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
    [self applyGfxConfig];

    self.touchControls.frame = bounds;
    [self layoutChromeButtons];
    [self layoutFpsPill];

    // Rebuilding the drawable is GL work on the main thread. That is only safe before SK's
    // render thread takes gEAGLContext; afterwards the two would be issuing commands into
    // one context, which corrupts the driver's heap. The scale is applied once at layer
    // creation (see viewDidLoad), so in practice there is nothing to do here after boot.
    // Re-assert on every layout: UIKit resets it from the screen scale behind our back.
    // Cheap, not a GL call, safe at any point in the session.
    if (self.renderScaleFactor > 0)
        self.surfaceView.contentScaleFactor = self.renderScaleFactor;

    [self updateSignInLayout];

    // The portrait sign-in phase is over and the screen is landscape now: the drawable still has the
    // portrait size. Until the game's render thread has taken the context the renderbuffer is rebuilt
    // right here; after that the render thread does it, as for the resolution slider.
    BOOL leavingPortrait = self.resyncDrawableAfterPortrait && bounds.size.width > bounds.size.height;
    if (leavingPortrait && sk_gl_context_taken()) {
        self.resyncDrawableAfterPortrait = NO;
        [self setDrawableSize:CGSizeMake(round(bounds.size.width * self.renderScaleFactor),
                                         round(bounds.size.height * self.renderScaleFactor))];
        sk_gl_request_resize();
    } else if (gEAGLContext && (!self.jvmKicked || leavingPortrait)) {
        if (leavingPortrait) self.resyncDrawableAfterPortrait = NO;
        [EAGLContext setCurrentContext:gEAGLContext];
        CGFloat contentsScale = self.renderScaleFactor;

        // Rebuilding the renderbuffer re-enters layout, so bail unless the target actually
        // moved -- otherwise this spins forever.
        CGSize target = CGSizeMake(round(bounds.size.width * contentsScale), round(bounds.size.height * contentsScale));
        if (CGSizeEqualToSize(target, self.lastDrawableSize)) {
            [EAGLContext setCurrentContext:nil];
            return;
        }
        [self setDrawableSize:target];

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
    self.bootStatus.text = NSLocalizedString(@"Waiting for JIT…", nil);
    [self.spinner startAnimating];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Waiting for JIT", nil)
                         message:SKBuiltinJIT.selected
                                     ? NSLocalizedString(@"Spiral Knights needs JIT. SKapsule is enabling it now (LocalDevVPN must be "
                                       @"connected); the game continues automatically.", nil)
                                     : NSLocalizedString(@"Spiral Knights needs JIT. Approve the request in StikDebug and the game "
                                       @"continues automatically.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
                                              __strong typeof(weakSelf) self = weakSelf;
                                              if (!self)
                                                  return;
                                              self.jitWaitCancelled = YES;
                                              self.jitWaitAlert = nil;
                                              [self dismissViewControllerAnimated:YES completion:nil];
                                            }]];
    self.jitWaitAlert = alert;
    [self presentViewController:alert animated:YES completion:nil];

    [SKBuiltinJIT requestJITWithFailure:^(NSString *message) {
      __strong typeof(weakSelf) self = weakSelf;
      if (self.jitWaitAlert != alert) return;  // already cancelled or granted
      alert.title = NSLocalizedString(@"Couldn't enable JIT", nil);
      alert.message = message;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      while (!skJITReady()) {
          __strong typeof(weakSelf) self = weakSelf;
          if (!self || self.jitWaitCancelled)
              return;
          usleep(200 * 1000);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.jitWaitCancelled)
            return;
        [self.jitWaitAlert dismissViewControllerAnimated:YES completion:nil];
        self.jitWaitAlert = nil;
        [self launchJVMNow];
      });
    });
}

- (void)launchJVMNow {
    self.bootStatus.text = NSLocalizedString(@"Launching Spiral Knights…", nil);
    [self.spinner startAnimating];

    BOOL isSteam = (self.loginMode == 1);  // SKLoginModeSteam
    // Deliberately the unscaled screen scale: this sizes Cacio's virtual AWT screen
    // (dialogs, cursor), which must not shrink with the render-scale divisor.
    CGSize surfaceSize = self.surfaceView.frame.size;
    CGFloat scale = UIScreen.mainScreen.scale;
    int w = (int)(surfaceSize.width * scale);
    int h = (int)(surfaceSize.height * scale);
    // The game is always landscape; a launch that starts in portrait (the Steam sign-in) must not
    // size the virtual screen with the portrait edges.
    if (w < h) {
        int t = w;
        w = h;
        h = t;
    }

    [self startHeapWatchdog];

    // The block gets the only copy; the property must not keep the password for the session.
    NSString *webUser = self.webUser ?: @"";
    __block NSString *webPass = self.webPass ?: @"";
    NSString *loginHost = self.loginHost ?: @"";
    self.webPass = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      // Before the JVM: getdown runs inside SkBootstrap, so a jar dropped here is
      // refetched on this launch rather than the next one.
      [SKInstaller repairGameJars];
      [SKInstaller repairUnpackedResources];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self startBootWatchdog];
        [self watchForUnservicedJITTrap];
      });
      int ret = launchJVM(webUser, webPass, loginHost, isSteam, w, h);
      webPass = nil;
      NSLog(@"[GameVC] JVM exited with code %d", ret);
      if (ret != 0) {
          SKReportFailure(@"jvm_exit",
                          [NSString stringWithFormat:@"JVM exited with code %d", ret],
                          @{@"exit_code" : @(ret).stringValue});
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        // The JIT message is the cause; the exit code is only its aftermath.
        if (!skJITTrapWasSkipped()) self.bootStatus.text = [NSString stringWithFormat:NSLocalizedString(@"JVM exited (code %d)", nil), ret];
        [self.spinner stopAnimating];
        [self endPortraitSignInPhase];
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

/// All three chrome buttons are the same square, so they read as one row of controls.
static const CGFloat kChromeButtonSize = 44.0f;

/// Gap between adjacent buttons in the ESC/gear/keyboard/eye row.
static const CGFloat kChromeButtonGap = 8.0f;

- (UIButton *)chromeButtonWithSymbol:(NSString *)symbolName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [self setChromeSymbol:symbolName onButton:button];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    button.layer.cornerRadius = 12;
    // Same hairline edge the touch buttons carry (SKButtonControl).
    button.layer.borderWidth = 1.0f;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.frame = CGRectMake(0, 0, kChromeButtonSize, kChromeButtonSize);

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handleChromeDrag:)];
    [button addGestureRecognizer:pan];

    [self.view addSubview:button];
    return button;
}

- (void)setChromeSymbol:(NSString *)symbolName onButton:(UIButton *)button {
    [button setImage:[UIImage systemImageNamed:symbolName] forState:UIControlStateNormal];
}

- (void)chromePositionForKey:(NSString *)key defaultX:(CGFloat)dx defaultY:(CGFloat)dy into:(CGPoint *)out {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kChromePrefsKey];
    NSNumber *x = prefs[[key stringByAppendingString:@"_x"]];
    NSNumber *y = prefs[[key stringByAppendingString:@"_y"]];
    out->x = x ? x.doubleValue : dx;
    out->y = y ? y.doubleValue : dy;
}

/**
 * Clears saved chrome positions once, when the row changed shape.
 *
 * The buttons went from two differently-sized text buttons to three squares sitting close
 * together; anyone who already had positions saved would keep the old spread-out layout
 * and never see the new arrangement.
 */
- (void)migrateChromeLayoutOnce {
    static NSString *const kLayoutVersionKey = @"game_chrome_layout_version";
    static const NSInteger kLayoutVersion = 3;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults integerForKey:kLayoutVersionKey] >= kLayoutVersion) return;
    [defaults removeObjectForKey:kChromePrefsKey];
    [defaults setInteger:kLayoutVersion forKey:kLayoutVersionKey];
}

- (void)layoutChromeButtons {
    CGRect bounds = self.surfaceView.frame;
    if (CGRectIsEmpty(bounds))
        return;

    CGFloat alpha = MAX(self.touchControls.layout.globalOpacity, 0.2);
    CGPoint fraction;

    // Default row: ESC, gear, keyboard, eye, evenly gapped on ESC's line. ESC is a
    // control node so it is width * SKButtonWidthPercent across; the chrome squares are a
    // fixed size, so the first gap is measured off ESC and the rest off each other.
    CGFloat escHalf = bounds.size.width * SKButtonWidthPercent * 0.5f;
    CGFloat step = kChromeButtonSize + kChromeButtonGap;
    CGFloat firstX = bounds.size.width * SKEscXPercent + escHalf + kChromeButtonGap +
                     kChromeButtonSize * 0.5f;
    CGFloat defaultY = SKEscYPercent;

    [self chromePositionForKey:@"gear" defaultX:firstX / bounds.size.width defaultY:defaultY into:&fraction];
    self.editLayoutButton.center = CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * fraction.x,
                                               CGRectGetMinY(bounds) + bounds.size.height * fraction.y);
    self.editLayoutButton.alpha = alpha;

    [self chromePositionForKey:@"kb" defaultX:(firstX + step) / bounds.size.width defaultY:defaultY into:&fraction];
    self.keyboardButton.center = CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * fraction.x,
                                             CGRectGetMinY(bounds) + bounds.size.height * fraction.y);
    self.keyboardButton.alpha = alpha;

    [self chromePositionForKey:@"eye" defaultX:(firstX + 2 * step) / bounds.size.width defaultY:defaultY into:&fraction];
    self.buttonsToggle.center = CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * fraction.x,
                                            CGRectGetMinY(bounds) + bounds.size.height * fraction.y);
    self.buttonsToggle.alpha = alpha;

    // "Show Controls" hides the keyboard and eye buttons too -- both only act on the touch
    // controls. The gear stays: it is the only way back into the editor.
    // Editing keeps them on screen regardless, or they could not be repositioned.
    BOOL controlsOn = self.touchControls.layout.controlsEnabled || self.touchControls.isEditing;
    self.keyboardButton.hidden = !controlsOn;
    self.buttonsToggle.hidden = !controlsOn;
}

- (void)touchOverlayDidChangeAppearance:(SKTouchControlOverlay *)overlay {
    [self layoutChromeButtons];
    [self refreshButtonsToggleIcon];
}

- (void)onToggleButtons {
    [self.touchControls toggleButtonsVisible];
    [self refreshButtonsToggleIcon];
}

- (void)refreshButtonsToggleIcon {
    [self setChromeSymbol:self.touchControls.buttonsVisible ? @"eye" : @"eye.slash"
                 onButton:self.buttonsToggle];
}

- (void)handleChromeDrag:(UIPanGestureRecognizer *)pan {
    // Only movable while laying out controls, so a mis-swipe during play still presses.
    if (!self.touchControls.isEditing)
        return;

    UIView *button = pan.view;
    CGPoint translation = [pan translationInView:self.view];
    if (hypot(translation.x, translation.y) < kChromeDragSlop && pan.state != UIGestureRecognizerStateEnded)
        return;

    if (pan.state == UIGestureRecognizerStateChanged) {
        button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
        [pan setTranslation:CGPointZero inView:self.view];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self persistChromePosition:button];
    }
}

- (void)persistChromePosition:(UIView *)button {
    CGRect bounds = self.surfaceView.frame;
    if (CGRectIsEmpty(bounds))
        return;
    NSString *key = @"kb";
    if (button == self.editLayoutButton) {
        key = @"gear";
    } else if (button == self.buttonsToggle) {
        key = @"eye";
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *prefs = [([defaults dictionaryForKey:kChromePrefsKey] ?: @{}) mutableCopy];
    prefs[[key stringByAppendingString:@"_x"]] = @((button.center.x - CGRectGetMinX(bounds)) / bounds.size.width);
    prefs[[key stringByAppendingString:@"_y"]] = @((button.center.y - CGRectGetMinY(bounds)) / bounds.size.height);
    [defaults setObject:prefs forKey:kChromePrefsKey];
}

- (void)onToggleEditLayout {
    [self.touchControls toggleEditMode];
    [self setChromeSymbol:self.touchControls.isEditing ? @"checkmark" : @"gearshape"
                 onButton:self.editLayoutButton];
    // The editor switch may have moved "Show Buttons" while it was open.
    [self refreshButtonsToggleIcon];
    [self layoutChromeButtons];
}

- (void)onToggleKeyboard {
    [self.keyboardBridge toggle];
}

/// The settings -> what the surface and the native pass do. With the offscreen pass the layer stays
/// native-sized and the pass does the scaling; otherwise Core Animation upscales a smaller layer.
- (void)applyGfxConfig {
    float scale = (float)self.layoutRenderScale;
    int sharpen = SKGfxSharpenPercent();
    BOOL hud = SKGfxSharpHud();
    self.gfxOffscreen = SKGfxUsesOffscreen(scale, sharpen, hud);
    CGFloat screenScale = UIScreen.mainScreen.scale;
    self.renderScaleFactor = screenScale * (self.gfxOffscreen ? 1.0 : self.layoutRenderScale);
    CGSize bounds = self.surfaceView.bounds.size;
    sk_gl_set_gfx_config(self.gfxOffscreen, scale, sharpen / 100.0f, hud, (int)lround(bounds.width * screenScale),
                         (int)lround(bounds.height * screenScale));
}

- (void)touchOverlayDidChangeGfx:(SKTouchControlOverlay *)overlay {
    [self touchOverlay:overlay didChangeRenderScale:self.layoutRenderScale];
}

- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeFpsVisible:(BOOL)visible {
    [self setFpsVisible:visible];
}

#pragma mark FPS counter

/// A native view above the game, so the game's own screenshots never contain it. The swap hook
/// counts frames; this reads the count twice a second.
- (void)setupFpsPill {
    self.fpsPill = [[UIView alloc] init];
    self.fpsPill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.fpsPill.layer.cornerRadius = 6;
    self.fpsPill.userInteractionEnabled = NO;
    self.fpsLabel = [[UILabel alloc] init];
    self.fpsLabel.textColor = UIColor.whiteColor;
    self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.fpsLabel.text = @"FPS --";
    self.fpsLabel.isAccessibilityElement = NO;
    [self.fpsPill addSubview:self.fpsLabel];
    [self.view addSubview:self.fpsPill];
    [self setFpsVisible:SKGfxShowFps()];
}

- (void)setFpsVisible:(BOOL)visible {
    [self.fpsTimer invalidate];
    self.fpsTimer = nil;
    self.fpsPill.hidden = !visible;
    if (!visible) return;
    self.fpsLastTime = 0;
    __weak typeof(self) weakSelf = self;
    self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updateFps];
    }];
}

- (void)updateFps {
    uint64_t frames = sk_gfx_frame_count();
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (self.fpsLastTime > 0 && now > self.fpsLastTime) {
        int fps = (int)lround((double)(frames - self.fpsLastFrames) / (now - self.fpsLastTime));
        self.fpsLabel.text = [NSString stringWithFormat:@"FPS %d", fps];
    }
    self.fpsLastFrames = frames;
    self.fpsLastTime = now;
}

/// Top-left corner of what the game fills, clear of the notch and any avoid-edges inset.
- (void)layoutFpsPill {
    CGSize text = [@"FPS 999" sizeWithAttributes:@{NSFontAttributeName: self.fpsLabel.font}];
    CGFloat padX = 6, padY = 1;
    self.fpsLabel.frame = CGRectMake(padX, padY, ceil(text.width), ceil(text.height));
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat x = MAX(CGRectGetMinX(self.surfaceView.frame), safe.left) + 3;
    CGFloat y = safe.top + 1;
    self.fpsPill.frame = CGRectMake(x, y, ceil(text.width) + 2 * padX, ceil(text.height) + 2 * padY);
    [self.view bringSubviewToFront:self.fpsPill];
}

- (void)touchOverlay:(SKTouchControlOverlay *)overlay didChangeRenderScale:(CGFloat)renderScale {
    self.layoutRenderScale = renderScale;
    [self applyGfxConfig];
    // contentScaleFactor is a UIKit property, not GL -- safe on the main thread, and it is
    // what CoreAnimation hands to renderbufferStorage:fromDrawable:.
    self.surfaceView.contentScaleFactor = self.renderScaleFactor;

    CGSize bounds = self.surfaceView.bounds.size;
    [self setDrawableSize:CGSizeMake(round(bounds.width * self.renderScaleFactor),
                                     round(bounds.height * self.renderScaleFactor))];

    // The rebuild itself has to happen on the thread that owns the context. Before the JVM
    // is up there is no render thread yet, so do it inline via the layout path instead.
    if (self.jvmKicked)
        sk_gl_request_resize();
    else
        [self.view setNeedsLayout];
}

/**
 * Says something true when the game never draws.
 *
 * The boot overlay is dismissed only by the first frame, so anything that kills the client
 * before then -- a broken resource jar, a caught exception inside SK -- leaves it showing
 * whatever status text arrived last, forever. That is what "Validating  75%" was: not a
 * stall in validation, just the last thing getdown said before the client died.
 */
- (void)startBootWatchdog {
    static const NSTimeInterval kBootTimeout = 90.0;
    [self.bootWatchdog invalidate];
    __weak typeof(self) weakSelf = self;
    self.bootWatchdog = [NSTimer scheduledTimerWithTimeInterval:kBootTimeout
                                                        repeats:NO
                                                          block:^(NSTimer *timer) {
                                                            [weakSelf onBootTimedOut];
                                                          }];
}

/// The JVM's JIT request went unanswered (see skInstallJITTrapGuard): the JVM cannot map its
/// code cache and will fail, so say why now rather than leave the last status on screen.
- (void)watchForUnservicedJITTrap {
    __weak typeof(self) weakSelf = self;
    [NSTimer scheduledTimerWithTimeInterval:0.5
                                    repeats:YES
                                      block:^(NSTimer *timer) {
                                        typeof(self) self = weakSelf;
                                        if (!self || !self.bootOverlay.superview) {
                                            [timer invalidate];
                                            return;
                                        }
                                        if (!skJITTrapWasSkipped()) return;
                                        [timer invalidate];
                                        [self.bootWatchdog invalidate];
                                        self.bootStatus.text =
                                            NSLocalizedString(@"JIT was not enabled: the game asked for its JIT memory and "
                                            @"nothing answered.\nIn StikDebug, import skapsule-jit.js and "
                                            @"assign it to SKapsule, then enable JIT again.", nil);
                                        [self.spinner stopAnimating];
                                      }];
}

- (void)onBootTimedOut {
    if (!self.bootOverlay.superview) return;  // first frame arrived; nothing to report
    self.bootStatus.text = NSLocalizedString(@"Spiral Knights did not finish starting.\n"
                           @"Share Logs from the launcher sidebar to report it.", nil);
    [self.spinner stopAnimating];
    SKReportFailure(@"boot_timeout", @"no first frame or progress within 90s of JVM launch", nil);
}

- (void)startHeapWatchdog {
    if (self.heapWatchdog)
        return;
    __weak typeof(self) weakSelf = self;
    __block int tick = 0;
    // 1s while the scene loads -- every corruption crash so far has landed inside the
    // first ~10s of GL activity, and a 5s period barely sampled that window at all.
    self.heapWatchdog =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                        repeats:YES
                                          block:^(NSTimer *timer) {
                                            if (!weakSelf) {
                                                [timer invalidate];
                                                return;
                                            }
                                            ++tick;
                                            BOOL settled = tick > 60;
                                            if (settled && (tick % 5))
                                                return;

                                            task_vm_info_data_t info;
                                            mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
                                            if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) ==
                                                KERN_SUCCESS) {
                                                NSLog(@"[mem] t=%ds footprint=%lluMB available=%lluMB", tick,
                                                      (unsigned long long)(info.phys_footprint >> 20),
                                                      (unsigned long long)(os_proc_available_memory() >> 20));
                                            }
                                          }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"[mem] *** memory warning, available=%lluMB ***", (unsigned long long)(os_proc_available_memory() >> 20));
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
    return self.signInInPortrait ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskLandscape;
}

- (void)dealloc {
    [self.heapWatchdog invalidate];
    [self.bootWatchdog invalidate];
    if (_signInTask != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:_signInTask];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (GCController *controller in GCController.controllers) {
        [self unregisterController:controller];
    }
    sk_gamepad_set_virtual_active(NO);
}

@end
