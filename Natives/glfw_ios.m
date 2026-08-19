#define GLES_SILENCE_DEPRECATION 1
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>   // GL_DEPTH24_STENCIL8_OES
#import <UIKit/UIKit.h>
#import "NativeBridge.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include "jni.h"

extern EAGLContext *gEAGLContext;
extern CAEAGLLayer *gEAGLLayer;
extern GLuint gRenderbuffer;
extern GLuint gFramebuffer;
extern GLuint gDepthRenderbuffer;

// Input is produced on UIKit/GameController threads and drained on SK's main
// loop thread by GLFW.java. Keep the wire format in sync with GLFW.java.
#define EV_CURSOR_POS 1
#define EV_MOUSE_BUTTON 2
#define EV_SCROLL 3
#define EV_KEY 4
#define EV_CHAR 5
#define EV_FRAMEBUFFER_SIZE 6

#define INPUT_Q_CAP 2048
static struct {
    pthread_mutex_t lock;
    int32_t records[INPUT_Q_CAP][4];
    int head;
    int tail;
} inputQueue = { .lock = PTHREAD_MUTEX_INITIALIZER };

static void input_push(int32_t type, int32_t a, int32_t b, int32_t c) {
    pthread_mutex_lock(&inputQueue.lock);
    int next = (inputQueue.tail + 1) % INPUT_Q_CAP;
    if (next != inputQueue.head) {
        int32_t *record = inputQueue.records[inputQueue.tail];
        record[0] = type;
        record[1] = a;
        record[2] = b;
        record[3] = c;
        inputQueue.tail = next;
    }
    pthread_mutex_unlock(&inputQueue.lock);
}

#define GP_BUTTONS 15
#define GP_AXES 6
#define GP_AXIS_LTRIGGER 4
#define GP_AXIS_RTRIGGER 5
static struct {
    pthread_mutex_t lock;
    atomic_bool physicalActive;
    atomic_bool virtualActive;
    int8_t buttons[GP_BUTTONS];
    float axes[GP_AXES];
} gamepad = { .lock = PTHREAD_MUTEX_INITIALIZER };

static BOOL gamepad_active(void) {
    return atomic_load(&gamepad.physicalActive) || atomic_load(&gamepad.virtualActive);
}

static void gamepad_reset(void) {
    pthread_mutex_lock(&gamepad.lock);
    memset(gamepad.buttons, 0, sizeof(gamepad.buttons));
    memset(gamepad.axes, 0, sizeof(gamepad.axes));
    gamepad.axes[GP_AXIS_LTRIGGER] = -1.0f;
    gamepad.axes[GP_AXIS_RTRIGGER] = -1.0f;
    pthread_mutex_unlock(&gamepad.lock);
}

void sk_input_push_cursor(int x, int y) {
    input_push(EV_CURSOR_POS, x, y, 0);
}

void sk_input_push_mouse_button(int button, BOOL pressed) {
    input_push(EV_MOUSE_BUTTON, button, pressed ? 1 : 0, 0);
}

void sk_input_push_key(int key, int action, int modifiers) {
    input_push(EV_KEY, key, action, modifiers);
}

void sk_input_push_char(int codepoint) {
    input_push(EV_CHAR, codepoint, 0, 0);
}

void sk_input_push_framebuffer_size(int width, int height) {
    input_push(EV_FRAMEBUFFER_SIZE, width, height, 0);
}

void sk_gamepad_set_virtual_active(BOOL active) {
    BOOL wasActive = gamepad_active();
    atomic_store(&gamepad.virtualActive, active);
    if ((active && !wasActive) || !gamepad_active()) {
        gamepad_reset();
    }
}

void sk_gamepad_set_physical_active(BOOL active) {
    BOOL wasActive = gamepad_active();
    atomic_store(&gamepad.physicalActive, active);
    if ((active && !wasActive) || !gamepad_active()) {
        gamepad_reset();
    }
}

void sk_gamepad_set_button(int index, BOOL pressed) {
    if (index < 0 || index >= GP_BUTTONS) return;
    pthread_mutex_lock(&gamepad.lock);
    gamepad.buttons[index] = pressed ? 1 : 0;
    pthread_mutex_unlock(&gamepad.lock);
}

void sk_gamepad_set_axis(int index, float value) {
    if (index < 0 || index >= GP_AXES) return;
    pthread_mutex_lock(&gamepad.lock);
    gamepad.axes[index] = value;
    pthread_mutex_unlock(&gamepad.lock);
}

static jint nativeDrainInput(JNIEnv *env, jclass clazz, jintArray out) {
    if (!out) return 0;

    jsize capacity = (*env)->GetArrayLength(env, out) / 4;
    if (capacity <= 0) return 0;

    jint tempBuf[1024];
    jsize limit = (capacity < 256) ? capacity : 256;

    int count = 0;
    pthread_mutex_lock(&inputQueue.lock);
    while (count < limit && inputQueue.head != inputQueue.tail) {
        int32_t *record = inputQueue.records[inputQueue.head];
        tempBuf[count * 4] = record[0];
        tempBuf[count * 4 + 1] = record[1];
        tempBuf[count * 4 + 2] = record[2];
        tempBuf[count * 4 + 3] = record[3];
        inputQueue.head = (inputQueue.head + 1) % INPUT_Q_CAP;
        count++;
    }
    pthread_mutex_unlock(&inputQueue.lock);

    if (count > 0) {
        (*env)->SetIntArrayRegion(env, out, 0, count * 4, tempBuf);
    }
    return count;
}

static jintArray nativeGetSurfaceSize(JNIEnv *env, jclass clazz) {
    jintArray result = (*env)->NewIntArray(env, 2);
    if (result != NULL) {
        jint dims[2];
        GLint rbWidth = 0, rbHeight = 0;
        if (gRenderbuffer) {
            glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &rbWidth);
            glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &rbHeight);
        }
        if (rbWidth > 0 && rbHeight > 0) {
            dims[0] = (jint)rbWidth;
            dims[1] = (jint)rbHeight;
        } else {
            CGSize size = UIScreen.mainScreen.bounds.size;
            CGFloat scale = UIScreen.mainScreen.scale;
            dims[0] = (jint)(size.width * scale);
            dims[1] = (jint)(size.height * scale);
        }
        (*env)->SetIntArrayRegion(env, result, 0, 2, dims);
    }
    return result;
}

#include <dlfcn.h>

static void gl4es_bring_up_once(void) {
    static BOOL initialized = NO;
    if (initialized)
        return;

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

// Rebuilding the drawable is GL work, and this context belongs to SK's render thread --
// doing it from the main thread is undefined behaviour that corrupts the driver's heap.
// The resolution slider therefore only raises this flag; the resize happens below, at the
// end of a frame, on the thread that owns the context.
static atomic_int gResizePending;

void sk_gl_request_resize(void) {
    atomic_store_explicit(&gResizePending, 1, memory_order_release);
}

static void apply_pending_resize(void) {
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    [gEAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:gEAGLLayer];

    GLint width = 0, height = 0;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);

    if (gDepthRenderbuffer) {
        glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, gDepthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    }

    // Tell SK the framebuffer changed so it re-lays out its HUD and render targets. The
    // callback runs on this same thread when GLFW.java drains the queue, so it is safe to
    // let it rebuild GL objects. Only ever pushed for a deliberate resolution change.
    if (width > 0 && height > 0) sk_input_push_framebuffer_size((int)width, (int)height);
}

static void nativeSwapBuffers(JNIEnv *env, jclass clazz, jlong window) {
    [EAGLContext setCurrentContext:gEAGLContext];
    glBindRenderbuffer(GL_RENDERBUFFER, gRenderbuffer);
    [gEAGLContext presentRenderbuffer:GL_RENDERBUFFER];

    // After the present, so the frame just shown was rendered at the old size.
    if (atomic_exchange_explicit(&gResizePending, 0, memory_order_acquire))
        apply_pending_resize();

    if (!gRenderReadyFired) {
        gRenderReadyFired = YES;
        [SKNativeBridge onRenderReady];
    }
}

static jboolean nativeGamepadPresent(JNIEnv *env, jclass clazz) {
    return gamepad_active() ? JNI_TRUE : JNI_FALSE;
}

static jboolean nativeGetGamepadState(JNIEnv *env, jclass clazz, jbyteArray outButtons, jfloatArray outAxes) {
    if (!gamepad_active() || !outButtons || !outAxes ||
        (*env)->GetArrayLength(env, outButtons) < GP_BUTTONS ||
        (*env)->GetArrayLength(env, outAxes) < GP_AXES) {
        return JNI_FALSE;
    }

    int8_t buttons[GP_BUTTONS];
    float axes[GP_AXES];
    pthread_mutex_lock(&gamepad.lock);
    memcpy(buttons, gamepad.buttons, sizeof(buttons));
    memcpy(axes, gamepad.axes, sizeof(axes));
    pthread_mutex_unlock(&gamepad.lock);

    (*env)->SetByteArrayRegion(env, outButtons, 0, GP_BUTTONS, (const jbyte *)buttons);
    (*env)->SetFloatArrayRegion(env, outAxes, 0, GP_AXES, axes);
    return JNI_TRUE;
}

void register_glfw_natives(JNIEnv *env, jclass glfwClass) {
    JNINativeMethod methods[] = {{"nativeDrainInput", "([I)I", (void *)&nativeDrainInput},
                                 {"nativeGetSurfaceSize", "()[I", (void *)&nativeGetSurfaceSize},
                                 {"nativeMakeContextCurrent", "(J)V", (void *)&nativeMakeContextCurrent},
                                 {"nativeSwapBuffers", "(J)V", (void *)&nativeSwapBuffers},
                                 {"nativeGamepadPresent", "()Z", (void *)&nativeGamepadPresent},
                                 {"nativeGetGamepadState", "([B[F)Z", (void *)&nativeGetGamepadState}};

    (*env)->RegisterNatives(env, glfwClass, methods, sizeof(methods) / sizeof(methods[0]));
}
