#define GLES_SILENCE_DEPRECATION 1
#import "GameViewController.h"
#import "JavaLauncher.h"
#import "NativeBridge.h"
#import "SKInstaller.h"
#import "utils.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#import <GameController/GameController.h>

extern void sk_input_push_cursor(int x, int y);
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

@interface SKTouchButton : UIView
- (instancetype)initWithTitle:(NSString *)title button:(NSInteger)button axis:(BOOL)axis toggle:(BOOL)toggle;
@end

@interface SKTouchJoystick : UIView
- (instancetype)initWithAxisX:(NSInteger)axisX axisY:(NSInteger)axisY;
@end

@interface SKTouchControlsView : UIView
@end

@implementation SKTouchButton {
    NSInteger _button;
    BOOL _axis;
    BOOL _toggle;
    BOOL _pressed;
    BOOL _toggled;
    UILabel *_label;
}

- (instancetype)initWithTitle:(NSString *)title button:(NSInteger)button axis:(BOOL)axis toggle:(BOOL)toggle {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _button = button;
    _axis = axis;
    _toggle = toggle;
    self.opaque = NO;
    self.multipleTouchEnabled = NO;
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.text = title;
    _label.textColor = UIColor.whiteColor;
    _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.adjustsFontSizeToFitWidth = YES;
    _label.minimumScaleFactor = 0.65;
    _label.numberOfLines = 2;
    [self addSubview:_label];
    [self refreshAppearance];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = CGRectInset(self.bounds, 4, 3);
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.24;
}

- (void)refreshAppearance {
    self.backgroundColor = (_pressed || _toggled) ? [UIColor colorWithWhite:0.48 alpha:0.80]
                                                   : [UIColor colorWithWhite:0.12 alpha:0.60];
}

- (void)sendPressed:(BOOL)pressed {
    if (_axis) {
        sk_gamepad_set_axis((int)_button, pressed ? 1.0f : -1.0f);
    } else {
        sk_gamepad_set_button((int)_button, pressed);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _pressed = YES;
    if (_toggle) {
        _toggled = !_toggled;
        [self sendPressed:_toggled];
    } else {
        [self sendPressed:YES];
    }
    [self refreshAppearance];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _pressed = NO;
    if (!_toggle) [self sendPressed:NO];
    [self refreshAppearance];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

@implementation SKTouchJoystick {
    NSInteger _axisX;
    NSInteger _axisY;
    UITouch *_touch;
    CGPoint _knob;
}

- (instancetype)initWithAxisX:(NSInteger)axisX axisY:(NSInteger)axisY {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _axisX = axisX;
    _axisY = axisY;
    self.opaque = NO;
    self.multipleTouchEnabled = NO;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_touch) _knob = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)drawRect:(CGRect)rect {
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [[UIColor colorWithWhite:0.12 alpha:0.40] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2)] fill];
    CGFloat knobRadius = radius * 0.40;
    [[UIColor colorWithWhite:0.62 alpha:0.80] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(_knob.x - knobRadius, _knob.y - knobRadius,
                                                        knobRadius * 2, knobRadius * 2)] fill];
}

- (void)reset {
    _touch = nil;
    _knob = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    sk_gamepad_set_axis((int)_axisX, 0.0f);
    sk_gamepad_set_axis((int)_axisY, 0.0f);
    [self setNeedsDisplay];
}

- (void)updateForTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat maxDistance = radius * 0.6;
    CGFloat dx = point.x - center.x;
    CGFloat dy = point.y - center.y;
    CGFloat distance = hypot(dx, dy);
    if (distance > maxDistance && distance > 0.0) {
        dx *= maxDistance / distance;
        dy *= maxDistance / distance;
    }
    _knob = CGPointMake(center.x + dx, center.y + dy);
    float x = dx / maxDistance;
    float y = dy / maxDistance;
    sk_gamepad_set_axis((int)_axisX, fabsf(x) < SKAxisDeadzone ? 0.0f : x);
    sk_gamepad_set_axis((int)_axisY, fabsf(y) < SKAxisDeadzone ? 0.0f : y);
    [self setNeedsDisplay];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch) return;
    _touch = touches.anyObject;
    [self updateForTouch:_touch];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self updateForTouch:_touch];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self reset];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self reset];
}

@end

@implementation SKTouchControlsView {
    SKTouchJoystick *_moveJoystick;
    SKTouchJoystick *_faceJoystick;
    NSArray<SKTouchButton *> *_buttons;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.opaque = NO;
    _moveJoystick = [[SKTouchJoystick alloc] initWithAxisX:SKGamepadAxisLeftX axisY:SKGamepadAxisLeftY];
    _faceJoystick = [[SKTouchJoystick alloc] initWithAxisX:SKGamepadAxisRightX axisY:SKGamepadAxisRightY];
    [self addSubview:_moveJoystick];
    [self addSubview:_faceJoystick];

    _buttons = @[
        [[SKTouchButton alloc] initWithTitle:@"Strafe" button:SKGamepadButtonRightThumb axis:NO toggle:YES],
        [[SKTouchButton alloc] initWithTitle:@"Defend" button:SKGamepadAxisLeftTrigger axis:YES toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"Attack" button:SKGamepadAxisRightTrigger axis:YES toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"Dodge" button:SKGamepadButtonLeftThumb axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"Bash" button:SKGamepadButtonY axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"↑" button:SKGamepadButtonLeftBumper axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"↓" button:SKGamepadButtonRightBumper axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"A1" button:SKGamepadButtonA axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"A2" button:SKGamepadButtonB axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"A3" button:SKGamepadButtonX axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"I1" button:SKGamepadButtonDpadUp axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"I2" button:SKGamepadButtonDpadRight axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"I3" button:SKGamepadButtonDpadDown axis:NO toggle:NO],
        [[SKTouchButton alloc] initWithTitle:@"I4" button:SKGamepadButtonDpadLeft axis:NO toggle:NO],
    ];
    for (SKTouchButton *button in _buttons) [self addSubview:button];
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return view == self ? nil : view;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat minDimension = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat joystickSize = MAX(104.0, MIN(160.0, minDimension * 0.40));
    CGFloat buttonSize = MAX(40.0, MIN(70.0, minDimension * 0.15));
    void (^place)(UIView *, CGFloat, CGFloat, CGFloat) = ^(UIView *view, CGFloat x, CGFloat y, CGFloat size) {
      view.bounds = CGRectMake(0, 0, size, size);
      view.center = CGPointMake(self.bounds.size.width * x, self.bounds.size.height * y);
    };

    place(_moveJoystick, 0.16, 0.72, joystickSize);
    place(_faceJoystick, 0.84, 0.72, joystickSize);
    const CGPoint positions[] = {
        {0.29, 0.72}, {0.70, 0.72}, {0.70, 0.55}, {0.78, 0.43}, {0.89, 0.43}, {0.95, 0.55}, {0.95, 0.86},
        {0.29, 0.90}, {0.36, 0.90}, {0.43, 0.90}, {0.50, 0.90}, {0.57, 0.90}, {0.64, 0.90}, {0.71, 0.90},
    };
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        place(_buttons[i], positions[i].x, positions[i].y, buttonSize);
    }
}

@end

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

@interface GameViewController ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) SKTouchControlsView *touchControls;
@property (nonatomic, strong) UILabel *bootStatus;
@property (nonatomic, strong) UIView *bootOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITouch *primaryTouch;
@property (nonatomic, assign) BOOL jvmKicked;
@property (nonatomic, strong) UIAlertController *jitWaitAlert;
@property (nonatomic, assign) BOOL jitWaitCancelled;
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
    gEAGLLayer.contentsScale = UIScreen.mainScreen.scale;
    gEAGLLayer.drawableProperties =
        @{kEAGLDrawablePropertyRetainedBacking: @(NO), kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8};

    gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!gEAGLContext) {
        gEAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    [EAGLContext setCurrentContext:gEAGLContext];

    glGenRenderbuffers(1, &gRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);

    self.touchControls = [[SKTouchControlsView alloc] initWithFrame:self.view.bounds];
    self.touchControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.touchControls];
    sk_gamepad_set_virtual_active(YES);

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

- (void)handlePointerHover:(UIHoverGestureRecognizer *)hover {
    CGPoint point = [hover locationInView:self.surfaceView];
    CGFloat scale = self.surfaceView.contentScaleFactor;
    sk_input_push_cursor((int)lround(point.x * scale), (int)lround(point.y * scale));
}

- (void)sendCursorForTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self.surfaceView];
    CGFloat scale = self.surfaceView.contentScaleFactor;
    sk_input_push_cursor((int)lround(point.x * scale), (int)lround(point.y * scale));
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    BOOL avoidEdges = NO;
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"avoid_screen_edges"];
    if (val) {
        avoidEdges = [val boolValue];
    }

    CGRect bounds = self.view.bounds;
    if (avoidEdges) {
        if (@available(iOS 11.0, *)) {
            UIEdgeInsets insets = self.view.safeAreaInsets;
            bounds = UIEdgeInsetsInsetRect(bounds, insets);
        }
    }
    self.surfaceView.frame = bounds;

    if (gEAGLContext) {
        [EAGLContext setCurrentContext:gEAGLContext];
        gEAGLLayer.contentsScale = UIScreen.mainScreen.scale;
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
    CGSize surfaceSize = self.surfaceView.frame.size;
    CGFloat scale = gEAGLLayer.contentsScale;
    int w = (int)(surfaceSize.width * scale);
    int h = (int)(surfaceSize.height * scale);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      int ret = launchJVM(self.steamUser ?: @"", self.steamPass ?: @"", isSteam, w, h);
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
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (GCController *controller in GCController.controllers) {
        [self unregisterController:controller];
    }
    sk_gamepad_set_virtual_active(NO);
}

@end
