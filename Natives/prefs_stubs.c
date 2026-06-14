#include "jni.h"
#include <stdio.h>
#include <sys/file.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

JNIEXPORT jintArray JNICALL Java_java_util_prefs_FileSystemPreferences_lockFile0(
    JNIEnv *env, jclass cls, jstring pathObj, jint perm, jboolean shared) {
    const char *path = (*env)->GetStringUTFChars(env, pathObj, NULL);
    int fd = open(path, O_RDWR | O_CREAT, perm);
    (*env)->ReleaseStringUTFChars(env, pathObj, path);
    jint result[2];
    if (fd < 0) {
        result[0] = 0;  // no fd
        result[1] = errno;
    } else {
        int rc = flock(fd, shared ? LOCK_SH : LOCK_EX);
        result[0] = fd;
        result[1] = (rc == 0) ? 0 : errno;
    }
    jintArray arr = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, arr, 0, 2, result);
    return arr;
}

// unlockFile0
JNIEXPORT jint JNICALL Java_java_util_prefs_FileSystemPreferences_unlockFile0(
    JNIEnv *env, jclass cls, jint lockHandle) {
    if (lockHandle > 0) {
        flock(lockHandle, LOCK_UN);
        close(lockHandle);
    }
    return 0;
}

// chmod — set file permissions (no-op on iOS)
JNIEXPORT jint JNICALL Java_java_util_prefs_FileSystemPreferences_chmod(
    JNIEnv *env, jclass cls, jstring path, jint mode) {
    return 0;
}
