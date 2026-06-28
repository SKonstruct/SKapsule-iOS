#include "jni.h"
#include <stddef.h>

// Stubs that match the real libawt_headless.dylib's exports.
// Font initIDs (the real libawt_headless provides these as empty stubs too)
JNIEXPORT void JNICALL Java_java_awt_Font_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_sun_awt_FontDescriptor_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_sun_awt_PlatformFont_initIDs(JNIEnv *env, jclass cls) {}

#define STUB_INIT_IDS(name) JNIEXPORT void JNICALL Java_##name##_initIDs(JNIEnv *env, jclass cls) {}

STUB_INIT_IDS(java_awt_AWTEvent)
STUB_INIT_IDS(java_awt_Insets)
STUB_INIT_IDS(java_awt_Rectangle)
STUB_INIT_IDS(java_awt_Point)
STUB_INIT_IDS(java_awt_Color)
STUB_INIT_IDS(java_awt_Component)
STUB_INIT_IDS(java_awt_Container)
STUB_INIT_IDS(java_awt_Window)
STUB_INIT_IDS(java_awt_Frame)
STUB_INIT_IDS(java_awt_Dialog)
STUB_INIT_IDS(java_awt_Cursor)
STUB_INIT_IDS(java_awt_KeyboardFocusManager)
STUB_INIT_IDS(java_awt_event_InputEvent)
STUB_INIT_IDS(java_awt_event_KeyEvent)

// AccelGlyphCache stubs (required by libfontmanager.dylib)
typedef void GlyphInfo;
typedef void CacheCellInfo;
void AccelGlyphCache_RemoveAllCellInfos(GlyphInfo *glyph) {}
void AccelGlyphCache_Free(void *cache) {}

// CFontManager native stubs
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeDirFonts(JNIEnv *env, jobject obj, jstring dir) {}
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeFonts(JNIEnv *env, jobject obj) {}
