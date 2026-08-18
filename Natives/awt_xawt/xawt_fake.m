// Fake libawt_xawt for cacio (caciocavallo) on iOS. The AngelAuraMC iOS JRE ships
// no libawt_xawt.dylib (iOS has no X11), but cacio's CTCToolkit still loads it via
// java.awt.Toolkit.loadLibraries(). These empty *_initIDs stubs satisfy that load
// and the JNI symbol lookups cacio performs. Ported from Amethyst-iOS.
#include "../jni.h"

// java.awt.*
JNIEXPORT void JNICALL Java_java_awt_AWTEvent_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Button_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Color_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Component_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Container_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Checkbox_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_CheckboxMenuItem_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Choice_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Cursor_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Cursor_finalizeImpl(JNIEnv *env, jclass clazz, jlong pData) {}
JNIEXPORT void JNICALL Java_java_awt_Dialog_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Dimension_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Event_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_FileDialog_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_FontMetrics_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Frame_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Insets_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_KeyboardFocusManager_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Label_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Menu_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_MenuBar_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_MenuComponent_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_MenuItem_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Rectangle_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Scrollbar_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_ScrollPane_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_ScrollPaneAdjustable_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_TextArea_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_TextField_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_Toolkit_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_TrayIcon_initIDs(JNIEnv *env, jclass clazz) {}
JNIEXPORT void JNICALL Java_java_awt_Window_initIDs(JNIEnv *env, jclass cls) {}

// Font natives — not exported by this JRE's libawt.dylib, and libawt_headless
// (which has them) isn't loaded on the non-headless cacio path. cacio's preload
// agent needs them during VM init, before register_sk_natives runs, so provide
// them here in the early-loaded xawt lib.
JNIEXPORT void JNICALL Java_java_awt_Font_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_sun_awt_FontDescriptor_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_sun_awt_PlatformFont_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeDirFonts(JNIEnv *env, jobject obj, jstring dir) {}
JNIEXPORT void JNICALL Java_sun_font_CFontManager_loadNativeFonts(JNIEnv *env, jobject obj) {}

// java.awt.event.*
JNIEXPORT void JNICALL Java_java_awt_AWTEvent_nativeSetSource(JNIEnv *env, jobject self, jobject newSource) {}
JNIEXPORT void JNICALL Java_java_awt_event_InputEvent_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_event_KeyEvent_initIDs(JNIEnv *env, jclass cls) {}
JNIEXPORT void JNICALL Java_java_awt_event_MouseEvent_initIDs(JNIEnv *env, jclass clazz) {}

// sun.awt.*
JNIEXPORT void JNICALL Java_sun_awt_SunToolkit_closeSplashScreen(JNIEnv *env, jclass cls) {}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_check_1gtk(JNIEnv *env, jclass klass, jint version) {
    return JNI_FALSE;
}
JNIEXPORT jint JNICALL Java_sun_awt_UNIXToolkit_get_1gtk_1version(JNIEnv *env, jclass klass) {
    return (jint)1;
}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_gtkCheckVersionImpl(JNIEnv *env, jobject this, jint major,
                                                                       jint minor, jint micro) {
    return JNI_FALSE;
}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_load_1gtk(JNIEnv *env, jclass klass, jint version,
                                                             jboolean verbose) {
    return JNI_FALSE;
}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_load_1gtk_1icon(JNIEnv *env, jobject this, jstring filename) {
    return JNI_FALSE;
}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_load_1stock_1icon(JNIEnv *env, jobject this, jint widget_type,
                                                                     jstring stock_id, jint icon_size,
                                                                     jint text_direction, jstring detail) {
    return JNI_FALSE;
}
JNIEXPORT void JNICALL Java_sun_awt_UNIXToolkit_nativeSync(JNIEnv *env, jobject this) {}
JNIEXPORT jboolean JNICALL Java_sun_awt_UNIXToolkit_unload_1gtk(JNIEnv *env, jclass klass) {
    return JNI_FALSE;
}
