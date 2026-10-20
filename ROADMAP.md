# SKapsule-iOS Engineering Notes

Invariants, open gaps and diagnostics for contributors. [README.md](README.md) has the
end-user setup; [AGENTS.md](AGENTS.md) the conventions.

Resolved sagas are condensed to their conclusions. Full detail is in git history.

---

## Current State

The app boots the bundled JRE 25, runs the real Spiral Knights desktop client through
gl4es, plays audio and logs in (Web or Steam, including Steam Guard). Gameplay was reached
on device before the symlink-free JRE layout; on that layout the runtime boots and the
remaining crashes are FFM upcalls (see *History*), each fixed as it appears. The runtime is
the AngelAuraMC JDK-25 **JIT** build, so on-device runs need JIT: built-in (StikJIT) or the
StikDebug app, both running `skapsule-jit.js` passed inline.

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
- **Never query GL for the drawable size.** `pointToPixelScale` reads
  `self.lastDrawableSize`; `nativeGetSurfaceSize` reads the cached ints published by
  `sk_gl_set_drawable_size` (Android reads plain cached ints too). Its only caller is
  `glfwCreateWindow`, which LWJGL runs *before* `glfwMakeContextCurrent` — a GL query there
  is a silent no-op and SK gets the full unscaled size, which is what put the viewport in
  the bottom-left corner at every launch until the slider was touched.

### Surface geometry — `Natives/GameViewController.m`

- **`UIView.contentScaleFactor`, never `layer.contentsScale`.** UIKit re-applies
  `contentScaleFactor` to the layer whenever the view joins a window or lays out, so a
  render scale written straight to `gEAGLLayer` is silently reset to the screen scale.
  Re-assert it on every layout.
- **Render scale must be applied before the first `renderbufferStorage`**, or the HUD is
  laid out for a framebuffer that no longer exists. It is a framebuffer divisor (matching
  Android's `SurfaceHolder.setFixedSize`), not a DPI or Cacio change; `-Dcacio.managed.screensize`
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

### JRE layout — `Makefile` (`METHOD_STAGE_JRE`)

The stock JDK layout, **with no symlinks**: `java.home` is `jre25`, so `jre25/lib/modules`
and the natives (`libjava`, `libjimage`, `libzip`, …) live in `jre25/lib`, `conf/` in
`jre25/conf`, fonts in `jre25/lib/fonts`, and `libjvm`/`libjsig` in `jre25/lib/server`.

**How this was established, and how to re-check it without a device.** Retag the JRE's
dylibs with `vtool -set-build-version macos 14.0 14.0 -replace`, re-sign ad hoc, and call
`JLI_Launch` from a small C host (dlopen `libjli`, set `JAVA_HOME` and `INTERNAL_JLI_PATH`,
forward the `main()` re-entry) with `-Xint -XX:-UseCompressedClassPointers
-XX:+UnlockExperimentalVMOptions -XX:+DisablePrimordialThreadGuardPages -Xshare:off
-XshowSettings:properties -version`. This exact libjvm then prints `java.home = …/jre25` and
`sun.boot.library.path = …/jre25/lib`, and `-version` succeeds. Boot-path setup runs before
the code cache, so the check needs no JIT. It reproduced the device failure on demand.

What went wrong before, so it is not repeated:
- A layout derived from reading `openjdk/mobile`'s `os_bsd.cpp` (java.home = libjvm's own
  directory) was **wrong for this binary**: it fails with `Failed setting boot class path.`
  because the VM looks for `<java.home>/lib/modules`. Trust the binary, not the upstream source.
- `-Dsun.boot.library.path` and `-Djava.home` are not the answer either.
- The old symlinks (app-root `lib`/`conf`, `server/lib`, per-dylib links) were not needed
  for java.home, and signing services rewrite every symlink in a bundle as a small text file
  holding the link target. `make package` fails on any symlink.

A VM that dies during init prints its reason to stderr and `_exit`s, so the line can be lost
to the stdio pipe, and `vmout-*.log` (`-XX:+LogVMOutput`) is opened *after* `java.home` and
the boot path are set, so it **cannot** capture this class of failure. Every launch now logs
the size of `lib/modules`, `libjimage` and `libjvm` as installed, and `Build:` (an
Info.plist stamp, because `CONFIG_COMMIT` goes stale).

### Runtime staging and boot — `Natives/SKInstaller.m`

- **Staged jars refresh on every launch**, comparing each bundled jar with its staged copy
  (size + mtime). Gating it on the version marker served the previous build's frenchpress
  and cacio after an update built from the same commit.
- **`repairGameJars` checks `sk/code/projectx-config.jar` for a canary entry** before each
  launch and drops jar and `.jarv` marker if unreadable: getdown decides validity from the
  marker alone and never re-hashes. Both ports pass `-Dcheck_unpacked=true`.
- **The boot overlay is dismissed only by SK's first frame**; a 90 s watchdog replaces it
  with an error and reports `boot_timeout`. Without it, a client that died during boot left
  the last getdown status ("Validating 75%") on screen.
- **Render-scale floor is 0.6.** At 0.5 a 1080p-tall device gives SK a 540 px surface and
  its UI stops laying out (578 px worked, measured on Android).

### Crash reporting and news — `Natives/SKReporter.m`, `Natives/SKNewsFeed.m`

- **No Sentry SDK.** Its crash handler installs Mach exception and signal handlers that
  HotSpot needs for implicit null checks, and it declines to report under a debugger, which
  every JIT run has. `SKReporter` POSTs an envelope itself; the real signal is the JVM's
  `hs_err`, sent on the next launch with a scrubbed log tail.
- **The news service is plain HTTP**, so its payload is untrusted: image and link URLs are
  dropped unless HTTPS, the download is size-capped, and `machineId` is a constant, not a
  device identifier.

### Built-in JIT — `Natives/SKBuiltinJIT.m`, `Natives/JITHelper/`

A process cannot debug itself, so the `SKJITHelper.appex` extension links StikJIT and
attaches to the app's pid over the device's debug tunnel (LocalDevVPN + a pairing file),
running `skapsule-jit.js` passed inline. The app starts it through the private
`NSExtension` API (`com.apple.ar.viewer` extension point, the same route pziOS uses). Its
debugger attaches like StikDebug's, so readiness is still `isJITEnabled()`. The StikDebug
path now passes the script inline too (`script-data`, base64url), so neither method needs
the script imported or assigned.

- Built twice, kept in step: `METHOD_STAGE_JITHELPER` (plain `swiftc`) for `make
  package`, the `SKJITHelper` target in `project.yml` for Xcode.
- `StikJIT.framework` sits in the **app's** `Frameworks/`, not the extension's: `ldid`
  cannot sign a framework nested in an extension in an app ("cannot find Info.plist").
  Only the extension links it, so the app never loads it below iOS 17.4.
- StikJIT's `project.yml` declares no `Info.plist`; `build-stikjit-ios.sh` writes one,
  because installd rejects a framework without it.
- `xcode-payload` must not empty `Frameworks/`: Xcode has embedded StikJIT there by then.
- `codesign --verify` cannot check this bundle: macOS reports `ldid`'s iOS signatures as
  "not signed at all". Re-signing with zsign is the check that means something.
- CI needs `xcodegen` (`brew install … xcodegen` in the workflow) to build StikJIT.
- Unverified on a device so far.

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

### Java preferences

Seeded on first launch by `init_seedGamePrefs` (`Natives/main.m`), matching Android's
`PrefsInstaller`: `anonymous_logon=false`, `compatibility_mode=true`,
`cull_transients_prod=true`, `render_quality=LOW`. Written only when absent, so a player's
own settings are never stomped.

The file lands at `home/.userPrefs/.java/.userPrefs/projectx/prefs.xml` — the JDK's
`FileSystemPreferences` appends `.java/.userPrefs` to `java.util.prefs.userRoot` itself.
Every component is a dotfile, which is why `home/` **looks** empty in Files.app; it is
visible over USB in Finder.

### Footguns

- **The `[Pre-Init] Commit:` line goes stale.** `Natives/config.h` is generated by
  `configure_file` but also checked in, and only regenerates when CMake *configures*. Do
  not use it to decide whether a build contains a change — jars and dylibs stage from
  `out/` independently.
- **The deployment target is 17.4 everywhere** (`Makefile`, `project.yml`, the JIT helper):
  the oldest iOS the JIT methods (StikJIT, StikDebug) work on. Raising it drops TrollStore
  installs on iOS 17.0 and older, which could use `PT_TRACE_ME` JIT; the TrollStore build is
  untested either way. Keep the app, helper and `apps.json` `minOSVersion` in step.
- **The "SKapsule Heap Diagnostics" scheme does nothing.** Its `MallocScribble` /
  `MallocGuardEdges` only apply when launching from Xcode, and Xcode's debugger cannot
  service the JIT trap.
- **Game Mode not engaging is not proof the keys are wrong.** `LSApplicationCategoryType`
  is what the OS actually decides from (`LSSupportsGameMode` / `GCSupportsGameMode` only
  opt in or out), and it skips a relaunch that follows too soon after the last quit —
  allow ~5 minutes between test launches. It never engages in the simulator, and nothing
  forces it on.

---

## The JIT badge has one blind spot

`isJITEnabled` on a TXM device checks `CS_DEBUGGED` plus `getppid() != 1`
(`utils.m:154-165`) — it can see that *a* debugger is attached, not that the attached one is
running `skapsule-jit.js`. A debugger attached without the script (an old StikDebug that
ignores the inline script, with none assigned) therefore turns the pill green and the launch proceeds into `brk #0x69` with nobody to
service it, which kills the process instantly: no `hs_err`, a 0-byte vmlog, and a log that
simply stops after `[JIT26] Requesting N MB for JIT mapping`.

There is no reliable in-process way to tell the two apart, so the gate is unchanged. Instead
the next launch detects it after the fact — `SKPreviousRunDiedOnJITTrap` looks for that
request line without the `[JIT26] mapping at RW=…, RX=…` that follows a serviced trap — and
says so in an alert rather than letting the app die silently again.

Related: `assets/skapsule-jit.js` sets `detachAfterFirstBr = true`, so the script services
exactly one trap. A second executable reservation later in a session would hit the same dead
trap; that is the standing argument for keeping the code cache large enough
(`-XX:ReservedCodeCacheSize`) that HotSpot never needs one.

## Known gaps

- **gl4es ES3 core capabilities** (`npot`, `elementuint`, `depthtex`, `rgtex`) are forced
  on ES3 contexts alongside the renderbuffer formats. They change codegen and sampling
  paths, so bisect here first if new visual artifacts appear; `LIBGL_NOES3CORE=1` disables
  the whole block.
- Android has no pointer-hover producer: `onGenericMotionEvent` handles scroll and joystick
  but drops `ACTION_HOVER_MOVE`, so a mouse only moves the cursor while a button is held.
- iOS has no hardware-key auto-repeat (UIKit does not repeat `UIPress`; needs a timer keyed
  off `pressesBegan`/`pressesEnded`), reports no NUM_LOCK bit, and `onToggleKeyboard`
  resigns first responder without reclaiming it, so the hardware
  keyboard stops working after one soft-keyboard toggle.
- `glfwGetJoystickHats`/`Name`/`GUID` return null while `glfwJoystickPresent` returns true,
  and only `jid 0` is supported — a second controller is invisible.
- Android's gamepad presence check accepts any `SOURCE_JOYSTICK` device, which some
  keyboards and remotes advertise.
- Mouse-button callbacks always report `mods = 0` (`GLFW.java:81`), so shift/ctrl-click is
  invisible to SK.
- The input queue drops the *newest* records when full (`glfw_ios.m`), which for keys means
  a lost release and a stuck key. Related: a held button latches if its input source
  disconnects while another source is still active.
- UI follow-ups: `handleChromeDrag` doesn't clamp, so a gear button
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
- **Touch routing differs by necessity.** iOS relies on UIKit hit testing — each control is
  a real subview and gets its own `UITouch`, and the overlay's `hitTest:` returns nil in the
  gaps so misses reach the GL surface. Android has no equivalent (ViewGroup dispatch would
  give one child the whole gesture), so its overlay routes pointers by hand; that hand-rolled
  path is where issue #43 came from (it hit-tested with pointer 0's coordinates, so no button
  could be pressed while a joystick was held). Both ports release every held control on
  layout rebuild, edit-mode toggle and Show-Controls-off, or a button latches.
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
  The same crash hit again at OpenAL setup (2026-10-16): SK registers a
  `SOFTSystemEventProc` (`ALC_SOFT_system_events`, device hot-plug), another `Callback`
  subclass, and died in `CodeBlob::CodeBlob` ← `UpcallStub::create` with SIGBUS
  `BUS_ADRALN` at an address inside the code cache — the stub's blob header is written
  through the RX alias instead of the RW mirror, so **any** LWJGL `Callback` crashes this
  JVM. `assets/shadow/org/lwjgl/openal/SOFTSystemEventProc.java` shadows it (built into
  `sk-bootstrap.jar` by `build-bootstrap.sh`, iOS only; address 0, so OpenAL gets a null
  callback and reports no device events). If a new `org.lwjgl.*Callback`/`*Proc` shows up in
  an `hs_err` under `UpcallLinker::make_upcall_stub`, shadow it the same way.
  The JDK itself has one too (2026-10-16): `sun.font.HBShaper`'s static initialiser builds
  upcall stubs, reached from `SunLayoutEngine.layout` the first time SK measures text
  (`Font.layoutGlyphVector` via `com.threerings.opengl.gui.text.a.getKerning`) — the same
  SIGBUS, 4 s into a launch. It cannot be shadowed (it is in `java.desktop`), but JDK 25
  keeps a switch: `-Dsun.font.layout.ffm=false` selects the JNI HarfBuzz path, whose natives
  `libfontmanager` exports (`Java_sun_font_SunLayoutEngine_shape`, `createFace`). Set in
  `JavaLauncher.m`. Unverified on device: a Mac test cannot run Java2D without the cacio agent.
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
