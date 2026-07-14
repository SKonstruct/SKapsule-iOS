# SKapsule-iOS Engineering Roadmap

Authoritative technical plan for SKapsule-iOS. [PROGRESS.md](PROGRESS.md) has the
phase-level status table; this document has the engineering detail for the active phase.

> Historical debugging logs (font resolution, framebuffer binding, AWT stub sagas, etc.)
> have been trimmed. See **History** below for a short summary of what was fixed. Full
> detail lives in git history / PR descriptions if ever needed again.

---

## Current State

The app is fully playable end-to-end on device: it boots the bundled JRE 25, runs the real
Spiral Knights desktop client through gl4es, plays audio, and logs in (Web or Steam,
including Steam Guard) successfully. Nothing is broken at the rendering/font/audio/login
layer.

**The only remaining phase is the input bridge (Ticket 36 below).** Touch, on-screen
controls, gamepad, and physical keyboard/mouse are all unimplemented — `glfw_ios.m`'s input
natives are stubs, and `GameViewController.m` has no touch/press handlers at all.

---

## History (completed work, condensed)

- **JVM boot & staging.** `JavaLauncher.m` boots the bundled JRE 25 via `JLI_Launch`.
  `dyld_bypass_validation.m` allows the unsigned dylibs (gl4es, openal-soft, cacio, etc.) to
  load under JIT/codesign restrictions. `SKInstaller.m` stages JARs/assets into the app's
  documents container and is version-aware, so a rebuilt JAR is always re-staged rather than
  served from stale cache.
- **Rendering (gl4es/EGL-equivalent).** `GameViewController.m` owns a `CAEAGLLayer`-backed
  `EAGLContext` surface with color + depth/stencil renderbuffers. Fixed: a render-thread
  SIGSEGV in gl4es's FBO 0 handling (`nativeMakeContextCurrent` now binds the real `gFramebuffer`
  on the render thread before gl4es touches it), a framebuffer-incomplete depth attachment
  (rebind + reattach on resize), and a `glGetUniformLocation`/`glGetAttribLocation` NULL-name
  crash (null checks added ahead of gl4es's debug-logging macros, which were dereferencing the
  NULL name themselves).
- **Fonts (cacio).** `SunFontManager` only auto-registers the JRE font directory on Linux, so
  iOS's `CTCFontManager`/`CTCFontConfiguration` needed a forced `registerFontDir()` call plus a
  hand-built `fonts.dir` XLFD-to-file mapping and a null-safe `findFont2D` fallback. This
  resolved a persistent `Font.getFont2D()` NPE that left the login screen blank.
- **AWT / Java2D.** `awt_stubs.c` replaces the JRE's `libawt_headless.dylib`; getting its
  exported symbol set exactly right took two passes — over-stubbing shadowed real
  `libawt.dylib` rendering-loop registration (`MaskBlit` `InternalError`), under-stubbing then
  produced `UnsatisfiedLinkError` for platform-backend `initIDs` symbols not present in either
  real library. Both are resolved.
- **Steam login.** `showSteamGuardPromptWithTitle:` originally nested a nested
  `dispatch_async(main_queue)` behind a `dispatch_semaphore_wait` also on the main queue —
  a self-deadlock. Fixed to present directly on the main thread and resume asynchronously via
  `[SKNativeBridge submitCode:]`. Web and Steam login (device-code and email-code Steam Guard)
  both verified working end-to-end on device.
- **Audio.** `openal-soft` binds to `AVAudioSession` and LWJGL's OpenAL module loads
  `libopenal.dylib` without sandbox/JIT issues; no further work needed.

---

## Active Work: TICKET 36 — Input Bridge

**Priority:** 🔴 Critical — needed for the game to be playable, not just watchable.
**Status:** Not started. This is the only remaining phase.

### The unifying architectural principle (from the Android port)

SKapsule's Android implementation (`SKapsule/launcher/`) treats **touch, virtual on-screen
controls, and a physical gamepad as three producers feeding two shared native data
structures**, and Spiral Knights itself never knows which one it's hearing from:

1. A **mouse/keyboard event queue** (cursor position, mouse button, scroll, key transitions,
   typed characters) — used for UI/menu navigation and text entry.
2. A **gamepad mailbox** (15 buttons + 6 axes, GLFW's standard gamepad layout) — used for
   gameplay (movement, combat). Touch joystick/button writes and physical-gamepad writes land
   in the *same* struct; SK just sees "a gamepad is connected" whenever either source is active
   (`gamepad_active() = present || virtual_present`).

This is the correct model to replicate on iOS — not three independent input paths bolted onto
GLFW.java three separate ways. GLFW.java (shared bootstrap, already complete, **no changes
needed there**) already expects exactly this: a 4-int-record ring buffer for queue #1, and a
`byte[15]`/`float[6]` poll for queue #2.

### Reference implementations (read before writing code)

| Concern | Android reference (`SKapsule/`) | iOS-native reference (`Amethyst-iOS/`) | What SKapsule-iOS needs |
| --- | --- | --- | --- |
| Wire protocol / contract | `external/bootstrap/.../GLFW.java` (shared, already ports to iOS) | — | Nothing — already done |
| Input ring buffer (native) | `launcher/app/src/main/cpp/sklauncher.c`: `input_q` struct, `input_push()`, `glfw_drain_input_impl()` | `Natives/input_bridge_v3.m`: `events[]` + `sendData()` (different design — direct GLFW callback invocation, not applicable 1:1) | Port `sklauncher.c`'s ring-buffer design into `glfw_ios.m`, keyed to the same `EV_*` constants |
| Gamepad mailbox (native) | `sklauncher.c`: `gamepad` struct, `glfw_gamepad_present_impl`, `glfw_get_gamepad_state_impl` | — | Port the same mailbox design into `glfw_ios.m` |
| Touch → input queue | `GameActivity.kt`: `wireTouchInput()` (`SurfaceView.setOnTouchListener`) | `Amethyst-iOS/Natives/SurfaceViewController.m`: `sendTouchPoint:withEvent:` (grab-mode cursor, different UX model — SK doesn't use FPS-style mouse capture) | Override `touchesBegan:/Moved:/Ended:/Cancelled:` in `GameViewController.m`, push cursor-pos + mouse-button events, matching Android's down/move/up model (not Amethyst's grab/relative model) |
| Touch controls & joystick (UI) | `launcher/app/src/main/java/.../touch/`: `TouchControlModels.kt` (percent-based `ControlNode` data model, JSON-persisted via Gson, default dual-joystick + 7-button layout), `TouchControlOverlay.kt` (editable overlay with drag/resize/opacity panel), `TouchControlViews.kt` (canvas-drawn `TouchJoystickView`/button views) | `Amethyst-iOS/Natives/customcontrols/`: `ControlLayout.m` (UIView container, loads a layout dict/JSON file), `ControlButton.m`, `ControlJoystick.m` | Build a UIKit `ControlLayout`-style overlay; can reuse Android's percent-based `ControlNode` *model* conceptually (not code — different languages) for a consistent default layout across platforms |
| Gamepad (`GCController`) | `GameActivity.kt`: `InputDevice`/`MotionEvent` (Android controller API, not applicable) | `Amethyst-iOS/Natives/input/ControllerInput.m`: `registerControllerCallbacks:` — per-button `GCExtendedGamepad` handlers | Directly portable pattern — but write into the GLFW standard-layout mailbox (buttons/axes) instead of Amethyst's remap-to-keyboard-keys approach, since SKapsule-iOS's GLFW.java already expects a standard gamepad poll |
| Physical keyboard | `GameActivity.kt`: `glfwKeyCode()` (Android `KeyEvent.KEYCODE_*` → GLFW keycode table), `handleKeyboard()` | `Amethyst-iOS/Natives/input/KeyboardInput.m`: `keycodeTable[]` (`UIKeyboardHIDUsage*` → GLFW keycode table), `sendKeyEvent:down:` | Directly portable pattern — override `pressesBegan:`/`pressesEnded:` in `GameViewController.m` (or a dedicated responder), port `KeyboardInput.m`'s HID-usage table, push `EV_KEY` + `EV_CHAR` via the ring buffer instead of Amethyst's direct-callback model |

`GameController.framework` is **already linked** in `Natives/CMakeLists.txt` — no build-system
change needed for 36d.

### Wire protocol reference (authoritative — from `external/bootstrap/.../GLFW.java`)

**Queue #1 — mouse/keyboard ring buffer**, drained via `nativeDrainInput(int[] out)`. Each
record is 4 ints `[type, a, b, c]`:

| Type | Value | Meaning |
| --- | --- | --- |
| `EV_CURSOR_POS` | 1 | `a`=x, `b`=y (framebuffer px, y-down, top-left origin) |
| `EV_MOUSE_BUTTON` | 2 | `a`=button (0=left), `b`=action (1=press, 0=release) |
| `EV_SCROLL` | 3 | `a`=delta (±1) |
| `EV_KEY` | 4 | `a`=GLFW keycode, `b`=action (1=press, 2=repeat, 0=release), `c`=mods |
| `EV_CHAR` | 5 | `a`=Unicode codepoint |

Android's touch handler always emits a cursor-pos record before a button record so
`glfwGetCursorPos()` is correct by the time SK's button callback fires — replicate this
ordering.

**Queue #2 — gamepad mailbox**, polled via `nativeGamepadPresent()` / `nativeGetGamepadState(byte[15], float[6])`.
Standard GLFW gamepad layout — buttons 0–14: A, B, X, Y, LB, RB, Back, Start, Guide, L3, R3,
DPad-Up, DPad-Right, DPad-Down, DPad-Left. Axes 0–5: LeftX, LeftY, RightX, RightY, LTrigger,
RTrigger. **Triggers rest at −1, not 0** — reset state must set them explicitly, not `memset`.

### Sub-tickets

#### 36a. Touch input (core bridge) — do this first, everything else depends on it

- Port `sklauncher.c`'s `input_q` ring buffer (mutex-guarded `int32_t[CAP][4]`, `input_push`,
  drain-on-poll) into `glfw_ios.m`. Implement `nativeDrainInput` for real (currently `return 0`).
- Add plain C entry points (no JNI needed on the write side — `GameViewController.m` and
  `glfw_ios.m` are both native code in the same target, unlike Android where Kotlin UI code has
  to cross a JNI boundary via `NativeBridge.kt`'s `external fun`s into `sklauncher.c`). Something
  like `sk_input_push_cursor(x, y)`, `sk_input_push_mouse_button(button, pressed)`.
- Override `touchesBegan:`/`touchesMoved:`/`touchesEnded:`/`touchesCancelled:` in
  `GameViewController.m`. Track only the primary touch (SK's UI is single-cursor, matching
  Android's approach — don't build multitouch cursor tracking). Coordinates from `GameViewController`'s
  `surfaceView` are already in the EGL framebuffer's pixel space (same as Android's `SurfaceView`),
  so no scaling is needed beyond what `viewDidLayoutSubviews` already handles for Retina.
- **Acceptance:** on-screen taps move the SK cursor and click UI elements (login screen buttons
  should become tappable).

#### 36b. Touch controls / buttons

- Build a `ControlLayout`-style UIKit overlay (reference: `Amethyst-iOS/Natives/customcontrols/ControlLayout.m`
  + `ControlButton.m`), positioned over `GameViewController`'s surface view.
- Each button press writes into the **gamepad mailbox** (36d's data structure), not the mouse
  queue — matching Android's `TouchControlOverlay`/`onGamepadButton` model. This means 36b and
  36d share one native mailbox implementation; do 36d's mailbox plumbing as part of this ticket
  even if `GCController` wiring comes later.
- Also needs `sk_gamepad_set_virtual_active(BOOL)` (Android's `onVirtualGamepadConnected`) so SK
  treats the pad as connected while touch controls are up, even with no physical controller —
  otherwise button/axis writes are silently dropped by the `gamepad_active()` check.
- Default button layout: reference Android's `TouchControlModels.createDefaultLayout()` for
  a reasonable starting set (attack/ability buttons, item slots, strafe/dodge/defend/weapon-swap),
  though exact placement should be tuned for iOS screen sizes independently.
- **Acceptance:** on-screen buttons register presses SK's input system recognizes as gamepad
  input (bindable in SK's control settings, same as a physical controller).

#### 36c. Touch joystick

- Two virtual joysticks (move + face), UIView-based (reference: `ControlJoystick.m`), positioned
  like Android's default (`joy_move` bottom-left, `joy_face` bottom-right).
- Feed into the same gamepad mailbox axes: `GP_AXIS_LEFT_X/Y` for move, `GP_AXIS_RIGHT_X/Y` for
  face/aim.
- **Acceptance:** dragging each joystick drives the corresponding gamepad axis smoothly, with a
  small deadzone (Android uses `AXIS_DEADZONE = 0.15f` as a reference starting point).

#### 36d. Gamepad support

- `GameController.framework` already linked; no CMake changes needed.
- Register for `GCControllerDidConnectNotification`/`DidDisconnectNotification`, call
  `sk_gamepad_set_physical_active(BOOL)` (mirrors Android's `onGamepadConnected`) on change.
- Port the handler-registration pattern from `Amethyst-iOS/Natives/input/ControllerInput.m`'s
  `registerControllerCallbacks:` — one `GCExtendedGamepad` button/thumbstick handler block per
  input — but write directly into the GLFW-standard mailbox slot (buttons 0–14 / axes 0–5) rather
  than Amethyst's approach of remapping each button through a JSON keybind file to a keyboard key.
  SKapsule-iOS doesn't need that indirection because SK already reads a native gamepad via
  `glfwGetGamepadState`, exactly like the Android build.
- Trigger axes (`LT`/`RT`) rest at **−1**, matching Android's `GP_AXIS_LTRIGGER`/`RTRIGGER`
  convention — don't leave them at 0 on connect/reset.
- **Acceptance:** a paired MFi/Bluetooth controller drives movement and actions in-game; SK's
  control-binding screen recognizes it as a standard gamepad.

#### 36e. Keyboard/mouse support

- Physical keyboard: override `pressesBegan:`/`pressesEnded:` (UIKit `UIPress`/`UIKey` API) on
  `GameViewController` or a dedicated first-responder view. Port `Amethyst-iOS/Natives/input/KeyboardInput.m`'s
  `keycodeTable[]` (`UIKeyboardHIDUsage*` → GLFW keycode, already GLFW-standard and directly
  reusable) — but push through **this project's** `EV_KEY`/`EV_CHAR` ring-buffer records rather
  than Amethyst's direct-GLFW-callback model. Cross-check against Android's `glfwKeyCode()` table
  in `GameActivity.kt` (same target GLFW keycodes, different source enum) if any mapping is
  ambiguous.
- Typed characters: use `UIKey.characters` (as `KeyboardInput.m` does) for the `EV_CHAR` path,
  matching Android's `onCharInput`/`unicodeChar` approach — needed for login/chat text entry.
- Mouse/trackpad: lower priority. iPadOS pointer support (`UIPointerInteraction`) for
  external-mouse/trackpad users; push through the same `EV_CURSOR_POS`/`EV_MOUSE_BUTTON` records
  touch already uses.
- **Acceptance:** an external keyboard can type into SK's login/chat fields and drive bound
  hotkeys; mouse/trackpad pointer (where available) moves the SK cursor.

### Sequencing note

36a is a hard prerequisite for everything else (it's the ring buffer both the keyboard path and
initial UI navigation depend on). 36b and 36d should be built together since they share one
gamepad mailbox implementation — do the mailbox once. 36c can follow either. 36e (keyboard/mouse)
is independent and can be done in parallel with 36b–36d once 36a lands.

### New files

Building 36b/36c's touch-control overlay will likely need new `.m`/`.h` files (a `ControlLayout`
equivalent doesn't exist yet in this repo). Per `AGENTS.md`: **flag this before adding files** —
new Xcode source files also require a `project.yml` (XcodeGen) update to stay buildable from the
Xcode IDE, not just from `make native`.

---

## Build & verification

- `make native` after any change — must compile with 0 errors before moving on.
- After modifying `external/bootstrap` (shared with Android): no rebuild script here, it's
  built into `sk-bootstrap.jar` via `scripts/build-bootstrap.sh`. Changes to `GLFW.java` are
  **not expected** for Ticket 36 — the protocol is already complete on the Java side.
- Deploy to device via Xcode for on-device testing; `make package` for a distributable `.ipa`.
- Per `AGENTS.md`: one PR per sub-ticket (36a, 36b, etc.) where practical rather than one giant
  input-bridge PR — each is independently testable.
