# SKapsule-iOS Progress

Phase-level status. Engineering detail lives in [ROADMAP.md](ROADMAP.md); end-user setup
in [README.md](README.md).

## Status

| Phase | Description | Status |
| ----- | ----------- | ------ |
| 0 | Basic app setup, architecture, build | ✅ Complete |
| 1 | JVM bootstrap, NativeBridge, device debug | ✅ Complete |
| 1.5 | JNI bridge & GLFW shadow-class wiring | ✅ Complete |
| 2 | OpenGL surface & rendering bridge (gl4es) | ✅ Complete |
| 3 | Input bridge (touch, controls, gamepad, keyboard/mouse) | 🟡 Android parity landed — device validation pending |
| 4 | Audio (OpenAL) | ✅ Complete |
| 5 | Steam login | ✅ Complete |
| 6 | iOS 26 JIT bring-up (TXM / StikDebug) | ✅ Complete |
| 7 | Render fidelity & in-game stability | 🟡 Heap corruption fixed — validation pending |

The app boots the JVM, renders the real desktop client through gl4es, plays audio, logs in
(Web or Steam, including Steam Guard), and reaches gameplay on device.

## Phase 7 — stability

The heap corruption that killed sessions from 2026-08-15 onward is **fixed**: gl4es's
`clear_program` passed `kh_foreach`'s *key* to `kh_del` as if it were a bucket index,
leaving freed `uniform_t` blocks live in the hash for the sampler-init loop to `memset`
through. AddressSanitizer identified it after the cheaper instruments (libmalloc's own
checker, `malloc_zone_check`, stack canaries) all came up empty. Full write-up and the
list of ruled-out theories are in ROADMAP.md.

Also fixed this round: a main-thread/render-thread GL race on one `EAGLContext`, render
scale not applying until the slider was touched, and the safe-area insets wasting space
around the Dynamic Island and long edges.

Remaining: on-device validation past the prologue — character select, Haven, a full level,
and level transitions.

## Phase 3 — input bridge

`Natives/glfw_ios.m` holds the thread-safe GLFW event ring buffer and the shared
standard-layout gamepad mailbox. `GameViewController.m` routes direct touch, physical
keyboard, pointer hover, virtual controls and `GCController` callbacks through them.

- [x] **36a. Touch input** — primary-touch cursor/click bridge, cursor-before-button ordering
- [x] **36b. Touch controls / buttons** — UIKit overlay writing to the virtual gamepad mailbox
- [x] **36c. Touch joystick** — virtual move and face joysticks
- [x] **36d. Gamepad support** — `GCController` → GLFW-standard 15-button / 6-axis mailbox
- [x] **36e. Keyboard/mouse** — `UIKey` press/character routing plus pointer-hover cursor

The customization layer now matches the Android port: percent-based node model with an ESC
button and right-stick attack, drag-to-reposition edit mode, per-node visibility and scale,
**Show Controls** / **Show Action Bar**, opacity and resolution sliders, and a soft-keyboard
bridge. New files: `SKTouchControls.{h,m}`, `SKTouchControlOverlay.{h,m}`,
`SKKeyboardBridge.{h,m}`.

Remaining acceptance checks: bind and use each touch/gamepad control in-game, type in
login/chat with an external keyboard, and verify external mouse/trackpad on iPadOS.
