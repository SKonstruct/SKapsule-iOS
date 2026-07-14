# SKapsule-iOS Progress

Phase-level status tracker. For the detailed engineering plan on the active phase, see
[OPUS-ROADMAP.md](OPUS-ROADMAP.md).

## Status Summary

| Phase | Description                                          | Status               |
| ----- | ----------------------------------------------------- | --------------------- |
| 0     | Basic app setup, architecture, build                  | ✅ Complete            |
| 1     | JVM bootstrap, NativeBridge, device debug              | ✅ Complete            |
| 1.5   | JNI bridge & GLFW shadow-class wiring                  | ✅ Complete            |
| 2     | OpenGL surface & rendering bridge (gl4es)              | ✅ Complete            |
| 3     | Input bridge (touch, controls, gamepad, keyboard/mouse) | 🔄 In progress — current focus |
| 4     | Audio (OpenAL)                                         | ✅ Complete            |
| 5     | Steam login                                            | ✅ Complete            |

The app boots the JVM, renders the real Spiral Knights desktop client through gl4es,
plays audio, and logs in (Web or Steam, including Steam Guard) end-to-end on device.
Phase 3 is the only remaining major phase before feature parity with the Android port.

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
resolved; see OPUS-ROADMAP.md's History section for a short technical summary if needed —
the blow-by-blow debugging log has been trimmed from both files to keep them current.

## Phase 3: Input Bridge (current)

**Not yet implemented.** `Natives/glfw_ios.m`'s `nativeDrainInput`, `nativeGamepadPresent`,
and `nativeGetGamepadState` are stubs that return 0/false; `Natives/GameViewController.m`
has no touch or key-press handler overrides yet; there is no gamepad (`GCController`) code
on iOS at all (though `GameController.framework` is already linked in `CMakeLists.txt`).

Key tasks (see OPUS-ROADMAP.md → **Ticket 36** for the full technical breakdown, informed by
reading the Android reference implementation in `SKapsule` and the iOS-native input patterns
in `Amethyst-iOS`):

- [ ] **36a. Touch input** — thread-safe input ring buffer in `glfw_ios.m` (mirrors
      `sklauncher.c`'s `input_q`), fed from `touchesBegan:`/`touchesMoved:`/`touchesEnded:`/
      `touchesCancelled:` in `GameViewController.m`.
- [ ] **36b. Touch controls / buttons** — on-screen action button overlay.
- [ ] **36c. Touch joystick** — virtual dual-joystick (move + face), matching Android's
      default layout.
- [ ] **36d. Gamepad support** — `GCController` integration writing into the same GLFW
      standard-layout gamepad mailbox (15 buttons / 6 axes) that touch controls also drive.
- [ ] **36e. Keyboard/mouse support** — physical keyboard via `UIKey`/`pressesBegan:`, and
      pointer/trackpad support where applicable.
