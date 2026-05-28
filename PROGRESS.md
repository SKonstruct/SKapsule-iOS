# SKapsule-iOS Progress

## Phase 0: Basic App Setup, Architecture & Build

**Status:** ✅ Complete

### Completed
- [x] Repository structure created
- [x] `.gitmodules` — submodule declarations (gl4es, openal-soft, lwjgl3, caciocavallo17, frenchpress, fishhook)
- [x] `.gitignore` — iOS build artifacts
- [x] `Makefile` — top-level build driver (native → payload → package)
- [x] `Natives/CMakeLists.txt` — CMake project for iOS arm64
- [x] `Natives/config.h.in` — branch/commit/build-type config
- [x] `Natives/Info.plist` — bundle metadata
- [x] `Natives/main.m` — app entry point (JIT, home dir, stdio redirect)
- [x] `Natives/AppDelegate.*` — UIApplicationDelegate
- [x] `Natives/SceneDelegate.*` — UISceneDelegate
- [x] `Natives/LauncherViewController.*` — launcher home (Play Web / Play Steam)
- [x] `Natives/GameViewController.*` — game surface (Phase 0 stub)
- [x] `Natives/JavaLauncher.*` — JVM bootstrap (Phase 0 stub)
- [x] `Natives/SKInstaller.*` — runtime installation check (Phase 0 stub)
- [x] `Natives/utils.*` — JIT detection, entitlements, JRE lookup
- [x] `Natives/awt_xawt/` — cacio AWT stubs
- [x] `entitlements.sideload.xml` — AltStore/SideStore
- [x] `entitlements.trollstore.xml` — TrollStore
- [x] `scripts/build-gl4es-ios.sh`
- [x] `scripts/build-openal-ios.sh`
- [x] `scripts/build-lwjgl3-ios.sh`
- [x] `scripts/build-cacio-ios.sh`
- [x] `scripts/build-frenchpress-ios.sh`
- [x] `scripts/stage-app-assets.sh`
- [x] `AGENTS.md`
- [x] `PROGRESS.md`
- [x] Git submodules added
- [x] `make native` compiles cleanly (0 errors, 0 warnings)
- [x] `make package` produces valid `.ipa`
- [x] `make package TROLLSTORE_JIT_ENT=1` produces valid `.tipa`

### Remaining for Phase 0
- [ ] Bundle JRE 25 for iOS arm64 (or create asset staging)
- [ ] Copy bootstrap/ Java source from SKapsule
- [ ] Test install on device

---

## Phase 1: Spiral Knights Downloads and Launches
**Status:** Not started

Key tasks:
- Implement `JavaLauncher.m` — full JVM boot via `JLI_Launch`
- Implement JRE extraction in `SKInstaller.m`
- Implement `NativeBridge` for JVM ↔ UI communication
- Implement `egl_bridge.m` — GL context management
- Implement `input_bridge.m` — touch → GLFW event forwarding
- Implement `dyld_bypass_validation.m` — library validation bypass
- Copy and adapt bootstrap/ Java source from SKapsule

## Phase 2: Steam Login Functional
**Status:** Not started

Key tasks:
- Steam Guard dialog integration (device code + email code prompts)
- Frenchpress credential passing through env vars
