#define GLES_SILENCE_DEPRECATION 1
#import <UIKit/UIKit.h>
#include "jni.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import "NativeBridge.h"

extern EAGLContext *gEAGLContext;
extern CAEAGLLayer *gEAGLLayer;
extern GLuint gRenderbuffer;
extern GLuint gFramebuffer;

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

#include <dlfcn.h>

static void gl4es_bring_up_once(void) {
    static BOOL initialized = NO;
    if (initialized) return;

    NSString *gl4esPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/libgl4es.dylib"];
    void *gl4es = dlopen(gl4esPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!gl4es) {
        NSLog(@"[glfw] dlopen libgl4es.dylib failed: %s", dlerror());
        return;
    }

    void (*init_gl4es)(void) = dlsym(gl4es, "initialize_gl4es");
    if (init_gl4es) {
        init_gl4es();
        NSLog(@"[glfw] gl4es initialized!");
    } else {
        NSLog(@"[glfw] dlsym initialize_gl4es failed: %s", dlerror());
    }
    initialized = YES;
}

static void nativeMakeContextCurrent(JNIEnv *env, jclass clazz, jlong window) {
    [EAGLContext setCurrentContext:gEAGLContext];

    // Dynamically call native GLES glBindFramebuffer to bind the custom FBO on the render thread context.
    // We must do this dynamically using dlsym to bypass gl4es interception before it is initialized.
    if (gFramebuffer != 0) {
        static void (*native_glBindFramebuffer)(GLenum, GLuint) = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            void *gles = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW);
            if (gles) {
                native_glBindFramebuffer = dlsym(gles, "glBindFramebuffer");
            }
        });
        if (native_glBindFramebuffer) {
            native_glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
        }
    }

    gl4es_bring_up_once();
}

static BOOL gRenderReadyFired = NO;

static void nativeSwapBuffers(JNIEnv *env, jclass clazz, jlong window) {
    [EAGLContext setCurrentContext:gEAGLContext];
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    [gEAGLContext presentRenderbuffer:GL_RENDERBUFFER];

    if (!gRenderReadyFired) {
        gRenderReadyFired = YES;
        [SKNativeBridge onRenderReady];
    }
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
