#import "SKKeyboardBridge.h"

extern void sk_input_push_key(int key, int action, int modifiers);
extern void sk_input_push_char(int codepoint);

static const int kGlfwKeyEnter = 257;
static const int kGlfwKeyBackspace = 259;

static void SKTapKey(int key) {
    sk_input_push_key(key, 1, 0);
    sk_input_push_key(key, 0, 0);
}

@implementation SKKeyboardBridge

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 1, 1)];
    if (self) self.opaque = NO;
    return self;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)toggle {
    if (self.isFirstResponder) {
        [self resignFirstResponder];
        return NO;
    }
    [self becomeFirstResponder];
    return YES;
}

#pragma mark - UIKeyInput

// Always claim to have text so the keyboard keeps delivering backspace; SK owns the real
// buffer, we only forward keystrokes.
- (BOOL)hasText {
    return YES;
}

- (void)insertText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        SKTapKey(kGlfwKeyEnter);
        return;
    }
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar unit = [text characterAtIndex:i];
        if (CFStringIsSurrogateHighCharacter(unit) && i + 1 < length) {
            unichar low = [text characterAtIndex:i + 1];
            if (CFStringIsSurrogateLowCharacter(low)) {
                sk_input_push_char((int)CFStringGetLongCharacterForSurrogatePair(unit, low));
                i++;
                continue;
            }
        }
        sk_input_push_char((int)unit);
    }
}

- (void)deleteBackward {
    SKTapKey(kGlfwKeyBackspace);
}

@end
