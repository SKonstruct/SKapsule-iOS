#import "SKKeyboardBridge.h"
#import "SKGlfwKeys.h"

extern void sk_input_push_key(int key, int action, int modifiers);
extern void sk_input_push_char(int codepoint);

static const int kGlfwKeyEnter = 257;
static const int kGlfwKeyBackspace = 259;

static void SKTapKey(int key) {
    sk_input_push_key(key, 1, 0);
    sk_input_push_key(key, 0, 0);
}

/// One typed character the way a desktop keyboard delivers it: key press, the character, key release. The game's text
/// fields act on the text (a live search, a filter) at the key release; with the character alone it shows up but does
/// nothing until Enter or Backspace. Text with no key (accents, emoji) goes as the character only.
static void SKTypeChar(int codepoint) {
    int key = SKGlfwKeyForChar(codepoint);
    if (key == kSKGlfwKeyUnknown) {
        sk_input_push_char(codepoint);
        return;
    }
    int mods = SKGlfwCharNeedsShift(codepoint) ? kSKGlfwModShift : 0;
    sk_input_push_key(key, 1, mods);
    sk_input_push_char(codepoint);
    sk_input_push_key(key, 0, mods);
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
                SKTypeChar((int)CFStringGetLongCharacterForSurrogatePair(unit, low));
                i++;
                continue;
            }
        }
        SKTypeChar((int)unit);
    }
}

- (void)deleteBackward {
    SKTapKey(kGlfwKeyBackspace);
}

@end
