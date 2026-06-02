#import <UIKit/UIKit.h>
#include "jni.h"

// Basic stub implementations to prevent UnsatisfiedLinkError during JVM boot.

static jint nativeDrainInput(JNIEnv *env, jclass clazz, jintArray out) {
    return 0; // Return 0 events for now
}

static jintArray nativeGetSurfaceSize(JNIEnv *env, jclass clazz) {
    jintArray result = (*env)->NewIntArray(env, 2);
    if (result != NULL) {
        jint dims[2];
        CGSize size = UIScreen.mainScreen.bounds.size;
        CGFloat scale = UIScreen.mainScreen.scale;
        dims[0] = (jint)(size.width * scale);
        dims[1] = (jint)(size.height * scale);
        (*env)->SetIntArrayRegion(env, result, 0, 2, dims);
    }
    return result;
}

static void nativeMakeContextCurrent(JNIEnv *env, jclass clazz, jlong window) {
    // Implementation needed for actual GL context setup
}

static void nativeSwapBuffers(JNIEnv *env, jclass clazz, jlong window) {
    // Implementation needed to present renderbuffer
}

static jboolean nativeGamepadPresent(JNIEnv *env, jclass clazz) {
    return JNI_FALSE;
}

static jboolean nativeGetGamepadState(JNIEnv *env, jclass clazz, jbyteArray outButtons, jfloatArray outAxes) {
    return JNI_FALSE;
}

void register_glfw_natives(JNIEnv *env, jclass glfwClass) {
    JNINativeMethod methods[] = {
        {"nativeDrainInput", "([I)I", (void *)&nativeDrainInput},
        {"nativeGetSurfaceSize", "()[I", (void *)&nativeGetSurfaceSize},
        {"nativeMakeContextCurrent", "(J)V", (void *)&nativeMakeContextCurrent},
        {"nativeSwapBuffers", "(J)V", (void *)&nativeSwapBuffers},
        {"nativeGamepadPresent", "()Z", (void *)&nativeGamepadPresent},
        {"nativeGetGamepadState", "([B[F)Z", (void *)&nativeGetGamepadState}
    };
    
    (*env)->RegisterNatives(env, glfwClass, methods, sizeof(methods)/sizeof(methods[0]));
}
