package org.lwjgl.openal;

import org.lwjgl.system.NativeResource;

// Shadow of LWJGL's SOFTSystemEventProc, built into sk-bootstrap.jar for iOS only.
//
// The real class extends org.lwjgl.system.Callback, whose constructor builds a Java FFM
// (Panama) upcall stub. On the mirror-mapped code cache that stub's CodeBlob header is
// written through the read-execute address instead of the writable mirror, which faults:
// SIGBUS / BUS_ADRALN in CodeBlob::CodeBlob, called from UpcallStub::create. Spiral
// Knights registers one of these while setting up OpenAL (ALC_SOFT_system_events, for
// device hot-plug), so every launch died there once the game got that far.
//
// This skips Callback entirely, as the shadowed GLFW callbacks do (see
// external/bootstrap/.../org/lwjgl/glfw/SKGLFWCallbackBase.java). address() is 0, so
// alcEventCallbackSOFT is handed a null callback and OpenAL simply never reports device
// events; playback is unaffected.
public abstract class SOFTSystemEventProc implements SOFTSystemEventProcI, NativeResource {
    protected SOFTSystemEventProc() {}

    @Override
    public long address() { return 0L; }

    @Override
    public void free() {}

    public static SOFTSystemEventProc create(long functionPointer) {
        return new SOFTSystemEventProc() {
            @Override
            public void invoke(int eventType, int deviceType, long device, int length, long message, long userParam) {}
        };
    }

    public static SOFTSystemEventProc createSafe(long functionPointer) {
        return functionPointer == 0L ? null : create(functionPointer);
    }

    public static SOFTSystemEventProc create(SOFTSystemEventProcI instance) {
        return instance instanceof SOFTSystemEventProc
            ? (SOFTSystemEventProc) instance
            : new SOFTSystemEventProc() {
                @Override
                public void invoke(int eventType, int deviceType, long device, int length, long message, long userParam) {
                    instance.invoke(eventType, deviceType, device, length, message, userParam);
                }
            };
    }
}
