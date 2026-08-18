# SKapsule-iOS Progress

Phase-level status tracker. For the detailed engineering plan on the active phase, see
[ROADMAP.md](ROADMAP.md).

## Status Summary

| Phase | Description                                             | Status                                     |
| ----- | ------------------------------------------------------- | ------------------------------------------ |
| 0     | Basic app setup, architecture, build                    | ✅ Complete                                |
| 1     | JVM bootstrap, NativeBridge, device debug               | ✅ Complete                                |
| 1.5   | JNI bridge & GLFW shadow-class wiring                   | ✅ Complete                                |
| 2     | OpenGL surface & rendering bridge (gl4es)               | ✅ Complete                                |
| 3     | Input bridge (touch, controls, gamepad, keyboard/mouse) | 🟡 Implemented — device validation pending |
| 4     | Audio (OpenAL)                                          | ✅ Complete                                |
| 5     | Steam login                                             | ✅ Complete                                |
| 6     | iOS 26 JIT bring-up (TXM / StikDebug)                   | ✅ Complete                                |
| 7     | Render fidelity & in-game stability                     | 🟡 Fixes landed — validation pending       |

The app boots the JVM, renders the real Spiral Knights desktop client through gl4es,
plays audio, logs in (Web or Steam, including Steam Guard), and runs gameplay end-to-end on device.
Phase 3 is implemented and ready for on-device validation across touch, controller, and keyboard hardware before declaring feature parity with the Android port.

## Recent Resolution: iOS 26 JIT bring-up (2026-08-15)

The bundled JRE is now the AngelAuraMC JDK-25 **JIT** build, replacing the Zero
interpreter. On A17+/iOS 26 the Trusted Execution Monitor enforces W^X in hardware, so
the VM traps (`brk #0x69`) for an attached debugger to map its code pages; `StikDebug`
running `assets/UniversalJIT26.js` services that. See [README.md](README.md) for the
end-user setup flow and [ROADMAP.md](ROADMAP.md) for the engineering detail.

Boot chain fixed along the way: compressed-class-pointer abort → missing
`libawt_xawt.dylib` → `java.awt.Font.initIDs` → `GLFWNativeCocoa` → FFM upcall stubs.
That last one is worth remembering: LWJGL's `GLFW*Callback` classes build a Java FFM
(Panama) upcall stub in their constructor, and emitting it crashed the mirror-mapped
code cache (`SIGBUS`/`BUS_ADRALN` in `UpcallLinker::make_upcall_stub`). Since SK's GLFW
is fully shadowed, nothing ever calls those stubs natively, so `sk-bootstrap.jar` now
shadows the callback classes to skip `org.lwjgl.system.Callback` entirely.

**Working on-device:** Steam auth, character select, the lobby, audio, and touch input.

## Recent Resolution: gl4es use-after-free & Safe Area Layout

- **gl4es Buffer Lifecycle Fix (2026-07-21):** Resolved memory corruption and crash during login/area load by updating `external/gl4es/src/gl/buffers.c` (`rebind_real_buff_arrays`, `gl4es_glBufferData`, `gl4es_glNamedBufferData`, `gl4es_glDeleteBuffers`). Previously, gl4es updated vertex attributes and buffer pointers only in the **active VAO** (`glstate->vao`) during buffer reallocation/deletion, leaving dangling pointers in other VAOs that referenced the same buffer. Updating all VAOs (`glstate->vaos`) eliminated the use-after-free.
- **Avoid Screen Edges Layout & Resolution Fix:**
  - Changed default `avoidEdges` setting to `NO` on fresh installs in [GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m).
  - Fixed surface/Cacio resolution mismatch when safe area insets are enabled in [glfw_ios.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/glfw_ios.m) (`nativeGetSurfaceSize` querying actual renderbuffer dimensions) and [GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m) (`startJVM` using `surfaceView.frame`), fixing viewport cropping and touch offset issues.

## Phase 0–2, 4, 5 — summary

- **Phase 0/1 (setup, JVM bootstrap):** `Natives/JavaLauncher.m` boots the bundled JRE 25
  via `JLI_Launch`; `Natives/dyld_bypass_validation.m` allows the unsigned dylibs to load;
  `Natives/SKInstaller.m` stages JARs/assets into the app's documents container and is
  version-aware (re-stages on every new build rather than trusting stale cache).
- **Phase 1.5 (JNI/GLFW wiring):** `external/bootstrap` (shared with Android) supplies
  `SkBootstrap`/`HeadlessGetdown`/`NativeBridgePrompt`/`GLFW.java`; `Natives/glfw_ios.m`
  registers the native side of the `GLFW` shadow class.
- **Phase 2 (rendering):** `Natives/GameViewController.m` owns a `CAEAGLLayer`-backed
  `EAGLContext` surface with color + depth/stencil renderbuffers, rebound per-thread in
  `nativeMakeContextCurrent`. Fixed along the way: a render-thread SIGSEGV in gl4es's FBO 0
  handling, a framebuffer-incomplete depth attachment, and a `glGetUniformLocation`/
  `glGetAttribLocation` NULL-name crash.
- **Phase 4 (audio):** `openal-soft` binds to `AVAudioSession`; LWJGL's OpenAL module loads
  `libopenal.dylib` without sandbox/JIT issues. Music plays through the prologue and in-game.
- **Phase 5 (Steam login):** Web and Steam login both work, including the Steam Guard
  device-code/email-code prompt (`GameViewController.m`'s `showSteamGuardPromptWithTitle:`).
  A main-thread deadlock in the original prompt implementation was fixed.

The font-resolution and Java2D/AWT-stub sagas that blocked the login screen for a while are
resolved; see ROADMAP.md's History section for a short technical summary if needed —
the blow-by-blow debugging log has been trimmed from both files to keep them current.

## Phase 3: Input Bridge

**Implemented; pending on-device acceptance testing.** `Natives/glfw_ios.m` now has the
thread-safe GLFW event ring buffer and shared standard-layout gamepad mailbox. `GameViewController.m`
routes direct touch, physical keyboard, pointer hover, virtual controls, and `GCController` callbacks
through those native structures. The generated Xcode project links `GameController.framework` too.

The native CMake build and Xcode compilation both pass. The Xcode package post-build step cannot
complete on this machine because its configured `Apple Development` identity is ambiguous; deploy and
test on device through Xcode before marking the phase complete.

Key tasks (see ROADMAP.md → **Ticket 36** for the full technical breakdown, informed by
reading the Android reference implementation in `SKapsule` and the iOS-native input patterns
in `Amethyst-iOS`):

- [x] **36a. Touch input** — primary-touch cursor/click bridge, preserving cursor-before-button ordering.
- [x] **36b. Touch controls / buttons** — UIKit action-button overlay writing to the virtual gamepad mailbox.
- [x] **36c. Touch joystick** — virtual move and face joysticks with a 0.15 deadzone.
- [x] **36d. Gamepad support** — `GCController` callbacks mapped to the GLFW-standard 15-button / 6-axis mailbox.
- [x] **36e. Keyboard/mouse support** — `UIKey` press/character routing plus pointer-hover cursor updates.

Remaining acceptance checks: tap the login UI, bind and use each touch/gamepad control in-game, type in login/chat with an external keyboard, and verify external mouse or trackpad behavior on iPadOS.
