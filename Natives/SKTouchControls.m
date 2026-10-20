#import "SKTouchControls.h"

// 0.6, not 0.5: at half scale a 1080p-tall device renders a 540 px surface and SK's
// own UI stops laying out -- character select never appears. 578 px worked, 540 did
// not, so the floor sits above that with room to spare.
// Fully transparent controls are unusable and there is no way back except Reset.
const CGFloat SKMinOpacity = 0.2f;
const CGFloat SKDefaultOpacity = 0.4f;

const CGFloat SKMinRenderScale = 0.6f;
const CGFloat SKMaxRenderScale = 1.0f;
const CGFloat SKMinNodeScale = 0.5f;
const CGFloat SKMaxNodeScale = 2.5f;

const CGFloat SKEscXPercent = 0.06f;
const CGFloat SKEscYPercent = 0.10f;
const CGFloat SKButtonWidthPercent = 0.067f;

static NSString *const kDefaultsKey = @"touch_controls_layout";

static NSString *SKControlTypeToString(SKControlType type) {
    switch (type) {
        case SKControlTypeJoystickLeft:  return @"JOYSTICK_LEFT";
        case SKControlTypeJoystickRight: return @"JOYSTICK_RIGHT";
        default:                         return @"BUTTON";
    }
}

static SKControlType SKControlTypeFromString(NSString *string) {
    if ([string isEqualToString:@"JOYSTICK_LEFT"])  return SKControlTypeJoystickLeft;
    if ([string isEqualToString:@"JOYSTICK_RIGHT"]) return SKControlTypeJoystickRight;
    return SKControlTypeButton;
}

@implementation SKControlNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _scale = 1.0f;
        _visible = YES;
        _buttonCode = -1;
        _keyCode = -1;
        _label = @"";
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.nodeId ?: @"",
        @"type": SKControlTypeToString(self.type),
        @"xPercent": @(self.xPercent),
        @"yPercent": @(self.yPercent),
        @"scale": @(self.scale),
        @"visible": @(self.visible),
        @"buttonCode": @(self.buttonCode),
        @"keyCode": @(self.keyCode),
        @"isAxisTrigger": @(self.isAxisTrigger),
        @"isToggle": @(self.isToggle),
        @"label": self.label ?: @"",
    };
}

/// Membership of the bottom action row is a property of the control, not of user state, so
/// derive it from the id instead of persisting it -- layouts saved by older builds then pick
/// it up for free.
static BOOL SKIsActionBarNode(NSString *nodeId) {
    return [nodeId hasPrefix:@"btn_ab"] || [nodeId hasPrefix:@"btn_item"];
}

/// Same reasoning as isActionBar: a control's label is fixed by its identity, never edited
/// by the user, so re-derive it rather than trusting whatever an older build persisted.
static NSString *SKLabelForNode(NSString *nodeId, NSString *persisted) {
    static NSDictionary<NSString *, NSString *> *labels = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      labels = @{
          @"btn_ab1" : @"1",   @"btn_ab2" : @"2",   @"btn_ab3" : @"3",
          @"btn_item1" : @"4", @"btn_item2" : @"5", @"btn_item3" : @"6", @"btn_item4" : @"7",
      };
    });
    return labels[nodeId] ?: (persisted ?: @"");
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *nodeId = dict[@"id"];
    if (![nodeId isKindOfClass:NSString.class] || nodeId.length == 0) return nil;
    SKControlNode *node = [SKControlNode new];
    node.nodeId = nodeId;
    node.isActionBar = SKIsActionBarNode(nodeId);
    node.type = SKControlTypeFromString(dict[@"type"]);
    node.xPercent = [dict[@"xPercent"] doubleValue];
    node.yPercent = [dict[@"yPercent"] doubleValue];
    node.visible = [dict[@"visible"] boolValue];
    node.buttonCode = [dict[@"buttonCode"] ?: @(-1) integerValue];
    node.keyCode = [dict[@"keyCode"] ?: @(-1) integerValue];
    node.isAxisTrigger = [dict[@"isAxisTrigger"] boolValue];
    node.isToggle = [dict[@"isToggle"] boolValue];
    node.label = SKLabelForNode(nodeId, dict[@"label"]);
    // A layout saved before `scale` existed would decode as 0 and lay out at zero size.
    CGFloat scale = [dict[@"scale"] doubleValue];
    node.scale = (scale <= 0) ? 1.0f : MIN(MAX(scale, SKMinNodeScale), SKMaxNodeScale);
    return node;
}

@end

@implementation SKTouchLayout

+ (SKControlNode *)nodeWithId:(NSString *)nodeId
                         type:(SKControlType)type
                        label:(NSString *)label
                            x:(CGFloat)x
                            y:(CGFloat)y {
    SKControlNode *node = [SKControlNode new];
    node.nodeId = nodeId;
    node.isActionBar = SKIsActionBarNode(nodeId);
    node.type = type;
    node.label = label;
    node.xPercent = x;
    node.yPercent = y;
    return node;
}

+ (instancetype)defaultLayout {
    SKTouchLayout *layout = [SKTouchLayout new];
    layout.globalOpacity = SKDefaultOpacity;
    layout.controlsEnabled = YES;
    layout.actionBarVisible = NO;
    // Half resolution by default: SK sizes its HUD in raw framebuffer pixels, so at native
    // retina density the UI is too small to read or tap.
    layout.renderScale = SKMinRenderScale;
    layout.nodes = [NSMutableArray array];

    void (^add)(SKControlNode *) = ^(SKControlNode *node) { [layout.nodes addObject:node]; };

    add([self nodeWithId:@"joy_move" type:SKControlTypeJoystickLeft label:@"" x:0.15 y:0.70]);
    add([self nodeWithId:@"joy_face" type:SKControlTypeJoystickRight label:@"" x:0.85 y:0.70]);

    SKControlNode *esc = [self nodeWithId:@"btn_esc"
                                     type:SKControlTypeButton
                                    label:@"ESC"
                                        x:SKEscXPercent
                                        y:SKEscYPercent];
    esc.keyCode = 256;  // GLFW_KEY_ESCAPE
    add(esc);

    SKControlNode *strafe = [self nodeWithId:@"btn_strafe" type:SKControlTypeButton label:@"Strafe" x:0.28 y:0.72];
    strafe.buttonCode = 10;  // right thumb
    strafe.isToggle = YES;
    add(strafe);

    SKControlNode *defend = [self nodeWithId:@"btn_defend" type:SKControlTypeButton label:@"Defend" x:0.72 y:0.72];
    defend.buttonCode = 4;  // left trigger axis
    defend.isAxisTrigger = YES;
    add(defend);

    struct { NSString *nodeId; NSString *label; CGFloat x; CGFloat y; NSInteger button; } plain[] = {
        {@"btn_dodge",      @"Dodge", 0.78, 0.45,  9},
        {@"btn_shieldbash", @"Bash",  0.88, 0.45,  3},
        {@"btn_prevweap",   @"↑", 0.95, 0.55, 4},
        {@"btn_nextweap",   @"↓", 0.95, 0.85, 5},
        // Bottom action row, 1-7. Buttons are width*0.067 across and spaced 0.07 apart, so
        // they nearly touch; the extra 0.03 before button 4 separates attacks from items.
        // Keep these x values identical to Android's (TouchControlModels.kt).
        {@"btn_ab1",        @"1",     0.275, 0.90,  0},
        {@"btn_ab2",        @"2",     0.345, 0.90,  1},
        {@"btn_ab3",        @"3",     0.415, 0.90,  2},
        {@"btn_item1",      @"4",     0.515, 0.90, 11},
        {@"btn_item2",      @"5",     0.585, 0.90, 12},
        {@"btn_item3",      @"6",     0.655, 0.90, 13},
        {@"btn_item4",      @"7",     0.725, 0.90, 14},
    };
    for (size_t i = 0; i < sizeof(plain) / sizeof(plain[0]); i++) {
        SKControlNode *node = [self nodeWithId:plain[i].nodeId
                                          type:SKControlTypeButton
                                         label:plain[i].label
                                             x:plain[i].x
                                             y:plain[i].y];
        node.buttonCode = plain[i].button;
        add(node);
    }
    return layout;
}

+ (instancetype)loadLayout {
    NSString *json = [NSUserDefaults.standardUserDefaults stringForKey:kDefaultsKey];
    if (json.length == 0) return [self defaultLayout];

    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                              options:0
                                                error:&error];
    if (![root isKindOfClass:NSDictionary.class]) {
        NSLog(@"[touch] layout unreadable (%@), using defaults", error.localizedDescription);
        return [self defaultLayout];
    }

    NSMutableArray<SKControlNode *> *nodes = [NSMutableArray array];
    for (NSDictionary *dict in root[@"nodes"]) {
        SKControlNode *node = [SKControlNode fromDictionary:dict];
        if (node) [nodes addObject:node];
    }
    if (nodes.count == 0) return [self defaultLayout];

    SKTouchLayout *layout = [SKTouchLayout new];
    layout.nodes = nodes;
    layout.controlsEnabled = root[@"controlsEnabled"] ? [root[@"controlsEnabled"] boolValue] : YES;
    layout.actionBarVisible = [root[@"actionBarVisible"] boolValue];
    CGFloat opacity = [root[@"globalOpacity"] doubleValue];
    layout.globalOpacity =
        (opacity <= 0) ? SKDefaultOpacity : MIN(MAX(opacity, SKMinOpacity), 1.0f);
    // Clamp rather than trust: a layout written before renderScale existed decodes as 0,
    // which would size the framebuffer to 1x1.
    CGFloat renderScale = [root[@"renderScale"] doubleValue];
    layout.renderScale = MIN(MAX(renderScale, SKMinRenderScale), SKMaxRenderScale);
    return layout;
}

- (void)save {
    NSMutableArray *nodeDicts = [NSMutableArray arrayWithCapacity:self.nodes.count];
    for (SKControlNode *node in self.nodes) [nodeDicts addObject:[node toDictionary]];

    NSDictionary *root = @{
        @"globalOpacity": @(self.globalOpacity),
        @"controlsEnabled": @(self.controlsEnabled),
        @"actionBarVisible": @(self.actionBarVisible),
        @"renderScale": @(self.renderScale),
        @"nodes": nodeDicts,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    if (!data) return;
    [NSUserDefaults.standardUserDefaults setObject:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                            forKey:kDefaultsKey];
}

@end
