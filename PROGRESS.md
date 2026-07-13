# SKapsule-iOS Progress

## Phase 0: Basic App Setup, Architecture & Build

**Status:** ✅ Complete

## Phase 1: JVM Bootstrap, NativeBridge & Device Debug

**Status:** ✅ Complete (build infrastructure)

### Completed

- [x] `Natives/dyld_bypass_validation.m` — library validation bypass for unsigned dylibs
- [x] `Natives/NativeBridge.h` / `.m` — JVM ↔ UI bridge (boot status, Steam Guard)
- [x] `Natives/JavaLauncher.h` / `.m` — full JVM boot via `JLI_Launch`
- [x] `Natives/SKInstaller.m` — JAR staging, manifest download, version marker
- [x] `Natives/GameViewController.m` — NativeBridge wiring, Steam Guard dialogs
- [x] `bootstrap/` — Java source copied from SKapsule (4 files)
- [x] `scripts/build-bootstrap.sh` — compile sk-bootstrap.jar
- [x] `.vscode/launch.json` — device debug (iPhone 13 Pro)
- [x] `.vscode/tasks.json` — build tasks (debug, release, TrollStore, deploy)
- [x] `Makefile` deploy target via `devicectl`
- [x] `make native` — 0 errors, 0 warnings
- [x] `make package` — produces valid `.ipa` (49KB)

### Remaining for full Phase 1 testing

- [x] Adopt OpenJDK 25 environment for builds (blocked on actual JRE download from CDN)
- [ ] Complete native submodule builds (gl4es, openal, LWJGL, frenchpress succeeded; caciocavallo17 blocked by JDK 25 FontManager API changes)
- [ ] Bundle all assets into the .app and test on device
- [ ] Verify JVM boots and getdown downloads SK assets

## Phase 1.5: JNI Bridge & GLFW Context

**Status:** ✅ Complete (Basic Stubs)

Key tasks:

- [x] Copy `jni.h` from Amethyst-iOS (instead of creating `jni_core.h`)
- [x] Implement `Java_com_skarm_launcher_bootstrap_SkBootstrap_*` bridge functions in `JavaLauncher.m` to fix UI hang
- [x] Implement `register_glfw_natives` and basic native stubs in `glfw_ios.m` so the SK client doesn't crash during GL init

---

## Phase 2: OpenGL Surface & Rendering Bridge (GL4ES)

**Status:** Not started

Key tasks:

- Replace the placeholder `UIView` in `GameViewController` with a `CAEAGLLayer` or `GLKView`.
- Initialize `EAGLContext` and manage renderbuffers.
- Plumb the window/layer handle into the GLFW/GL4ES bridge so the JVM can present frames to the iOS display.

## Phase 3: Input Bridge (Touch & Virtual Keyboard)

**Status:** Not started

Key tasks:

- Override `touchesBegan:`, `touchesMoved:`, `touchesEnded:`, `touchesCancelled:` in `GameViewController`.
- Map iOS touch coordinates to JVM/AWT mouse events (caciocavallo or GLFW injection).
- Implement a virtual onscreen keyboard overlay for text input (login, chat).

## Phase 4: Audio Integration (OpenAL)

**Status:** Not started

Key tasks:

- Ensure `openal-soft` binds correctly to iOS `AVAudioSession`.
- Verify LWJGL's OpenAL module successfully loads the native `libopenal.dylib` without sandbox/JIT crashes.

## Phase 5: Steam Login Functional

**Status:** Mostly complete (Native UI is done, blocked on JVM testing)

Key tasks:

- Test Steam Guard dialog integration (device code + email code prompts).
- Verify Frenchpress credential passing through env vars.
