#pragma once

#import <Foundation/Foundation.h>

// The GLFW key behind a typed character, on a US keyboard. A desktop keyboard sends key press, the character, then
// key release, and the game's text fields only act on the typed text once the matching key release arrives: with
// the character alone it shows up but a live search or filter does not update until Enter or Backspace (real key
// transitions) is used. Header-only and Foundation-only so `make test` runs it; the same rules and cases as
// Android's GlfwKeys.kt (keep them in step).

static const int kSKGlfwKeyUnknown = -1;
static const int kSKGlfwModShift = 1;

/// The key that types `cp` (with Shift where it needs it), or kSKGlfwKeyUnknown for text that has no key.
static inline int SKGlfwKeyForChar(int cp) {
    if (cp >= 'a' && cp <= 'z') return 'A' + (cp - 'a');
    if ((cp >= 'A' && cp <= 'Z') || (cp >= '0' && cp <= '9')) return cp;
    if (cp < 32 || cp > 126) return kSKGlfwKeyUnknown;
    const char *shiftedDigits = ")!@#$%^&*(";
    for (int i = 0; i < 10; i++) {
        if (cp == shiftedDigits[i]) return '0' + i;
    }
    switch (cp) {
        case ' ': return 32;
        case '\'': case '"': return 39;
        case ',': case '<': return 44;
        case '-': case '_': return 45;
        case '.': case '>': return 46;
        case '/': case '?': return 47;
        case ';': case ':': return 59;
        case '=': case '+': return 61;
        case '[': case '{': return 91;
        case '\\': case '|': return 92;
        case ']': case '}': return 93;
        case '`': case '~': return 96;
        default: return kSKGlfwKeyUnknown;
    }
}

/// Whether typing `cp` holds Shift on a US keyboard.
static inline BOOL SKGlfwCharNeedsShift(int cp) {
    if (cp >= 'A' && cp <= 'Z') return YES;
    if (cp < 32 || cp > 126) return NO;
    const char *shifted = "!@#$%^&*()\"<_>?:+{|}~";
    for (const char *p = shifted; *p; p++) {
        if (cp == *p) return YES;
    }
    return NO;
}
