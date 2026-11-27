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

/// A floating stick's zone is this many stick-diameters across, and this far (pt) from the screen edges.
static const CGFloat SKFloatZoneFactor = 1.5f;
static const CGFloat SKFloatZoneMargin = 12.0f;
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

#pragma mark - Button glyphs

/// Icons for the combat buttons, vector glyphs on a 24x24 grid instead of text. The path data and colours
/// are identical to Android's (ControlGlyphs.kt): keep the two in step. The colours come from the game's own
/// HUD icons: attack red, buff-ring cyan for Dodge, the stun star's gold for Bash; Defend is a deeper blue so
/// it reads apart from Dodge, Strafe stays neutral.
static const CGFloat SKGlyphGrid = 24.0f;

@interface SKGlyph : NSObject
@property (nonatomic, copy) NSString *pathData;
@property (nonatomic, strong) UIColor *color;
/// Neutral glyphs keep the plain dark button; the rest are tinted in their colour.
@property (nonatomic, assign) BOOL tinted;
@end
@implementation SKGlyph
@end

static SKGlyph *SKGlyphForNode(NSString *nodeId) {
    static NSDictionary<NSString *, SKGlyph *> *glyphs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      SKGlyph * (^make)(NSString *, uint32_t, BOOL) = ^SKGlyph *(NSString *path, uint32_t rgb, BOOL tinted) {
        SKGlyph *glyph = [SKGlyph new];
        glyph.pathData = path;
        glyph.color = [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                                      green:((rgb >> 8) & 0xFF) / 255.0
                                       blue:(rgb & 0xFF) / 255.0
                                      alpha:1.0];
        glyph.tinted = tinted;
        return glyph;
      };
      glyphs = @{
          // Two opposed arrows: strafe lock.
          @"btn_strafe" : make(@"M2 6 L15 6 L15 3.5 L22 7.5 L15 11.5 L15 9 L2 9 Z "
                               @"M22 15 L9 15 L9 12.5 L2 16.5 L9 20.5 L9 18 L22 18 Z", 0xFFFFFF, NO),
          // Shield.
          @"btn_defend" : make(@"M12 2 L20 5 L20 11 C20 16.5 16.5 20.5 12 22 C7.5 20.5 4 16.5 4 11 L4 5 Z",
                               0x3B82F6, YES),
          // Sword, tip up and to the right.
          @"btn_attack" : make(@"M19.4 4.6 L18.6 8.7 L11.5 15.7 L8.3 12.5 L15.3 5.4 Z "
                               @"M5.8 10.0 L14.0 18.2 L12.3 19.9 L4.1 11.7 Z "
                               @"M7.3 15.0 L9.0 16.7 L6.5 19.2 L4.8 17.5 Z "
                               @"M4.2 16.9 L7.1 19.8 L6.0 21.0 L3.0 18.0 Z", 0xEB2121, YES),
          // Double chevron: a dash.
          @"btn_dodge" : make(@"M3 5 L10 12 L3 19 L6.6 19 L13.6 12 L6.6 5 Z "
                              @"M11 5 L18 12 L11 19 L14.6 19 L21.6 12 L14.6 5 Z", 0x28D9FF, YES),
          // The stun star.
          @"btn_shieldbash" : make(@"M12.0 1.5 L14.6 8.4 L22.0 8.8 L16.2 13.4 L18.2 20.5 L12.0 16.4 "
                                   @"L5.8 20.5 L7.8 13.4 L2.0 8.8 L9.4 8.4 Z", 0xFEB200, YES),
      };
    });
    return glyphs[nodeId];
}

/// Parses the glyphs' path data: absolute M, L, C and Z only, which is all they use.
static UIBezierPath *SKGlyphPath(NSString *data) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSRegularExpression *token = [NSRegularExpression regularExpressionWithPattern:@"[MLCZ]|-?[0-9]*\\.?[0-9]+"
                                                                           options:0
                                                                             error:nil];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSTextCheckingResult *match in [token matchesInString:data options:0 range:NSMakeRange(0, data.length)]) {
        [tokens addObject:[data substringWithRange:match.range]];
    }
    __block NSUInteger i = 0;
    CGFloat (^num)(void) = ^CGFloat {
      return i < tokens.count ? tokens[i++].doubleValue : 0;
    };
    while (i < tokens.count) {
        NSString *cmd = tokens[i++];
        if ([cmd isEqualToString:@"M"]) {
            CGFloat x = num(), y = num();
            [path moveToPoint:CGPointMake(x, y)];
        } else if ([cmd isEqualToString:@"L"]) {
            CGFloat x = num(), y = num();
            [path addLineToPoint:CGPointMake(x, y)];
        } else if ([cmd isEqualToString:@"C"]) {
            CGFloat x1 = num(), y1 = num(), x2 = num(), y2 = num(), x = num(), y = num();
            [path addCurveToPoint:CGPointMake(x, y) controlPoint1:CGPointMake(x1, y1) controlPoint2:CGPointMake(x2, y2)];
        } else if ([cmd isEqualToString:@"Z"]) {
            [path closePath];
        }
    }
    return path;
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
    /// The icon, for a combat button; the label is hidden then.
    SKGlyph *_glyph;
    CAShapeLayer *_glyphLayer;
    UIBezierPath *_glyphPath;
    BOOL _pressed;
    BOOL _toggledOn;
}

- (instancetype)initWithNode:(SKControlNode *)node {
    self = [super initWithNode:node];
    if (!self) return nil;
    self.layer.borderWidth = 1.0f;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;

    _glyph = SKGlyphForNode(node.nodeId);
    if (_glyph) {
        _glyphPath = SKGlyphPath(_glyph.pathData);
        _glyphLayer = [CAShapeLayer layer];
        _glyphLayer.fillColor = _glyph.color.CGColor;
        _glyphLayer.fillRule = kCAFillRuleNonZero;
        [self.layer addSublayer:_glyphLayer];
        if (_glyph.tinted) self.layer.borderColor = [_glyph.color colorWithAlphaComponent:0.6].CGColor;
    }

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.hidden = _glyph != nil;
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
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = size * 0.24f;
    if (_glyphLayer) {
        // The glyph fills 56% of the button, centred.
        CGFloat glyphSize = size * 0.56f;
        CGFloat scale = glyphSize / SKGlyphGrid;
        UIBezierPath *placed = [_glyphPath copy];
        [placed applyTransform:CGAffineTransformMakeScale(scale, scale)];
        [placed applyTransform:CGAffineTransformMakeTranslation((self.bounds.size.width - glyphSize) * 0.5f,
                                                                (self.bounds.size.height - glyphSize) * 0.5f)];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _glyphLayer.frame = self.bounds;
        _glyphLayer.path = placed.CGPath;
        [CATransaction commit];
    }
}

- (void)refreshFill {
    BOOL lit = _pressed || _toggledOn;
    if (_glyph.tinted) {
        // The dark button with a wash of the glyph's colour, stronger while pressed.
        CGFloat r, g, b, a;
        [_glyph.color getRed:&r green:&g blue:&b alpha:&a];
        CGFloat wash = lit ? 0.50 : 0.20, base = 0.12;
        self.backgroundColor = [UIColor colorWithRed:base * (1 - wash) + r * wash
                                               green:base * (1 - wash) + g * wash
                                                blue:base * (1 - wash) + b * wash
                                               alpha:lit ? 0.85 : 0.65];
        return;
    }
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
/// Radius of the stick itself. A floating stick's view is the larger square zone it moves in, so the
/// overlay says how big the stick inside it is; a fixed stick fills its view.
@property (nonatomic, assign) CGFloat stickRadius;
@end

@implementation SKJoystickControl {
    CGPoint _knob;
    /// Where the stick's centre is inside the view: the middle, except a floating stick following the thumb.
    CGPoint _base;
    BOOL _dragging;
    NSInteger _aimGeneration;
    int _axisX;
    int _axisY;
}

- (void)setStickRadius:(CGFloat)stickRadius {
    _stickRadius = stickRadius;
    [self setNeedsDisplay];
}

- (CGFloat)radius {
    if (self.node.floating && _stickRadius > 0) return _stickRadius;
    return MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;
}

- (CGPoint)middle {
    return CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

/// Moves the base to [point] (view coordinates), kept inside the zone; returns how far it moved.
- (CGPoint)placeBase:(CGPoint)point {
    CGFloat r = [self radius];
    CGFloat x = MIN(MAX(point.x, r), MAX(r, self.bounds.size.width - r));
    CGFloat y = MIN(MAX(point.y, r), MAX(r, self.bounds.size.height - r));
    CGPoint moved = CGPointMake(x - _base.x, y - _base.y);
    _base = CGPointMake(x, y);
    return moved;
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
    if (!_dragging) {
        _base = [self middle];
        _knob = _base;
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat radius = [self radius];
    BOOL floating = self.node.floating;

    if (floating) {
        // The zone the stick may start in: a rounded square, always shown so the player knows where
        // to put a thumb. The stick itself only appears under a held thumb.
        CGRect zone = CGRectInset(self.bounds, 0.5f, 0.5f);
        UIBezierPath *square = [UIBezierPath bezierPathWithRoundedRect:zone
                                                          cornerRadius:MIN(zone.size.width, zone.size.height) * 0.12f];
        [[UIColor colorWithWhite:0.12 alpha:0.40] setFill];
        [square fill];
        [[UIColor colorWithWhite:1 alpha:0.28] setStroke];
        square.lineWidth = 1;
        [square stroke];
    }

    UIBezierPath *base = [UIBezierPath bezierPathWithArcCenter:_base
                                                        radius:radius - 2
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    // A floating stick waiting for a thumb is only a faint hint of where it will appear.
    BOOL ghost = floating && !_dragging;
    [[UIColor colorWithWhite:0.12 alpha:ghost ? 0.19 : 0.40] setFill];
    [base fill];

    if (ghost) return;
    UIBezierPath *knob = [UIBezierPath bezierPathWithArcCenter:_knob
                                                        radius:radius * 0.40f
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    [[UIColor colorWithWhite:0.62 alpha:0.80] setFill];
    [knob fill];
}

- (void)updateForTouch:(UITouch *)touch {
    CGFloat radius = [self radius];
    CGFloat maxDistance = radius * kJoystickTravel;
    CGPoint point = [touch locationInView:self];

    // Past its travel a floating stick's base is dragged along, so the thumb never runs out of room.
    // It stays inside the zone.
    if (self.node.floating && maxDistance > 0) {
        CGFloat ex = point.x - _base.x, ey = point.y - _base.y;
        CGFloat d = hypot(ex, ey);
        if (d > maxDistance) {
            CGFloat pull = (d - maxDistance) / d;
            [self placeBase:CGPointMake(_base.x + ex * pull, _base.y + ey * pull)];
        }
    }

    CGPoint centre = _base;

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
    // A floating stick starts anywhere in its zone, under the thumb.
    if (self.node.floating) [self placeBase:[touches.anyObject locationInView:self]];
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
    // A floating stick goes back to the middle of its zone.
    _base = [self middle];
    _knob = _base;
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
    _base = [self middle];
    _knob = _base;
    [self setNeedsDisplay];
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
    // A floating stick's view is its zone, so it is hit like any control; buttons are added after
    // the sticks, so one lying over the zone wins. Anything else falls through to the game.
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
        // A floating stick lives in a square zone in its bottom corner (left stick bottom-left, right
        // stick bottom-right), not at a saved spot; the stick appears inside it.
        if ([view isKindOfClass:SKJoystickControl.class] && node.floating) {
            CGFloat margin = SKFloatZoneMargin;
            CGFloat zone = MIN(MIN(size * SKFloatZoneFactor, height * 0.62f), width * 0.36f);
            CGFloat zoneX = (node.type == SKControlTypeJoystickLeft) ? margin : width - margin - zone;
            ((SKJoystickControl *)view).stickRadius = MIN(size * 0.5f, zone * 0.5f);
            view.bounds = CGRectMake(0, 0, zone, zone);
            view.center = CGPointMake(zoneX + zone * 0.5f, height - margin - zone * 0.5f);
            continue;
        }
        view.bounds = CGRectMake(0, 0, size, size);
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
    // A floating stick's zone is fixed in its corner, so it is not dragged.
    if (_dragging.node.floating) return;
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
