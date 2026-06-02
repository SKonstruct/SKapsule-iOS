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
- [x] Source JRE 25 for iOS arm64 (Temporarily downgraded to JRE 21)
- [x] Build native submodules (gl4es, openal, LWJGL, cacio, frenchpress)
- [x] Bundle all assets into the .app and test on device
- [ ] Verify JVM boots and getdown downloads SK assets

## Phase 1.5: JNI Bridge & GLFW Context
**Status:** ✅ Complete (Basic Stubs)

Key tasks:
- [x] Copy `jni.h` from Amethyst-iOS (instead of creating `jni_core.h`)
- [x] Implement `Java_com_skarm_launcher_bootstrap_SkBootstrap_*` bridge functions in `JavaLauncher.m` to fix UI hang
- [x] Implement `register_glfw_natives` and basic native stubs in `glfw_ios.m` so the SK client doesn't crash during GL init

---

## Phase 2: Steam Login Functional
**Status:** Not started

Key tasks:
- Steam Guard dialog integration (device code + email code prompts)
- Frenchpress credential passing through env vars
