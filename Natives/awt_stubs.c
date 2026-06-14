#include "jni.h"
#include <stddef.h>

// AWT initIDs stubs — these are normally provided by platform-specific
// AWT backends. On iOS we use cacio which handles everything in Java,
// but the JRE's libawt.dylib still calls these during class loading.

#define STUB_INIT_IDS(name) \
    JNIEXPORT void JNICALL Java_##name##_initIDs(JNIEnv *env, jclass cls) {}

STUB_INIT_IDS(java_awt_AWTEvent)
STUB_INIT_IDS(java_awt_Toolkit)
STUB_INIT_IDS(java_awt_Dimension)
STUB_INIT_IDS(java_awt_image_ColorModel)
STUB_INIT_IDS(java_awt_image_BufferedImage)
STUB_INIT_IDS(java_awt_image_Raster)
STUB_INIT_IDS(java_awt_image_SampleModel)
STUB_INIT_IDS(java_awt_image_SinglePixelPackedSampleModel)
STUB_INIT_IDS(java_awt_Font)
STUB_INIT_IDS(java_awt_FontMetrics)
STUB_INIT_IDS(sun_awt_image_IntegerComponentRaster)
STUB_INIT_IDS(sun_java2d_SurfaceData)
STUB_INIT_IDS(sun_java2d_pipe_SpanClipRenderer)
STUB_INIT_IDS(sun_java2d_pipe_Region)
STUB_INIT_IDS(sun_awt_image_BufImgSurfaceData)
STUB_INIT_IDS(sun_java2d_loops_GraphicsPrimitiveMgr)
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
STUB_INIT_IDS(java_awt_event_MouseEvent)

// BufImgSurfaceData also needs initRaster
JNIEXPORT void JNICALL Java_sun_awt_image_BufImgSurfaceData_initRaster(
    JNIEnv *env, jobject obj, jobject img, jint type, jint x, jint y,
    jint w, jint h, jobject sData, jobject icm) {}

// GraphicsPrimitiveMgr also needs registerNativeLoops
JNIEXPORT void JNICALL Java_sun_java2d_loops_GraphicsPrimitiveMgr_registerNativeLoops(
    JNIEnv *env, jclass cls) {}

// --- AccelGlyphCache stubs (required by libfontmanager.dylib) ---
// These are C-level symbols, not JNI. libfontmanager imports them
// from libawt_headless (or libawt on other platforms).

typedef void GlyphInfo;    // opaque pointer
typedef void CacheCellInfo; // opaque pointer

void AccelGlyphCache_RemoveAllCellInfos(GlyphInfo *glyph) {}
void AccelGlyphCache_Free(void *cache) {}

// Additional Font initIDs found in real libawt_headless
STUB_INIT_IDS(sun_awt_FontDescriptor)
STUB_INIT_IDS(sun_awt_PlatformFont)

// CFontManager native stubs
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeDirFonts(JNIEnv *env, jobject obj, jstring dir) {}
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeFonts(JNIEnv *env, jobject obj) {}

