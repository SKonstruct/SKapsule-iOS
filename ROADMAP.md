# SKapsule-iOS Engineering Roadmap

Engineering detail for the active work. [PROGRESS.md](PROGRESS.md) has the phase-level
status table; [README.md](README.md) has the end-user setup.

Resolved sagas are condensed to their conclusions. Full detail is in git history.

---

## Current State

The app boots the bundled JRE 25, runs the real Spiral Knights desktop client through
gl4es, plays audio, logs in (Web or Steam, including Steam Guard), and reaches gameplay
on device. The runtime is the AngelAuraMC JDK-25 **JIT** build, so on-device runs require
StikDebug with `UniversalJIT26.js` assigned to the bundle id.

The long-running heap corruption (2026-08-15 → 08-19) is **fixed** — see *Root cause*
below. Remaining work is validation and the visual/UX gaps listed under *Known gaps*.

---

## Invariants

Each of these cost at least one debugging round. Breaking one reintroduces a crash that
looks like something else entirely.

### GL threading — `Natives/GameViewController.m`

- **GL may only be issued from the main thread before SK's render thread starts**
  (`self.jvmKicked`). SK's render thread holds `gEAGLContext` (`glfw_ios.m:200`, `:224`);
  two threads issuing into one EAGLContext corrupts the Apple driver's own heap. The
  drawable is built once in `viewDidLoad` and never resized afterwards.
- **`[EAGLContext setCurrentContext:nil]` on every exit** from a main-thread GL block, so
  nothing later inherits the renderer's context.
- **Never query GL for the drawable size.** `pointToPixelScale` runs per touch-move; it
  reads `self.lastDrawableSize`.

### Surface geometry — `Natives/GameViewController.m`

- **`UIView.contentScaleFactor`, never `layer.contentsScale`.** UIKit re-applies
  `contentScaleFactor` to the layer whenever the view joins a window or lays out, so a
  render scale written straight to `gEAGLLayer` is silently reset to the screen scale.
  Re-assert it on every layout.
- **Render scale must be applied before the first `renderbufferStorage`**, or
  `nativeGetSurfaceSize` reports full resolution to SK at init and the HUD is laid out for
  a framebuffer that no longer exists. It is a framebuffer divisor (matching Android's
  `SurfaceHolder.setFixedSize`), not a DPI or Cacio change; `-Dcacio.managed.screensize`
  stays at the **unscaled** screen size.
- **Safe area is hand-rolled in `gameSafeAreaInsets`**, not `view.safeAreaInsets`. UIKit
  mirrors the sensor-housing inset onto *both* sides, adds ~11pt of margin beyond the
  housing, and reserves the whole home-indicator strip. We inset the housing edge only
  (minus that margin), 8pt on the side edges and 2pt on the long edges — the display curve
  clips only at corners, not along an edge's middle.
- `UIInterfaceOrientationLandscapeRight` means the sensor housing is on the **left** (the
  enum is defined against the device orientation, inverting the reading its name suggests).
- **Live drawable resizes go through the render thread.** The resolution slider sets
  `contentScaleFactor` on the main thread (UIKit, not GL) and raises a flag;
  `nativeSwapBuffers` performs the `renderbufferStorage:fromDrawable:` at end-of-frame on
  the thread that owns the context, then pushes `sk_input_push_framebuffer_size` so SK
  re-lays out its HUD. That event is pushed **only** for a deliberate resize — it makes the
  Three Rings renderer rebuild render targets (`GLFW.java:93-98` fires both the
  framebuffer-size and window-size callbacks), which is not something to do at launch or
  per slider tick.

### gl4es

- **`gl4es_glDetachShader`'s `if(glprogram->linked) return;` early-out is load-bearing**
  despite being spec-incorrect. gl4es keeps raw `shader_t*` in `last_vert`/`last_frag` and
  never clears them, so a real detach frees a shader the program still reads
  (`fpe.c:494`). Leaking the shader is the lesser bug. Fix `last_vert`/`last_frag` and
  `glprogram->attach[]` first if this is ever revisited.
- **`kh_foreach`'s second parameter is the key, not the bucket index.** Never pass it to
  `kh_del`. See *Root cause*.

---

## Root cause of the heap corruption (fixed 2026-08-19)

`clear_program` used `kh_foreach`'s key as a bucket index:

```c
kh_foreach(glprogram->uniform, k, m,
    free(m->name); free(m);
    kh_del(uniformlist, glprogram->uniform, k);   // k is the uniform's LOCATION
)
```

So on every relink each `uniform_t` was freed while **its own bucket stayed live** holding
a dangling pointer, and `kh_del` marked whatever unrelated bucket sat at
`index == location`. `fill_program`'s sampler-init loop then walks every live bucket and
does `memset((char*)cache + m->cache_offs, 0xff, m->cache_size)` through freed memory —
an **arbitrary-offset heap write**, and the writer behind every libmalloc "corruption of
free block" abort. The same stale entries fed the `strlen(NULL)` crash in
`gl4es_glGetUniformLocation`.

Fixed by iterating bucket indices directly in both the uniform and attribloc loops. The
other `kh_foreach` sites (`fpe.c:292,512,589,613`, `program.c:672`) only read the value.

It hid for so long because upstream never *read* the stale pointer — `fill_program`
unconditionally overwrote `kh_value`, leaking but never touching it. Adding `kh_put`
return-value handling (as a leak fix) started reading and `free()`ing it, which is what
finally gave AddressSanitizer something to catch.

### Ruled out — do not re-chase

| theory | how it was excluded |
| --- | --- |
| stack smash | gl4es built `-fstack-protector-strong`; no canary ever fired |
| transposed-matrix overflow | real bug, fixed (`tmp[16]` scratch sized for one matrix while the loop wrote `count`), but shipped before a crash that still reproduced |
| `texunits` overflow | real bug, bounded against `MAX_TEX`, but shipped before a crash that still reproduced |
| ES3 capability flags | every read site audited: `elementuint` changes no buffer arithmetic; `npot=3` unlocks an overflow only under `LIBGL_TEXCOPY`, unset here; `depthtex` has an OOB *read* gated on non-default `glPixelTransfer` |
| main-thread GL race | real bug, fixed (see Invariants), but not the corruption |
| `malloc_zone_check` | blind on iOS 27's xzone allocator — reported nothing all session while libmalloc aborted seconds later |

---

## Diagnostics

### AddressSanitizer

```sh
SK_ASAN=1 ./scripts/build-gl4es-ios.sh    # + uncomment OTHER_LDFLAGS in project.yml
```

`scripts/stage-app-assets.sh` copies the runtime into `Frameworks/` when gl4es carries the
dependency. Reports reach `latestlog.txt` via the stdio tee. Three prerequisites:

- **The app must link the runtime**, not the dlopen'd gl4es — arriving late aborts with
  *"Interceptors are not working"*. `project.yml` links it into `SKapsule.debug.dylib`,
  which dyld loads before `main()`. Linker flag only; app code stays uninstrumented.
- **Nothing may call `malloc_zone_check`** — ASan leaves that zone callback unimplemented
  and aborts with *"CHECK failed: sanitizer_malloc_mac.inc"*.
- Options come from `__asan_default_options()` in `Natives/main.m`, since `ASAN_OPTIONS`
  cannot be set for a sideloaded app. Signal handling is left to the JVM.

Expect ~2-3x slower. Diagnostic only.

### Footguns

- **The `[Pre-Init] Commit:` line goes stale.** `Natives/config.h` is generated by
  `configure_file` but also checked in, and only regenerates when CMake *configures*. Do
  not use it to decide whether a build contains a change — jars and dylibs stage from
  `out/` independently.
- **The "SKapsule Heap Diagnostics" scheme does nothing.** Its `MallocScribble` /
  `MallocGuardEdges` only apply when launching from Xcode, and Xcode's debugger cannot
  service the JIT trap.

---

## Known gaps

- **gl4es ES3 core capabilities** (`npot`, `elementuint`, `depthtex`, `rgtex`) are forced
  on ES3 contexts alongside the renderbuffer formats. They change codegen and sampling
  paths, so bisect here first if new visual artifacts appear; `LIBGL_NOES3CORE=1` disables
  the whole block.
- No scroll-wheel producer on either platform (`EV_SCROLL` is handled but never pushed),
  so SK inventory/chat lists cannot be scrolled by touch.
- No right/middle click and no long-press→right-click, on either platform.
- `GCController` thumbstick Y is up-positive while touch joysticks derive Y from screen
  coords (down-positive) — verify on device.
- The input queue drops the *newest* records when full (`glfw_ios.m`), which for keys means
  a lost release and a stuck key.
- UI follow-ups: `onToggleKeyboard` doesn't restore the VC as first responder (hardware
  keyboard dies after one show/hide); `handleChromeDrag` doesn't clamp, so a gear button
  dragged off-screen is unrecoverable; cancelling the "Waiting for JIT" alert leaves
  `bootOverlay` with no dismiss path.

---

## Touch parity with Android

Ported from `SKapsule/launcher/.../touch/`. **Keep the two in sync** — the layout schema,
default node table and slider ranges are meant to stay comparable, so a change to one
usually belongs in the other.

- `Natives/SKTouchControls.{h,m}` — percent-based node model + `SKTouchLayout`
  (`globalOpacity`, `controlsEnabled`, `actionBarVisible`, `renderScale`, nodes),
  JSON-persisted in `NSUserDefaults`. All 16 Android default nodes including `btn_esc`
  (GLFW 256). `scale`/`renderScale` clamp on load so an older schema can't decode to 0.
- `Natives/SKTouchControlOverlay.{h,m}` — edit mode, per-node visible/scale, opacity and
  resolution sliders, **Show Controls** / **Show Action Bar**, double-tap-confirm Reset.
  Every appearance change re-asserts `sk_gamepad_set_virtual_active(controlsEnabled)`, or a
  latched `Strafe` toggle has no reset path. Right stick presses axis 5 and holds the last
  aim direction 200 ms on release. **Deadzone applies to physical sticks only.**
- `Natives/SKKeyboardBridge.{h,m}` — offscreen `UIKeyInput` first responder.
- `GameViewController.m` — ⚙ / Keyboard chrome buttons (draggable in edit mode, 20 pt slop,
  persisted in `game_chrome_prefs`); the overlay is sized to `surfaceView`, not `self.view`.

---

## History (condensed)

- **JVM boot & staging.** `JavaLauncher.m` boots JRE 25 via `JLI_Launch`;
  `dyld_bypass_validation.m` allows the unsigned dylibs; `SKInstaller.m` stages
  JARs/assets version-aware so a rebuilt JAR is never served from stale cache.
- **iOS 26 JIT bring-up.** Boot chain fixed: compressed-class-pointer abort → missing
  `libawt_xawt.dylib` → `java.awt.Font.initIDs` → `GLFWNativeCocoa` → FFM upcall stubs.
  The last one matters: LWJGL's `GLFW*Callback` classes build a Panama upcall stub in
  their constructor, which crashed the mirror-mapped code cache. SK's GLFW is fully
  shadowed, so `sk-bootstrap.jar` shadows the callback classes to skip
  `org.lwjgl.system.Callback` entirely.
- **Rendering.** `CAEAGLLayer`-backed `EAGLContext` with color + depth/stencil
  renderbuffers. Fixed: a render-thread SIGSEGV in gl4es's FBO 0 handling, a
  framebuffer-incomplete depth attachment, a `glGetUniformLocation` NULL-name crash, and a
  use-after-free in gl4es buffer management (`buffers.c` now updates all VAOs in
  `glstate->vaos`, not just the active one).
- **gl4es GLES 3 core formats.** `GetHardwareExtensions()` detects capabilities by
  string-matching ES2-era `OES` names, but on an ES3 context `packed_depth_stencil`,
  `depth24` and `rgb8_rgba8` are *core* and never advertised — so all three stayed 0,
  splitting `GL_DEPTH24_STENCIL8` (which Apple GPUs reject) and downgrading RGB8/RGBA8 to
  RGB565/RGBA4. Now probed from `glGetString(GL_VERSION)`.
- **Fonts (cacio).** `SunFontManager` only auto-registers the JRE font directory on Linux,
  so iOS needed a forced `registerFontDir()`, a hand-built `fonts.dir` XLFD mapping and a
  null-safe `findFont2D` fallback.
- **AWT / Java2D.** `awt_stubs.c` replaces `libawt_headless.dylib`; its exported symbol set
  had to be exact — over-stubbing shadowed real rendering-loop registration, under-stubbing
  produced `UnsatisfiedLinkError` on platform-backend `initIDs`.
- **Steam login.** A self-deadlock in `showSteamGuardPromptWithTitle:` (nested
  `dispatch_async(main_queue)` behind a main-queue semaphore wait) fixed; Web and Steam
  login including Steam Guard verified on device.
- **Input bridge (Ticket 36).** Touch, on-screen controls, gamepad and keyboard/mouse all
  feed two shared native structures — a 4-int-record event ring buffer and a GLFW
  standard-layout gamepad mailbox — so SK never knows which producer it is hearing. Wire
  protocol is in `external/bootstrap/.../GLFW.java`; trigger axes rest at **−1**, not 0.

---

## Build & verification

```sh
make native                      # CMake build of the native app
./scripts/build-gl4es-ios.sh     # -> out/gl4es/libgl4es.dylib
make package                     # -> .ipa in out/artifacts/
```

Deploy to device via Xcode; the post-build phase re-runs `make xcode-payload`. Adding a
source file under `Natives/` needs `xcodegen generate` — `project.yml` globs the directory,
but `SKapsule.xcodeproj` is checked in and no build step regenerates it, so a missing run
shows up as `Undefined symbol: _OBJC_CLASS_$_…` long after `make native` passed.
