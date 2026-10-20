#import "SKTouchControlOverlay.h"

extern void sk_input_push_key(int key, int action, int modifiers);
extern void sk_gamepad_set_virtual_active(BOOL active);
extern void sk_gamepad_set_button(int index, BOOL pressed);
extern void sk_gamepad_set_axis(int index, float value);

/// The app's accent, matching the launcher and the Android build. UIKit's defaults are
/// system green and blue, which look like a different app bolted on.
static UIColor *SKThemeColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      color = [UIColor colorWithRed:171.0 / 255.0 green:74.0 / 255.0 blue:129.0 / 255.0 alpha:1.0];
    });
    return color;
}

static const CGFloat kEditMinOpacity = 0.85f;
static const CGFloat kEditHiddenOpacity = 0.3f;
static const CGFloat kResetConfirmWindow = 2.5f;
/// The knob reaches full deflection at 60% of the visual radius, so the stick doesn't need
/// to be pushed all the way to the rim.
static const CGFloat kJoystickTravel = 0.6f;
/// How long the right stick keeps reporting its last direction after release, so the
/// attack fires where it was aimed rather than at centre.
static const NSTimeInterval kAimHold = 0.2;

/// A node emits exactly one of: a GLFW key, a gamepad axis held at +1/-1, or a button.
static void SKEmitNode(SKControlNode *node, BOOL pressed) {
    if (node.keyCode >= 0) {
        sk_input_push_key((int)node.keyCode, pressed ? 1 : 0, 0);
    } else if (node.buttonCode < 0) {
        return;
    } else if (node.isAxisTrigger) {
        sk_gamepad_set_axis((int)node.buttonCode, pressed ? 1.0f : -1.0f);
    } else {
        sk_gamepad_set_button((int)node.buttonCode, pressed);
    }
}

#pragma mark - Base control

@interface SKControlView : UIView
@property (nonatomic, strong) SKControlNode *node;
@property (nonatomic, assign) BOOL selectedForEdit;
@property (nonatomic, strong) CAShapeLayer *outline;
- (instancetype)initWithNode:(SKControlNode *)node;
/// Drop any input this control is currently asserting (used when controls are disabled).
- (void)releaseInput;
@end

@implementation SKControlView

- (instancetype)initWithNode:(SKControlNode *)node {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _node = node;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = NO;

    _outline = [CAShapeLayer layer];
    _outline.fillColor = UIColor.clearColor.CGColor;
    _outline.lineWidth = 4.0f;
    _outline.lineDashPattern = @[@10, @10];
    _outline.hidden = YES;
    [self.layer addSublayer:_outline];
    return self;
}

- (void)setSelectedForEdit:(BOOL)selectedForEdit {
    _selectedForEdit = selectedForEdit;
    self.outline.strokeColor = (selectedForEdit ? UIColor.yellowColor : UIColor.grayColor).CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.outline.frame = self.bounds;
    self.outline.path = [UIBezierPath bezierPathWithRect:self.bounds].CGPath;
}

- (void)releaseInput {}

@end

#pragma mark - Button

@interface SKButtonControl : SKControlView
@end

@implementation SKButtonControl {
    UILabel *_label;
    BOOL _pressed;
    BOOL _toggledOn;
}

- (instancetype)initWithNode:(SKControlNode *)node {
    self = [super initWithNode:node];
    if (!self) return nil;
    self.layer.borderWidth = 1.0f;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.text = node.label;
    _label.textColor = UIColor.whiteColor;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.numberOfLines = 2;
    _label.adjustsFontSizeToFitWidth = YES;
    _label.minimumScaleFactor = 0.65f;
    _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self addSubview:_label];
    [self refreshFill];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.24f;
}

- (void)refreshFill {
    BOOL lit = _pressed || _toggledOn;
    self.backgroundColor = [UIColor colorWithWhite:(lit ? 0.48 : 0.12) alpha:(lit ? 0.80 : 0.60)];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _pressed = YES;
    if (self.node.isToggle) {
        _toggledOn = !_toggledOn;
        SKEmitNode(self.node, _toggledOn);
    } else {
        SKEmitNode(self.node, YES);
    }
    [self refreshFill];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _pressed = NO;
    // A toggle latches: it reported its new state on press and says nothing on release.
    if (!self.node.isToggle) SKEmitNode(self.node, NO);
    [self refreshFill];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)releaseInput {
    if (_pressed || _toggledOn) {
        _pressed = _toggledOn = NO;
        SKEmitNode(self.node, NO);
        [self refreshFill];
    }
}

@end

#pragma mark - Joystick

@interface SKJoystickControl : SKControlView
@end

@implementation SKJoystickControl {
    CGPoint _knob;
    BOOL _dragging;
    NSInteger _aimGeneration;
    int _axisX;
    int _axisY;
}

- (instancetype)initWithNode:(SKControlNode *)node {
    self = [super initWithNode:node];
    if (!self) return nil;
    BOOL right = (node.type == SKControlTypeJoystickRight);
    _axisX = right ? 2 : 0;
    _axisY = right ? 3 : 1;
    return self;
}

- (BOOL)isRightStick {
    return self.node.type == SKControlTypeJoystickRight;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_dragging) _knob = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;
    CGPoint centre = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));

    UIBezierPath *base = [UIBezierPath bezierPathWithArcCenter:centre
                                                        radius:radius - 2
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    [[UIColor colorWithWhite:0.12 alpha:0.40] setFill];
    [base fill];

    UIBezierPath *knob = [UIBezierPath bezierPathWithArcCenter:_knob
                                                        radius:radius * 0.40f
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    [[UIColor colorWithWhite:0.62 alpha:0.80] setFill];
    [knob fill];
}

- (void)updateForTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGPoint centre = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;
    CGFloat maxDistance = radius * kJoystickTravel;

    CGFloat dx = point.x - centre.x;
    CGFloat dy = point.y - centre.y;
    CGFloat distance = hypot(dx, dy);
    if (distance > maxDistance && distance > 0) {
        CGFloat angle = atan2(dy, dx);
        dx = cos(angle) * maxDistance;
        dy = sin(angle) * maxDistance;
    }
    _knob = CGPointMake(centre.x + dx, centre.y + dy);
    [self setNeedsDisplay];

    if (maxDistance <= 0) return;  // degenerate bounds would push NaN into the axis

    // No deadzone: the touch stick already rests exactly at centre when untouched, and a
    // deadzone here would just eat small deliberate movements.
    sk_gamepad_set_axis(_axisX, (float)(dx / maxDistance));
    sk_gamepad_set_axis(_axisY, (float)(dy / maxDistance));
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _dragging = YES;
    _aimGeneration++;
    // Right stick doubles as attack: holding it charges, a tap fires.
    if (self.isRightStick) sk_gamepad_set_axis(5, 1.0f);
    [self updateForTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_dragging) [self updateForTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_dragging) return;
    _dragging = NO;
    _knob = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self setNeedsDisplay];

    if (self.isRightStick) {
        sk_gamepad_set_axis(5, -1.0f);
        // Keep reporting the aim briefly so the released attack goes where it was pointed.
        NSInteger generation = ++_aimGeneration;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAimHold * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_aimGeneration == generation) [strongSelf zeroAxes];
        });
    } else {
        [self zeroAxes];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)zeroAxes {
    sk_gamepad_set_axis(_axisX, 0.0f);
    sk_gamepad_set_axis(_axisY, 0.0f);
}

- (void)releaseInput {
    _dragging = NO;
    _aimGeneration++;
    [self zeroAxes];
    if (self.isRightStick) sk_gamepad_set_axis(5, -1.0f);
    _knob = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self setNeedsDisplay];
}

@end

#pragma mark - Overlay

@implementation SKTouchControlOverlay {
    NSMutableArray<SKControlView *> *_controls;
    SKControlView *_selected;

    UIView *_panel;
    UISwitch *_enableSwitch;
    UISwitch *_actionBarSwitch;
    UISlider *_opacitySlider;
    UISlider *_resolutionSlider;
    UIButton *_resetButton;
    UIView *_nodeSection;
    UILabel *_nodeTitle;
    UISwitch *_visibleSwitch;
    UISlider *_scaleSlider;

    BOOL _resetArmed;
    CGPoint _dragOffset;
    SKControlView *_dragging;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _layout = [SKTouchLayout loadLayout];
    _controls = [NSMutableArray array];
    self.opaque = NO;

    for (SKControlNode *node in _layout.nodes) {
        SKControlView *view = (node.type == SKControlTypeButton)
            ? [[SKButtonControl alloc] initWithNode:node]
            : [[SKJoystickControl alloc] initWithNode:node];
        [_controls addObject:view];
        [self addSubview:view];
    }
    [self buildPanel];
    [self applyAppearance];
    return self;
}

/// In play mode the overlay itself must be transparent to touches so taps in the gaps
/// reach the GL surface underneath; in edit mode it swallows everything so it can drag.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.editing) return hit ?: self;
    return hit == self ? nil : hit;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat baseJoystick = width * 0.135f;
    CGFloat baseButton = width * SKButtonWidthPercent;

    for (SKControlView *view in _controls) {
        SKControlNode *node = view.node;
        CGFloat base = (node.type == SKControlTypeButton) ? baseButton : baseJoystick;
        CGFloat size = base * node.scale;
        view.bounds = CGRectMake(0, 0, size, size);
        view.center = CGPointMake(width * node.xPercent, height * node.yPercent);
    }

    // The panel's height comes from its stack's constraints; sizeToFit would return the
    // frame unchanged because the panel itself is autoresizing-sized.
    CGFloat panelWidth = MIN(320.0f, width - 40.0f);
    CGFloat panelHeight = [_panel systemLayoutSizeFittingSize:CGSizeMake(panelWidth, 0)
                                withHorizontalFittingPriority:UILayoutPriorityRequired
                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    _panel.frame = CGRectMake((width - panelWidth) * 0.5f, (height - panelHeight) * 0.5f,
                              panelWidth, panelHeight);
}

/**
 * "Show Buttons" off hides every button except ESC. The joysticks are not buttons so they
 * stay, and ESC stays because without a hardware keyboard it is the only way out of a menu.
 */
- (BOOL)isHiddenByShowButtons:(SKControlNode *)node {
    return !_layout.actionBarVisible && node.type == SKControlTypeButton &&
           ![node.nodeId isEqualToString:@"btn_esc"];
}

/// Current state, for the chrome eye button's icon.
- (BOOL)buttonsVisible {
    return _layout.actionBarVisible;
}

/// Flips "Show Buttons" from outside the editor (the chrome eye button).
- (BOOL)toggleButtonsVisible {
    _layout.actionBarVisible = !_layout.actionBarVisible;
    _actionBarSwitch.on = _layout.actionBarVisible;
    [self applyAppearance];
    [_layout save];
    return _layout.actionBarVisible;
}

- (void)applyAppearance {
    for (SKControlView *view in _controls) {
        SKControlNode *node = view.node;
        if (self.editing) {
            view.hidden = NO;
            BOOL shown = node.visible && ![self isHiddenByShowButtons:node];
            view.alpha = shown ? MAX(_layout.globalOpacity, kEditMinOpacity) : kEditHiddenOpacity;
            view.userInteractionEnabled = NO;  // the overlay drives selection/drag itself
            view.outline.hidden = NO;
        } else {
            view.hidden =
              !(_layout.controlsEnabled && node.visible && ![self isHiddenByShowButtons:node]);
            view.alpha = _layout.globalOpacity;
            view.userInteractionEnabled = YES;
            view.outline.hidden = YES;
        }
    }
    // SK only reads the virtual pad while it reports as connected, so this gate is what
    // actually disables the controls rather than merely hiding them.
    sk_gamepad_set_virtual_active(_layout.controlsEnabled);

    if ([self.delegate respondsToSelector:@selector(touchOverlayDidChangeAppearance:)]) {
        [self.delegate touchOverlayDidChangeAppearance:self];
    }
    if (!_layout.controlsEnabled) {
        for (SKControlView *view in _controls) [view releaseInput];
    }
}

#pragma mark Edit mode

- (void)toggleEditMode {
    // A control held when the mode flips stops receiving touches, so release it here or
    // its button/axis stays latched in the gamepad mailbox.
    for (SKControlView *view in _controls) [view releaseInput];
    _editing = !_editing;
    _panel.hidden = !_editing;
    if (!_editing) {
        [self selectControl:nil];
        [_layout save];
    }
    [self applyAppearance];
    [self setNeedsLayout];
}

- (void)selectControl:(SKControlView *)control {
    _selected.selectedForEdit = NO;
    _selected = control;
    _selected.selectedForEdit = YES;

    _nodeSection.hidden = (control == nil);
    if (control) {
        _nodeTitle.text = [NSString stringWithFormat:@"Settings: %@",
                           control.node.label.length ? control.node.label : control.node.nodeId];
        _visibleSwitch.on = control.node.visible;
        _scaleSlider.value = control.node.scale;
    }
    [self setNeedsLayout];
}

- (SKControlView *)controlAtPoint:(CGPoint)point {
    for (SKControlView *view in _controls.reverseObjectEnumerator) {
        if (CGRectContainsPoint(view.frame, point)) return view;
    }
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.editing) return;
    CGPoint point = [touches.anyObject locationInView:self];
    if (CGRectContainsPoint(_panel.frame, point)) return;

    SKControlView *hit = [self controlAtPoint:point];
    [self selectControl:hit];
    _dragging = hit;
    if (hit) _dragOffset = CGPointMake(point.x - hit.center.x, point.y - hit.center.y);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.editing || !_dragging) return;
    CGPoint point = [touches.anyObject locationInView:self];
    CGFloat halfWidth = _dragging.bounds.size.width * 0.5f;
    CGFloat halfHeight = _dragging.bounds.size.height * 0.5f;
    CGFloat x = MIN(MAX(point.x - _dragOffset.x, halfWidth), self.bounds.size.width - halfWidth);
    CGFloat y = MIN(MAX(point.y - _dragOffset.y, halfHeight), self.bounds.size.height - halfHeight);
    _dragging.center = CGPointMake(x, y);
    _dragging.node.xPercent = x / self.bounds.size.width;
    _dragging.node.yPercent = y / self.bounds.size.height;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _dragging = nil;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _dragging = nil;
}

#pragma mark Panel

- (UILabel *)panelLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    return label;
}

- (UIView *)rowWithLabel:(NSString *)text control:(UIView *)control {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[[self panelLabel:text], control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 12;
    return row;
}

- (void)buildPanel {
    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];
    _panel.layer.cornerRadius = 12;
    _panel.hidden = YES;

    _enableSwitch = [UISwitch new];
    _enableSwitch.onTintColor = SKThemeColor();
    _enableSwitch.on = _layout.controlsEnabled;
    [_enableSwitch addTarget:self action:@selector(onEnableChanged) forControlEvents:UIControlEventValueChanged];

    _actionBarSwitch = [UISwitch new];
    _actionBarSwitch.onTintColor = SKThemeColor();
    _actionBarSwitch.on = _layout.actionBarVisible;
    [_actionBarSwitch addTarget:self action:@selector(onActionBarChanged) forControlEvents:UIControlEventValueChanged];

    _opacitySlider = [UISlider new];
    _opacitySlider.minimumTrackTintColor = SKThemeColor();
    _opacitySlider.minimumValue = SKMinOpacity;
    _opacitySlider.maximumValue = 1.0f;
    _opacitySlider.value = _layout.globalOpacity;
    [_opacitySlider addTarget:self action:@selector(onOpacityChanged) forControlEvents:UIControlEventValueChanged];

    _resolutionSlider = [UISlider new];
    _resolutionSlider.minimumTrackTintColor = SKThemeColor();
    _resolutionSlider.minimumValue = SKMinRenderScale;
    _resolutionSlider.maximumValue = SKMaxRenderScale;
    _resolutionSlider.value = _layout.renderScale;
    // Applied on release rather than per-step: each one rebuilds the drawable and makes SK
    // re-lay out its HUD, which is not something to do on every slider tick.
    [_resolutionSlider addTarget:self
                          action:@selector(onResolutionCommitted)
                forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];
    [_resetButton addTarget:self action:@selector(onResetTapped) forControlEvents:UIControlEventTouchUpInside];

    _nodeTitle = [self panelLabel:@""];
    _visibleSwitch = [UISwitch new];
    _visibleSwitch.onTintColor = SKThemeColor();
    [_visibleSwitch addTarget:self action:@selector(onVisibleChanged) forControlEvents:UIControlEventValueChanged];
    _scaleSlider = [UISlider new];
    _scaleSlider.minimumTrackTintColor = SKThemeColor();
    _scaleSlider.minimumValue = SKMinNodeScale;
    _scaleSlider.maximumValue = SKMaxNodeScale;
    [_scaleSlider addTarget:self action:@selector(onScaleChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *nodeStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _nodeTitle,
        [self rowWithLabel:@"Visible" control:_visibleSwitch],
        [self rowWithLabel:@"Scale" control:_scaleSlider],
    ]];
    nodeStack.axis = UILayoutConstraintAxisVertical;
    nodeStack.spacing = 8;
    _nodeSection = nodeStack;
    _nodeSection.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self panelLabel:@"Touch Controls"],
        [self rowWithLabel:@"Show Controls" control:_enableSwitch],
        [self rowWithLabel:@"Show Buttons" control:_actionBarSwitch],
        [self rowWithLabel:@"Opacity" control:_opacitySlider],
        [self rowWithLabel:@"Resolution" control:_resolutionSlider],
        _resetButton,
        _nodeSection,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-16],
    ]];
    [self addSubview:_panel];
}

- (void)onEnableChanged {
    _layout.controlsEnabled = _enableSwitch.on;
    [self applyAppearance];
}

- (void)onActionBarChanged {
    _layout.actionBarVisible = _actionBarSwitch.on;
    [self applyAppearance];
}

- (void)onOpacityChanged {
    _layout.globalOpacity = _opacitySlider.value;
    [self applyAppearance];
}

- (void)onResolutionCommitted {
    _layout.renderScale = MIN(MAX(_resolutionSlider.value, SKMinRenderScale), SKMaxRenderScale);
    [_layout save];
    [self.delegate touchOverlay:self didChangeRenderScale:_layout.renderScale];
}

- (void)onVisibleChanged {
    _selected.node.visible = _visibleSwitch.on;
    [self applyAppearance];
}

- (void)onScaleChanged {
    _selected.node.scale = _scaleSlider.value;
    [self setNeedsLayout];
}

/// Two-step so a stray tap can't wipe a layout the user spent time arranging.
- (void)onResetTapped {
    if (!_resetArmed) {
        _resetArmed = YES;
        [_resetButton setTitle:@"Tap again to confirm" forState:UIControlStateNormal];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kResetConfirmWindow * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_resetArmed) {
                strongSelf->_resetArmed = NO;
                [strongSelf->_resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];
            }
        });
        return;
    }
    _resetArmed = NO;
    [_resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];

    SKTouchLayout *defaults = [SKTouchLayout defaultLayout];
    _layout.globalOpacity = defaults.globalOpacity;
    _layout.controlsEnabled = defaults.controlsEnabled;
    _layout.actionBarVisible = defaults.actionBarVisible;
    _layout.renderScale = defaults.renderScale;
    for (SKControlNode *fresh in defaults.nodes) {
        for (SKControlView *view in _controls) {
            if (![view.node.nodeId isEqualToString:fresh.nodeId]) continue;
            view.node.xPercent = fresh.xPercent;
            view.node.yPercent = fresh.yPercent;
            view.node.scale = fresh.scale;
            view.node.visible = fresh.visible;
        }
    }
    [_layout save];

    _enableSwitch.on = _layout.controlsEnabled;
    _actionBarSwitch.on = _layout.actionBarVisible;
    _opacitySlider.value = _layout.globalOpacity;
    _resolutionSlider.value = _layout.renderScale;
    [self selectControl:nil];
    [self applyAppearance];
    [self setNeedsLayout];
    [self.delegate touchOverlay:self didChangeRenderScale:_layout.renderScale];
}

@end
