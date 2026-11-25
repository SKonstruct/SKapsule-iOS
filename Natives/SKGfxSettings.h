#import <Foundation/Foundation.h>

// Graphics settings beside the resolution slider (which lives in the touch layout): the FPS counter,
// sharpening and Sharp HUD, and the decisions made from them. Header-only so `make test` covers the
// decisions. The native pass (skgfx.c) uses the same formulas: keep them in step. SKapsule (Android)
// has the same settings and rules in GfxSettings.kt.

static inline BOOL SKGfxShowFps(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"gfx_show_fps"];
    return value ? [value boolValue] : YES;
}

static inline void SKGfxSetShowFps(BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"gfx_show_fps"];
}

static inline int SKGfxSharpenPercent(void) {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:@"gfx_sharpen_percent"];
    return value < 0 ? 0 : (value > 100 ? 100 : (int)value);
}

static inline void SKGfxSetSharpenPercent(int percent) {
    [NSUserDefaults.standardUserDefaults setInteger:(percent < 0 ? 0 : (percent > 100 ? 100 : percent))
                                             forKey:@"gfx_sharpen_percent"];
}

static inline BOOL SKGfxSharpHud(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"gfx_sharp_hud"];
}

static inline void SKGfxSetSharpHud(BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"gfx_sharp_hud"];
}

/// Sharp HUD only changes anything while the scene is smaller than the window.
static inline BOOL SKGfxSharpHudApplies(float scale) {
    return scale < 0.999f;
}

/// Whether the game draws offscreen (sharpening or Sharp HUD asked for) instead of into a layer that
/// Core Animation upscales.
static inline BOOL SKGfxUsesOffscreen(float scale, int sharpenPercent, BOOL sharpHud) {
    return sharpenPercent > 0 || (sharpHud && SKGfxSharpHudApplies(scale));
}

/// As the native pass rounds it: per mille, half up, at least 1.
static inline int SKGfxScaled(int size, float scale) {
    if (scale < 0.25f) scale = 0.25f;
    if (scale > 1.0f) scale = 1.0f;
    int perMille = (int)(scale * 1000.0f + 0.5f);
    long long value = ((long long)size * perMille + 500) / 1000;
    return value < 1 ? 1 : (int)value;
}

/// The size the game should believe its window is, for a native drawable of w x h with the offscreen
/// path on: the scene's, or with Sharp HUD the full size.
static inline void SKGfxGameSize(int w, int h, float scale, BOOL sharpHud, int *gameW, int *gameH) {
    if (sharpHud && SKGfxSharpHudApplies(scale)) {
        *gameW = w;
        *gameH = h;
    } else {
        *gameW = SKGfxScaled(w, scale);
        *gameH = SKGfxScaled(h, scale);
    }
}
