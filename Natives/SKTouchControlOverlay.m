#import "SKTouchControlOverlay.h"
#import "SKDockPlacement.h"

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
/// A floating stick at rest in play mode: drawn faintly, where it will reappear.
@property (nonatomic, assign) BOOL idleGhost;
/// Being held, so the overlay must not move it back to its saved spot.
@property (nonatomic, readonly) BOOL isHeld;
@end

@implementation SKJoystickControl {
    CGPoint _knob;
    BOOL _dragging;
    NSInteger _aimGeneration;
    int _axisX;
    int _axisY;
}

- (BOOL)isHeld {
    return _dragging;
}

- (void)setIdleGhost:(BOOL)idleGhost {
    _idleGhost = idleGhost;
    [self setNeedsDisplay];
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
    // A floating stick waiting for a thumb is only a faint hint of where it will appear.
    BOOL ghost = self.idleGhost && !_dragging;
    [[UIColor colorWithWhite:0.12 alpha:ghost ? 0.19 : 0.40] setFill];
    [base fill];

    UIBezierPath *knob = [UIBezierPath bezierPathWithArcCenter:_knob
                                                        radius:radius * 0.40f
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    [[UIColor colorWithWhite:0.62 alpha:ghost ? 0.30 : 0.80] setFill];
    [knob fill];
}

/// A floating stick starts under the thumb (kept on screen), not at its saved spot.
- (void)floatToTouch:(UITouch *)touch {
    UIView *parent = self.superview;
    if (!parent) return;
    CGPoint p = [touch locationInView:parent];
    CGFloat halfW = self.bounds.size.width * 0.5f, halfH = self.bounds.size.height * 0.5f;
    self.center = CGPointMake(MIN(MAX(p.x, halfW), MAX(halfW, parent.bounds.size.width - halfW)),
                              MIN(MAX(p.y, halfH), MAX(halfH, parent.bounds.size.height - halfH)));
}

- (void)updateForTouch:(UITouch *)touch {
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;
    CGFloat maxDistance = radius * kJoystickTravel;
    UIView *parent = self.superview;

    // Past its travel a floating stick's base is dragged along, so the thumb never runs out of room.
    if (self.node.floating && parent && maxDistance > 0) {
        CGPoint p = [touch locationInView:parent];
        CGFloat ex = p.x - self.center.x, ey = p.y - self.center.y;
        CGFloat d = hypot(ex, ey);
        if (d > maxDistance) {
            CGFloat pull = (d - maxDistance) / d;
            CGFloat halfW = self.bounds.size.width * 0.5f, halfH = self.bounds.size.height * 0.5f;
            self.center = CGPointMake(MIN(MAX(self.center.x + ex * pull, halfW), MAX(halfW, parent.bounds.size.width - halfW)),
                                      MIN(MAX(self.center.y + ey * pull, halfH), MAX(halfH, parent.bounds.size.height - halfH)));
        }
    }

    CGPoint point = [touch locationInView:self];
    CGPoint centre = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));

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
    if (self.node.floating) [self floatToTouch:touches.anyObject];
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
    [self.superview setNeedsLayout];  // a floating stick goes back to its saved spot

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
    [self.superview setNeedsLayout];
}

@end

#import "SKGfxSettings.h"

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
    UIButton *_layoutsButton;
    UIStackView *_panelStack;
    UISwitch *_fpsSwitch;
    UISwitch *_cursorSwitch;
    UISwitch *_avoidEdgesSwitch;
    UISlider *_sharpenSlider;
    UILabel *_sharpenLabel;
    UISwitch *_hudSwitch;
    UIView *_nodeSection;
    UILabel *_nodeTitle;
    UISwitch *_visibleSwitch;
    UISlider *_scaleSlider;
    UIStackView *_nodeStack;
    UISegmentedControl *_tabs;
    UISwitch *_floatLeftSwitch;
    UISwitch *_floatRightSwitch;
    /// 0 = arranging controls (a small dialog only for the selected one), 1 = the full settings panel.
    NSInteger _page;

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
    // A floating stick takes touches anywhere on its half of the screen, but a button or the
    // other controls under the thumb win: only a touch that would reach the game is claimed.
    if (hit == self) return [self floatingStickAtPoint:point];
    return hit;
}

- (SKJoystickControl *)floatingStickAtPoint:(CGPoint)point {
    BOOL rightHalf = point.x >= self.bounds.size.width * 0.5f;
    for (SKControlView *view in _controls.reverseObjectEnumerator) {
        if (![view isKindOfClass:SKJoystickControl.class] || view.hidden || !view.node.floating) continue;
        if ((view.node.type == SKControlTypeJoystickRight) == rightHalf) return (SKJoystickControl *)view;
    }
    return nil;
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
        // A floating stick under a thumb moves itself; it goes home when released.
        if ([view isKindOfClass:SKJoystickControl.class] && ((SKJoystickControl *)view).isHeld) continue;
        view.center = CGPointMake(width * node.xPercent, height * node.yPercent);
    }

    // The tab strip sits at the top centre; everything else keeps clear of it.
    CGFloat tabsWidth = MIN(210.0f, width - 180.0f);
    _tabs.frame = CGRectMake((width - tabsWidth) * 0.5f, 10, tabsWidth, 32);
    CGFloat top = CGRectGetMaxY(_tabs.frame) + 10;

    // The panel's height comes from its stack's constraints; sizeToFit would return the
    // frame unchanged because the panel itself is autoresizing-sized.
    CGFloat panelWidth = MIN(320.0f, width - 40.0f);
    CGFloat contentHeight = [_panelStack systemLayoutSizeFittingSize:CGSizeMake(panelWidth - 32.0f, 0)
                                       withHorizontalFittingPriority:UILayoutPriorityRequired
                                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height + 32.0f;
    // Taller than the screen: the panel scrolls. It centres in the room below the tab strip.
    CGFloat room = height - top - 12.0f;
    CGFloat panelHeight = MIN(contentHeight, room);
    _panel.frame = CGRectMake((width - panelWidth) * 0.5f, top + (room - panelHeight) * 0.5f,
                              panelWidth, panelHeight);

    [self dockNodePanel];
}

/// The selected control's dialog goes where it never covers that control (the player is dragging it),
/// the tab strip or Done, and covers as few other controls as it can (see SKDockPlacement.h).
- (void)dockNodePanel {
    if (_nodeSection.hidden || !_selected) return;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat dialogWidth = MIN(240.0f, width - 24.0f);
    CGFloat dialogHeight = [_nodeStack systemLayoutSizeFittingSize:CGSizeMake(dialogWidth - 24.0f, 0)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height + 24.0f;
    CGRect reserved[2] = {CGRectInset(_tabs.frame, -8, -8), CGRectMake(width - 150, 0, 150, 64)};
    CGRect others[64];
    int count = 0;
    for (SKControlView *view in _controls) {
        if (view != _selected && count < 64) others[count++] = view.frame;
    }
    CGPoint origin = SKDockPlace(CGSizeMake(width, height), CGSizeMake(dialogWidth, dialogHeight), _selected.frame,
                                 reserved, 2, others, count, 12, 16);
    _nodeSection.frame = CGRectMake(origin.x, origin.y, dialogWidth, dialogHeight);
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
    // Only the Edit page shows the arranging look; the Settings page shows the controls as they play, untouchable.
    BOOL editLook = self.editing && _page == 0;
    for (SKControlView *view in _controls) {
        SKControlNode *node = view.node;
        if (editLook) {
            view.hidden = NO;
            BOOL shown = node.visible && ![self isHiddenByShowButtons:node];
            view.alpha = shown ? MAX(_layout.globalOpacity, kEditMinOpacity) : kEditHiddenOpacity;
            view.outline.hidden = NO;
        } else {
            view.hidden =
              !(_layout.controlsEnabled && node.visible && ![self isHiddenByShowButtons:node]);
            view.alpha = _layout.globalOpacity;
            view.outline.hidden = YES;
        }
        // While editing the overlay drives selection/drag itself, and the Settings page must not press anything.
        view.userInteractionEnabled = !self.editing;
        if ([view isKindOfClass:SKJoystickControl.class]) ((SKJoystickControl *)view).idleGhost = node.floating && !self.editing;
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
    _tabs.hidden = !_editing;
    if (!_editing) {
        [self selectControl:nil];
        [_layout save];
    }
    [self showPage:0];
}

/// 0 = Edit, 1 = Settings. The tab strip is the way between them; the panel and the selected
/// control's dialog are never up together.
- (void)showPage:(NSInteger)page {
    _page = page;
    _tabs.selectedSegmentIndex = page;
    _panel.hidden = !(_editing && page == 1);
    if (page == 1) [self selectControl:nil];
    _nodeSection.hidden = !(_editing && page == 0 && _selected);
    [self applyAppearance];
    [self setNeedsLayout];
}

- (void)onTabChanged {
    [self showPage:_tabs.selectedSegmentIndex];
}

- (void)selectControl:(SKControlView *)control {
    _selected.selectedForEdit = NO;
    _selected = control;
    _selected.selectedForEdit = YES;

    _nodeSection.hidden = !(_editing && _page == 0 && control);
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
    // Only the Edit page arranges controls; on Settings a tap on the bare backdrop does nothing.
    if (!self.editing || _page != 0) return;
    CGPoint point = [touches.anyObject locationInView:self];
    if (CGRectContainsPoint(_panel.frame, point)) return;
    if (!_nodeSection.hidden && CGRectContainsPoint(_nodeSection.frame, point)) return;

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
    [self setNeedsLayout];  // re-dock the dialog for the control's new spot
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _dragging = nil;
    [self setNeedsLayout];
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

    [_resolutionSlider addTarget:self action:@selector(onResolutionMoved) forControlEvents:UIControlEventValueChanged];

    // Graphics (skgfx.c). Stored apart from the touch layout, so Reset Layout leaves them alone.
    _fpsSwitch = [UISwitch new];
    _fpsSwitch.onTintColor = SKThemeColor();
    _fpsSwitch.on = SKGfxShowFps();
    [_fpsSwitch addTarget:self action:@selector(onFpsChanged) forControlEvents:UIControlEventValueChanged];

    // The same setting as the launcher sidebar's "Avoid screen edges"; absent means off.
    _avoidEdgesSwitch = [UISwitch new];
    _avoidEdgesSwitch.onTintColor = SKThemeColor();
    _avoidEdgesSwitch.on = [[NSUserDefaults.standardUserDefaults objectForKey:@"avoid_screen_edges"] boolValue];
    [_avoidEdgesSwitch addTarget:self action:@selector(onAvoidEdgesChanged) forControlEvents:UIControlEventValueChanged];

    _cursorSwitch = [UISwitch new];
    _cursorSwitch.onTintColor = SKThemeColor();
    _cursorSwitch.on = SKShowMouseCursor();
    [_cursorSwitch addTarget:self action:@selector(onCursorChanged) forControlEvents:UIControlEventValueChanged];

    _sharpenLabel = [self panelLabel:@""];
    _sharpenSlider = [UISlider new];
    _sharpenSlider.minimumTrackTintColor = SKThemeColor();
    _sharpenSlider.minimumValue = 0;
    _sharpenSlider.maximumValue = 100;
    _sharpenSlider.value = SKGfxSharpenPercent();
    [_sharpenSlider addTarget:self action:@selector(onSharpenMoved) forControlEvents:UIControlEventValueChanged];
    // Applied on release, like the resolution: the drawable may be rebuilt.
    [_sharpenSlider addTarget:self
                       action:@selector(onSharpenCommitted)
             forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    UIButton *sharpenReset = [UIButton buttonWithType:UIButtonTypeSystem];
    [sharpenReset setTitle:@"Reset" forState:UIControlStateNormal];
    [sharpenReset addTarget:self action:@selector(onSharpenReset) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *sharpenRow = [[UIStackView alloc] initWithArrangedSubviews:@[_sharpenSlider, sharpenReset]];
    sharpenRow.axis = UILayoutConstraintAxisHorizontal;
    sharpenRow.spacing = 12;

    _hudSwitch = [UISwitch new];
    _hudSwitch.onTintColor = SKThemeColor();
    _hudSwitch.on = SKGfxSharpHud();
    [_hudSwitch addTarget:self action:@selector(onHudChanged) forControlEvents:UIControlEventValueChanged];

    [self refreshGfxPanel];

    // Layout library: presets, export, import. The host provides it (it presents the file
    // pickers), so the button stays hidden until a host sets one.
    _layoutsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_layoutsButton setTitle:NSLocalizedString(@"Layouts…", nil) forState:UIControlStateNormal];
    [_layoutsButton addTarget:self action:@selector(onLayoutsTapped) forControlEvents:UIControlEventTouchUpInside];
    _layoutsButton.hidden = (self.layoutLibraryHandler == nil);

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

    // The selected control's dialog: its own card, docked clear of the control (dockNodePanel), not part of the panel.
    _nodeStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _nodeTitle,
        [self rowWithLabel:@"Visible" control:_visibleSwitch],
        [self rowWithLabel:@"Scale" control:_scaleSlider],
    ]];
    _nodeStack.axis = UILayoutConstraintAxisVertical;
    _nodeStack.spacing = 8;
    _nodeStack.frame = CGRectMake(12, 12, 216, 100);
    _nodeSection = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 124)];
    _nodeSection.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];
    _nodeSection.layer.cornerRadius = 12;
    _nodeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_nodeSection addSubview:_nodeStack];
    [NSLayoutConstraint activateConstraints:@[
        [_nodeStack.leadingAnchor constraintEqualToAnchor:_nodeSection.leadingAnchor constant:12],
        [_nodeStack.trailingAnchor constraintEqualToAnchor:_nodeSection.trailingAnchor constant:-12],
        [_nodeStack.topAnchor constraintEqualToAnchor:_nodeSection.topAnchor constant:12],
    ]];
    _nodeSection.hidden = YES;

    // Floating sticks, one switch each (saved in the layout).
    _floatLeftSwitch = [UISwitch new];
    _floatLeftSwitch.onTintColor = SKThemeColor();
    [_floatLeftSwitch addTarget:self action:@selector(onFloatChanged:) forControlEvents:UIControlEventValueChanged];
    _floatRightSwitch = [UISwitch new];
    _floatRightSwitch.onTintColor = SKThemeColor();
    [_floatRightSwitch addTarget:self action:@selector(onFloatChanged:) forControlEvents:UIControlEventValueChanged];
    [self syncFloatSwitches];

    _tabs = [[UISegmentedControl alloc] initWithItems:@[
        NSLocalizedString(@"Edit", nil), NSLocalizedString(@"Settings", nil)]];
    _tabs.selectedSegmentIndex = 0;
    _tabs.selectedSegmentTintColor = SKThemeColor();
    [_tabs setTitleTextAttributes:@{NSForegroundColorAttributeName : UIColor.whiteColor} forState:UIControlStateNormal];
    [_tabs setTitleTextAttributes:@{NSForegroundColorAttributeName : UIColor.whiteColor} forState:UIControlStateSelected];
    _tabs.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];
    _tabs.hidden = YES;
    [_tabs addTarget:self action:@selector(onTabChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self panelLabel:@"Touch Controls"],
        [self rowWithLabel:@"Show Controls" control:_enableSwitch],
        [self rowWithLabel:@"Show Buttons" control:_actionBarSwitch],
        [self rowWithLabel:@"Opacity" control:_opacitySlider],
        [self rowWithLabel:@"Resolution" control:_resolutionSlider],
        [self rowWithLabel:NSLocalizedString(@"Avoid screen edges", nil) control:_avoidEdgesSwitch],
        [self rowWithLabel:@"Show FPS counter" control:_fpsSwitch],
        [self rowWithLabel:NSLocalizedString(@"Show mouse cursor", nil) control:_cursorSwitch],
        _sharpenLabel,
        sharpenRow,
        [self rowWithLabel:@"Sharp HUD (experimental)" control:_hudSwitch],
        [self rowWithLabel:NSLocalizedString(@"Floating left stick", nil) control:_floatLeftSwitch],
        [self rowWithLabel:NSLocalizedString(@"Floating right stick", nil) control:_floatRightSwitch],
        _layoutsButton,
        _resetButton,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    _panelStack = stack;
    // The panel scrolls: the graphics rows make it taller than a landscape phone.
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.delaysContentTouches = NO;  // sliders in here must respond at once
    [_panel addSubview:scroll];
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_panel.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];
    [self addSubview:_panel];
    [self addSubview:_nodeSection];
    [self addSubview:_tabs];
}

- (void)syncFloatSwitches {
    for (SKControlNode *node in _layout.nodes) {
        if (node.type == SKControlTypeJoystickLeft) _floatLeftSwitch.on = node.floating;
        if (node.type == SKControlTypeJoystickRight) _floatRightSwitch.on = node.floating;
    }
}

- (void)onFloatChanged:(UISwitch *)sender {
    SKControlType type = (sender == _floatLeftSwitch) ? SKControlTypeJoystickLeft : SKControlTypeJoystickRight;
    for (SKControlNode *node in _layout.nodes) {
        if (node.type == type) node.floating = sender.on;
    }
    [self applyAppearance];
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

#pragma mark Graphics

/// Sharp HUD needs a scene smaller than the window, so it is greyed out at 100% resolution, with the
/// hint saying what to change. The hint also says what the offscreen features have in common.
- (void)refreshGfxPanel {
    int percent = (int)lround(_sharpenSlider.value);
    _sharpenLabel.text = percent > 0 ? [NSString stringWithFormat:@"Sharpening: %d%%", percent] : @"Sharpening: off";
    float scale = _resolutionSlider ? _resolutionSlider.value : _layout.renderScale;
    BOOL applies = SKGfxSharpHudApplies(scale);
    _hudSwitch.enabled = applies;
    _hudSwitch.alpha = applies ? 1.0f : 0.4f;
}

- (void)gfxChanged {
    if ([self.delegate respondsToSelector:@selector(touchOverlayDidChangeGfx:)])
        [self.delegate touchOverlayDidChangeGfx:self];
}

- (void)onFpsChanged {
    SKGfxSetShowFps(_fpsSwitch.on);
    if ([self.delegate respondsToSelector:@selector(touchOverlay:didChangeFpsVisible:)])
        [self.delegate touchOverlay:self didChangeFpsVisible:_fpsSwitch.on];
}

- (void)onAvoidEdgesChanged {
    [NSUserDefaults.standardUserDefaults setBool:_avoidEdgesSwitch.on forKey:@"avoid_screen_edges"];
    if ([self.delegate respondsToSelector:@selector(touchOverlay:didChangeAvoidEdges:)])
        [self.delegate touchOverlay:self didChangeAvoidEdges:_avoidEdgesSwitch.on];
}

- (void)onCursorChanged {
    SKSetShowMouseCursor(_cursorSwitch.on);
    if ([self.delegate respondsToSelector:@selector(touchOverlay:didChangeCursorVisible:)])
        [self.delegate touchOverlay:self didChangeCursorVisible:_cursorSwitch.on];
}

- (void)onSharpenMoved {
    [self refreshGfxPanel];
}

- (void)onSharpenCommitted {
    SKGfxSetSharpenPercent((int)lround(_sharpenSlider.value));
    [self gfxChanged];
}

- (void)onSharpenReset {
    _sharpenSlider.value = 0;
    [self refreshGfxPanel];
    [self onSharpenCommitted];
}

- (void)onHudChanged {
    SKGfxSetSharpHud(_hudSwitch.on);
    [self gfxChanged];
}

- (void)onResolutionMoved {
    [self refreshGfxPanel];
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
            view.node.floating = fresh.floating;
        }
    }
    [_layout save];
    [self syncFloatSwitches];

    _enableSwitch.on = _layout.controlsEnabled;
    _actionBarSwitch.on = _layout.actionBarVisible;
    _opacitySlider.value = _layout.globalOpacity;
    _resolutionSlider.value = _layout.renderScale;
    [self refreshGfxPanel];
    [self selectControl:nil];
    [self applyAppearance];
    [self setNeedsLayout];
    [self.delegate touchOverlay:self didChangeRenderScale:_layout.renderScale];
}

- (void)setLayoutLibraryHandler:(void (^)(void))handler {
    _layoutLibraryHandler = [handler copy];
    _layoutsButton.hidden = (_layoutLibraryHandler == nil);
}

- (void)onLayoutsTapped {
    if (self.layoutLibraryHandler) self.layoutLibraryHandler();
}

- (void)applySharedLayout:(SKSharedLayout *)shared {
    [_layout applySharedLayout:shared];  // mutates the nodes the control views hold
    [_layout save];

    _actionBarSwitch.on = _layout.actionBarVisible;
    _opacitySlider.value = _layout.globalOpacity;
    [self syncFloatSwitches];
    [self selectControl:nil];
    [self applyAppearance];
    [self setNeedsLayout];
}

@end
