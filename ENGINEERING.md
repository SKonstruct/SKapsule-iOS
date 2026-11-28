# SKapsule-iOS Engineering Notes

Invariants, open gaps and diagnostics for contributors. [README.md](README.md) has the
end-user setup; [AGENTS.md](AGENTS.md) the conventions.

Resolved sagas are condensed to their conclusions. Full detail is in git history.

---

## Current State

The app boots the bundled JRE 25, runs the real Spiral Knights desktop client through
gl4es, plays audio and logs in (Web, or Steam by QR code or username and password). The runtime is the
AngelAuraMC JDK-25 **JIT** build, so on-device runs need JIT: built-in (StikJIT) or the
StikDebug app, both running `skapsule-jit.js` passed inline.

---

## Invariants

Each of these cost at least one debugging round. Breaking one reintroduces a crash that
looks like something else entirely.

### GL threading — `Natives/GameViewController.m`

- **GL may only be issued from the main thread before SK's render thread starts**
  (`self.jvmKicked`). SK's render thread holds `gEAGLContext` (`glfw_ios.m`); two threads
  issuing into one EAGLContext corrupts the Apple driver's own heap. The drawable is built
  once in `viewDidLoad` and never resized afterwards.
- **`[EAGLContext setCurrentContext:nil]` on every exit** from a main-thread GL block, so
  nothing later inherits the renderer's context.
- **Never query GL for the drawable size.** `pointToPixelScale` reads
  `self.lastDrawableSize`; `nativeGetSurfaceSize` reads the cached ints published by
  `sk_gl_set_drawable_size`. Its only caller is `glfwCreateWindow`, which LWJGL runs *before*
  `glfwMakeContextCurrent`: a GL query there is a silent no-op and SK gets the full unscaled
  size (viewport stuck in the bottom-left corner).
- **No GL while the scene is inactive.** iOS terminates an app that submits GL in the
  background. `SceneDelegate` raises `sk_gl_set_paused`; `nativeSwapBuffers` runs `glFinish`
  and parks the render thread on a condition variable until the scene is active again.

### Surface geometry — `Natives/GameViewController.m`

- **`UIView.contentScaleFactor`, never `layer.contentsScale`.** UIKit re-applies
  `contentScaleFactor` to the layer whenever the view joins a window or lays out, so a
  render scale written straight to `gEAGLLayer` is silently reset. Re-assert it on every layout.
- **Render scale must be applied before the first `renderbufferStorage`**, or the HUD is
  laid out for a framebuffer that no longer exists. It is a framebuffer divisor (matching
  Android's `SurfaceHolder.setFixedSize`), not a DPI or Cacio change;
  `-Dcacio.managed.screensize` stays at the **unscaled** screen size. The floor is 0.6: at 0.5
  a 1080p-tall device gives SK a 540 px surface and its UI stops laying out.
- **Safe area is hand-rolled in `gameSafeAreaInsets`**, not `view.safeAreaInsets`. UIKit
  mirrors the sensor-housing inset onto *both* sides, adds ~11pt of margin beyond the
  housing, and reserves the whole home-indicator strip. We inset the housing edge only
  (minus that margin), 8pt on the side edges and 2pt on the long edges.
- `UIInterfaceOrientationLandscapeRight` means the sensor housing is on the **left**.
- **Live drawable resizes go through the render thread.** The resolution slider sets
  `contentScaleFactor` on the main thread and raises a flag; `nativeSwapBuffers` performs the
  `renderbufferStorage:fromDrawable:` at end-of-frame on the thread that owns the context,
  then pushes `sk_input_push_framebuffer_size` so SK re-lays out its HUD. That event is pushed
  **only** for a deliberate resize: it makes the Three Rings renderer rebuild render targets,
  which is not something to do at launch or per slider tick.

### JRE layout — `Makefile` (`METHOD_STAGE_JRE`)

The stock JDK layout, **with no symlinks**: `java.home` is `jre25`, so `jre25/lib/modules`
and the natives (`libjava`, `libjimage`, `libzip`, …) live in `jre25/lib`, `conf/` in
`jre25/conf`, fonts in `jre25/lib/fonts`, and `libjvm`/`libjsig` in `jre25/lib/server`.

- Trust the binary, not upstream source: a layout derived from `openjdk/mobile`'s
  `os_bsd.cpp` (java.home = libjvm's own directory) fails with `Failed setting boot class
  path.` because this VM looks for `<java.home>/lib/modules`. `-Dsun.boot.library.path` and
  `-Djava.home` are not the answer either.
- Signing services rewrite every symlink in a bundle as a small text file, and `make package`
  fails on any symlink.
- **Re-check without a device:** retag the JRE's dylibs with `vtool -set-build-version macos
  14.0 14.0 -replace`, re-sign ad hoc, and call `JLI_Launch` from a small C host (dlopen
  `libjli`, set `JAVA_HOME` and `INTERNAL_JLI_PATH`, forward the `main()` re-entry) with
  `-Xint -XX:-UseCompressedClassPointers -XX:+UnlockExperimentalVMOptions
  -XX:+DisablePrimordialThreadGuardPages -Xshare:off -XshowSettings:properties -version`.
  Boot-path setup runs before the code cache, so no JIT is needed.
- A VM that dies during init prints its reason to stderr and `_exit`s, so the line can be lost
  to the stdio pipe, and `vmout-*.log` (`-XX:+LogVMOutput`) opens *after* `java.home` and the
  boot path are set, so it **cannot** capture this class of failure. Every launch logs the
  size of `lib/modules`, `libjimage` and `libjvm` as installed, and `Build:` (an Info.plist
  stamp, because `CONFIG_COMMIT` goes stale).

### Runtime staging and boot — `Natives/SKInstaller.m`

- **Staged jars refresh on every launch**, comparing each bundled jar with its staged copy
  (size + mtime). Gating it on the version marker served the previous build's frenchpress
  and cacio after an update built from the same commit.
- **`repairGameJars` checks `sk/code/projectx-config.jar` for a canary entry** before each
  launch and drops jar and `.jarv` marker if unreadable: getdown decides validity from the
  marker alone and never re-hashes. Both ports pass `-Dcheck_unpacked=true`.
- **The boot overlay is dismissed only by SK's first frame.** A stall timer (90 s, restarted
  by every status message) replaces it with an error and reports `boot_timeout`; without it a
  client that died during boot left the last getdown status on screen.

### Mods — `Natives/SKModManager.m`, `Natives/SKZipUtils.m`

- **Mod archives and `mod.json` are third-party input.** Zip offsets are bounds-checked,
  declared sizes capped (512 MB per entry, 2 GB per archive), entry names and locale bundle
  keys confined to their extraction root, and every `mod.json` value type-checked.
- **Downloads are verified against the listing's git blob SHA** (and only taken from
  `raw.githubusercontent.com` over HTTPS) before being moved into place. The listing's
  `main` branch is trusted, not pinned. A sync only deletes files an earlier sync wrote
  (`mod_sync_files`); the user's own mods are never removed.
- **Apply order is automatic, never chosen** (`Natives/SKModOrder.{h,m}`, Foundation only). A later mod
  wins a clash, and `contentsOfDirectoryAtPath:` has no defined order, so apply sorts: the mods that write
  the most files first, equal ones by name (ignoring case, then exact), so a small, targeted mod wins over a
  broad one. A mod's weight is the files it writes: no directories, `mod.json`/`mod.png`, protected files or
  paths that leave the root; a modpack is the sum of its top-level inner `.zip` mods; an unreadable mod is 0.
  This is SKradle's "optimal" order (`core::mods::list`) and Android's `ModsOrder.kt`: keep the three in
  step. `SKModOrderTests.m` and Android's `ModsOrderTest.kt` run the same cases.
- **Mods apply by themselves** (`Natives/SKModSync.h` decides, `SKModManager pendingSyncAction`, run by the launcher on
  appearing, on becoming active and after a download; same rule and cases as Android's `ModsSync.kt`). Two
  fingerprints are saved after each apply or reset: the mods folder (name, size, time) and the SHA-1 of the
  game's `digest2.txt` (changes when the game updates and puts its jars back). Either differing means apply;
  no mods left but some applied means restore once. The code jars are deliberately not fingerprinted: a private-server
  choice rewrites `config.jar` after each apply. Reset Game Files saves the current fingerprints, so the folder stays
  unapplied until it changes. A failed state is reported once per fingerprint.
- **The game's cursor is the game's own art.** SK makes its cursor as a window cursor: `glfwCreateCursor` (RGBA pixels,
  hotspot) and `glfwSetCursor`. The bootstrap's `GLFW.java` shim keeps each image and passes the selected one to native
  (`nativeSetCursor`, registered like the other GLFW natives; no art = nothing drawn). `glfw_ios.m` turns it into a
  `UIImage` and posts `SKGameCursorDidChange`; `GameViewController` draws it, game pixels scaled to points like the
  game's UI, hotspot on the point `pushCursorAtPoint:` last pushed (touch, trackpad and mouse all feed that point).
  While it shows, a `UIPointerInteraction` hides the system pointer. Android does the same through
  `NativeBridge.onCursorImage` and `GameActivity`. The setting is off by default (`SKShowMouseCursor`).
- **A typed character is key press, char, key release** (`SKKeyboardBridge.m`, `SKGlfwKeys.h`). The game's char
  callback only calls `keyPressed(char, keyCode -1)`, and the game releases only real key codes, so a character alone
  is a press that never ends: the text shows but live searches and form checks wait for the next real key
  transition (Enter, Backspace). A desktop keyboard sends the key press, the char, then the key release; the bridge
  does too, with the US-layout key for the character (text with no key, such as accents and emoji, goes as the
  char only). Same rule and cases as Android's `GlfwKeys.kt`.
- **Apply fails closed:** if a jar cannot be rebuilt or swapped, the code jars stay as the
  restored originals and the user gets the error. Apply and remove run under a background
  task (about 30 s of grace if the app is backgrounded).
- A missing digest ("No digest for…", error code 8 in `SKModManagerDomain`) means the game
  was never launched; it is shown to the user, not reported.

### Crash reporting and news — `Natives/SKReporter.m`, `Natives/SKNewsFeed.m`

- **No Sentry SDK.** Its crash handler installs Mach exception and signal handlers that
  HotSpot needs for implicit null checks, and it declines to report under a debugger, which
  every JIT run has. `SKReporter` POSTs an envelope itself; the real signal is the JVM's
  `hs_err`, sent on the next launch with a scrubbed log tail.
- **Report only failures, not user-fixable states** (JIT wait cancelled, game not yet
  launched). They are shown as alerts.
- **The news service is plain HTTP**, so its payload is untrusted: image and link URLs are
  dropped unless HTTPS, the body and the decoded image are size-capped, a response is cached
  only if it parses, and `machineId` is a constant, not a device identifier. ATS allows
  cleartext for `flamingo.knightlauncher.com` only.

### Built-in JIT — `Natives/SKBuiltinJIT.m`, `Natives/JITHelper/`

A process cannot debug itself, so the `SKJITHelper.appex` extension links StikJIT and
attaches to the app's pid over the device's debug tunnel (LocalDevVPN + a pairing file),
running `skapsule-jit.js` passed inline. The app starts it through the private
`NSExtension` API (`com.apple.ar.viewer` extension point, the same route pziOS uses). Its
debugger attaches like StikDebug's, so readiness is still `isJITEnabled()`. The StikDebug
path passes the script inline too (`script-data`, base64url).

- Built twice, kept in step: `METHOD_STAGE_JITHELPER` (plain `swiftc`) for `make
  package`, the `SKJITHelper` target in `project.yml` for Xcode.
- `StikJIT.framework` sits in the **app's** `Frameworks/`, not the extension's: `ldid`
  cannot sign a framework nested in an extension in an app. Only the extension links it, so
  the app never loads it below iOS 17.4.
- StikJIT's `project.yml` declares no `Info.plist`; `build-stikjit-ios.sh` writes one,
  because installd rejects a framework without it.
- `xcode-payload` must not empty `Frameworks/`: Xcode has embedded StikJIT there by then.
- `codesign --verify` cannot check this bundle (macOS reports `ldid`'s iOS signatures as
  "not signed at all"); re-signing with zsign is the check that means something.
- CI needs `xcodegen` to build StikJIT.
- **StikJIT is built from a patched copy** (`scripts/patches/stikjit-high-address.patch`, from
  a community fix; the submodule stays at the upstream commit). Upstream writes page addresses
  as nine hex digits, which truncates any JIT mapping above 0xfffffffff (reported on iPads).
- **On iOS 26+ the helper reads the device's RemotePairing port** from its `_remotepairing._tcp`
  Bonjour service (`RSDPortResolver.swift`): the device picks the port at boot, so StikJIT's
  fixed 49152 can be closed. Needs `NSBonjourServices` in the helper and the app's Info.plist
  plus the Local Network permission.
- **Before a request, the route to 10.7.0.1 must leave by a VPN interface** (an unsent UDP
  connect, `SKBuiltinJIT.m`); otherwise the helper can only time out. When it does not, the app
  opens LocalDevVPN (`localdevvpn://enable?scheme=skapsule`; the `skapsule` URL scheme and the
  `localdevvpn` query scheme are in Info.plist), waits for the app to leave and return, polls up to
  10 s for the tunnel to route, then continues; 2 minutes without a return gives up. Failures get advice from
  `SKJITAdvice.h` (pairing replaced, another VPN, LocalDevVPN off, cellular-only), covered by
  `make test`. Cellular data alone breaks LocalDevVPN's loopback.
- **On-device pairing (iOS 27+)** (`SKJITPairing.m`, `Natives/RPPairing`, C interface
  `SKRPPairing.h`): iOS 27 lists `_remotepairing-pairable-host._tcp` services under Developer Mode
  and asks for a PIN the "computer" shows. The Rust library (idevice's `PairableHost`) listens
  and runs the pairing; the app publishes the Bonjour service through `dns_sd` (Local Network
  permission only), shows the PIN (alert, notification, continued-task subtitle) and saves the
  pairing file through `SKBuiltinJIT savePairingData:`. The user is in Settings meanwhile, so a
  `BGContinuedProcessingTask` (`<bundle id>.pairing.*` in `BGTaskSchedulerPermittedIdentifiers`;
  the Makefile rewrites the prefix) keeps the app alive; a sideloader that renames the bundle
  leaves the plist stale and iOS refuses it, leaving the ~30 s grace period. Every pairing makes a
  new key under the same identifier, so only the newest pairing file works. A pairing stops after
  5 minutes. Notices of the Rust crates ship as `legal/LICENSES-rppairing-crates.txt`.
- **JIT Setup is a bottom sheet** (`SKJITSetupViewController`): a navigation controller in a
  medium/large sheet. The root lists the ways; each pushes a page (pair, import, LocalDevVPN, enable,
  StikDebug, TrollStore, jailbreak). Pages rebuild from state on every change (pairing notifications,
  a 1 s `isJITEnabled` poll), so there is no per-view bookkeeping. TrollStore and jailbreak exist only
  where `canGrantOwnJIT` (before iOS 26): from the TXM on, a debugger must stay and answer the VM.
  TrollStore asks `apple-magnifier://enable-jit`; a jailbreak is detected by `/var/jb` and by the
  process already being debugged at launch (`noteLaunchState`, read in `main` before anything attaches).
- **The pairing continued task must be registered for the concrete identifier it submits**
  (`<bundle id>.pairing.session`; `.pairing.*` is only what Info.plist permits): submitting an
  identifier nothing registered raises, which crashed the first on-device pairing. The task also has
  to report progress or iOS ends it.
- **Method is Automatic by default** (StikDebug app if installed, else built-in), never switched
  after a failure.
- **StikJIT is pinned at upstream 2.0 (`a9ccad9`)**, which has its own `_remotepairing._tcp` port discovery
  (`automaticallyDiscoverRSDPort`, on only when the port is the default 49152). Ours (`RSDPortResolver.swift`) still
  passes the port it found, so upstream's never runs; keep it unless upstream's proves better on a device. Its
  script rule is unchanged: on a TXM device our inline script runs, without one it attaches only. The patch applied
  cleanly and the framework and helper build; none of it has run on a device.
- None of the patch, port lookup, advice or on-device pairing has run on a device yet.

**The JIT badge has one blind spot.** `isJITEnabled` on a TXM device checks `CS_DEBUGGED`
plus `getppid() != 1` (`utils.m`): it sees that *a* debugger is attached, not that it runs
`skapsule-jit.js`. A debugger without the script (an old StikDebug ignoring the inline
script) turns the pill green and the launch proceeds into `brk #0x69` with nobody to service
it: the process dies instantly, with no `hs_err`, a 0-byte vmlog, and a log that stops after
`[JIT26] Requesting N MB for JIT mapping`. There is no reliable in-process check, so the gate
is unchanged. `skInstallJITTrapGuard` (a SIGTRAP handler for the exact `brk #0x69` word, which a
servicing debugger never lets reach it) skips the instruction with x0 = 0, logs it and lets the
game screen say why; HotSpot then falls back to a plain `mmap`, which TXM refuses (how the VM fails
after that is unverified on a device). The next launch also detects it (`SKPreviousRunDiedOnJITTrap`: that request line
without the following `[JIT26] mapping at RW=…, RX=…`) and says so in an alert.

`assets/skapsule-jit.js` sets `detachAfterFirstBr = true`, so the script services exactly one
trap. A second executable reservation later in a session would hit the same dead trap;
that is why the code cache must stay large enough (`-XX:ReservedCodeCacheSize`) that HotSpot
never needs one.

### Graphics pass — `external/skgfx/mobile/skgfx.c`

The FPS counter, sharpening (CAS) and Sharp HUD, ported from KnightLauncherPlus's `skgfx`. **`skgfx.c` and
`skgfx.h` come from the `external/skgfx` submodule (single source: SKonstruct/skgfx, MIT), shared with SKapsule
(Android):** change them in that repo and bump the pointer here. `Natives/CMakeLists.txt` and `project.yml` (then
`xcodegen generate`) point at `external/skgfx/mobile`. The decisions and
settings are in `SKGfxSettings.h` (Android: `GfxSettings.kt`), tested by `make test`.

- **Redirect:** gl4es maps the game's framebuffer 0 to `glstate->fbo.mainfbo_fbo`. The gl4es fork exports
  `gl4es_skgfx_set_main_framebuffer()` and a hook table (`gl4es_skgfx_hooks`: ortho, draw, viewport,
  scissor, blendfunc), all NULL unless set. The game draws into our scene target; `skgfx_present(gFramebuffer, …)`
  puts it on the window (CAS when asked) just before `presentRenderbuffer`. These patches are ours only: do not
  offer them upstream. **A device's `out/gl4es` must be rebuilt (`scripts/build-gl4es-ios.sh`) to carry them:**
  with the old library the pass logs "no graphics hooks" and stays off. The dylib exports only `gl4es_`-prefixed
  entry points, so the module looks those up first.
- **Offscreen path** is on when sharpening > 0 or (Sharp HUD and scale < 1); otherwise the layer is
  `contentsScale`-scaled as before. On it the layer stays native-sized and the pass scales.
- **What the game believes its size is** (`skgfx_believed_size`; `SKGfxGameSize`, which also scales touches): the
  scene size, or with Sharp HUD the full drawable (the game lays out and rasterises text at full size; its viewport
  and scissor are scaled down for the scene). Changes reach the game as a framebuffer-size event
  (`push_size_if_changed` in `glfw_ios.m`), so they apply live.
- **GL discipline:** anything gl4es tracks changes through its own entry points; everything else is saved and
  restored exactly. `apply_pending_resize` rebinds framebuffers behind gl4es's back, so `skgfx_after_swap`
  re-asserts the game's framebuffer every frame. No GL text: the counter is a `UIView`. Fails open.
- **Sharp HUD start** is the first full-window `glOrtho` after 20 depth-tested draws (as KLP). Not supported: MSAA on
  the layer, a game screenshot taken while the HUD is drawn.
- **Verified** (iOS 27.0 simulator, login screen): counter shows and hides; sharpening engages with the scene at
  60% inside the native drawable; Sharp HUD starts after 25 draws with a crisp, smaller HUD over a soft scene;
  leaving and re-entering the app keeps all of it. **Sim-only / not measured:** real-device fps and GPU time
  (`SKGFX_TIME=1` in the environment logs the pass's GPU ms every 120 frames; the simulator's ~4 fps says nothing),
  thermals, in-world Sharp HUD (needs a login), a device run at all. The simulator's login scene shows opaque
  black shards with or without this pass (same with the pre-merge gl4es), so that is the simulator, not a regression.

### JVM flags — `Natives/JavaLauncher.m`

Checked against KnightLauncher's "Load recommended settings" (G1, `-XX:+DisableExplicitGC`, 2048 MB on
a desktop). We keep **SerialGC**, not G1: G1 crashed this JRE entering Haven (SIGSEGV in
`G1CodeRootSetHashTable::bulk_remove`, only reachable under G1). `-XX:+DisableExplicitGC` and
`-XX:SoftRefLRUPolicyMSPerMB=10` match KnightLauncher; the first matters more here, because an explicit
`System.gc()` under SerialGC is a full stop-the-world collection. The heap cap defaults to **1024 MB**
(`SK_RAM_DEFAULT_MB`), with `-Xms128M`: it is a ceiling, not a commitment. Android's JVM picks G1 by
ergonomics (`gc.log` says `Using G1`), so there the same recommendation holds with no flag.

### gl4es

- **`gl4es_glDetachShader`'s `if(glprogram->linked) return;` early-out is load-bearing**
  despite being spec-incorrect. gl4es keeps raw `shader_t*` in `last_vert`/`last_frag` and
  never clears them, so a real detach frees a shader the program still reads. Fix
  `last_vert`/`last_frag` and `glprogram->attach[]` first if this is ever revisited.
- **`kh_foreach`'s second parameter is the key, not the bucket index.** Never pass it to
  `kh_del`. Using it that way (`clear_program`, fixed) freed each `uniform_t` while its
  bucket stayed live, and `fill_program`'s sampler-init loop then wrote through freed memory:
  the arbitrary-offset heap write behind every libmalloc "corruption of free block" abort.
  It hid for so long because upstream never *read* the stale pointer; a leak fix that did
  gave AddressSanitizer something to catch.
- **Do not use `malloc_zone_check` on iOS 27**: the xzone allocator makes it blind.
- **ES3 core capabilities** (`npot`, `elementuint`, `depthtex`, `rgtex`) are forced on ES3
  contexts alongside the renderbuffer formats. They change codegen and sampling paths, so
  bisect here first if new visual artifacts appear; `LIBGL_NOES3CORE=1` disables the block.
  `GetHardwareExtensions()` matched ES2-era `OES` names, but on ES3 `packed_depth_stencil`,
  `depth24` and `rgb8_rgba8` are core and never advertised, which split
  `GL_DEPTH24_STENCIL8` (rejected by Apple GPUs); they are now probed from `GL_VERSION`.

---

## Diagnostics

### AddressSanitizer

```sh
SK_ASAN=1 ./scripts/build-gl4es-ios.sh    # + uncomment OTHER_LDFLAGS in project.yml
```

`scripts/stage-app-assets.sh` copies the runtime into `Frameworks/` when gl4es carries the
dependency. Reports reach `latestlog.txt` via the stdio tee. Three prerequisites:

- **The app must link the runtime**, not the dlopen'd gl4es: arriving late aborts with
  *"Interceptors are not working"*. `project.yml` links it into `SKapsule.debug.dylib`,
  which dyld loads before `main()`. Linker flag only; app code stays uninstrumented.
- **Nothing may call `malloc_zone_check`**: ASan leaves that zone callback unimplemented
  and aborts with *"CHECK failed: sanitizer_malloc_mac.inc"*.
- Options come from `__asan_default_options()` in `Natives/main.m`, since `ASAN_OPTIONS`
  cannot be set for a sideloaded app. Signal handling is left to the JVM.

Expect ~2-3x slower. Diagnostic only.

### Java preferences

Seeded on first launch by `init_seedGamePrefs` (`Natives/main.m`), matching Android's
`PrefsInstaller`: `anonymous_logon=false`, `compatibility_mode=true`,
`cull_transients_prod=true`, `render_quality=LOW`. Written only when absent.

The file lands at `home/.userPrefs/.java/.userPrefs/projectx/prefs.xml` (the JDK's
`FileSystemPreferences` appends `.java/.userPrefs` itself). Every component is a dotfile,
which is why `home/` **looks** empty in Files.app; it is visible over USB in Finder.

### Simulator

`make sim-run` builds, installs and runs the app in the iOS Simulator with no device, signing
profile or JIT helper (`scripts/sim/`, after Wintur's `docs/SIM-LOOP.md`). It uses its own `build/sim`
and `out/sim`; no device target is involved.

- **`build-libs.sh`** rebuilds gl4es, openal-soft and the pairing library against the
  iphonesimulator SDK with the device scripts themselves (`SDKPATH`, `OUT_DIR`, `RP_TARGET`
  overrides) into `out/sim`.
- **`build.sh`** compiles the app with CMake for the simulator, stages the JRE from the assets zip into
  `out/sim/jre25` with the same layout and trimming as `METHOD_STAGE_JRE` (**keep the two in step**),
  and stages the device build's jars. The JRE and the LWJGL natives are the device builds with only
  their Mach-O platform retagged (`vtool -set-build-version iossim`): the arm64 code is the same and
  dyld in a simulator refuses an iOS-platform image. Everything is signed ad hoc, with no entitlements;
  there is no `SKJITHelper.appex` and no StikJIT. It puts `Natives/config.h` back afterwards (CMake
  writes it into the source tree, where Xcode also reads it).
- **`run.sh`** boots `SK_SIM_DEVICE` (default iPhone 18 Pro Max), installs over the existing app (the
  downloaded game survives; `--fresh` forgets it), launches, taps Launch with idb (`idb_companion`
  required) and waits for `[NativeBridge] renderReady`. `build/sim/runs/<time>/` gets the screenshots
  (`launcher.png`, `game.png`), `latestlog.txt`, `vmlog-*.log`, any `hs_err`/crash report and a summary.
  Exit 0 means: launcher UI up, game rendered, no crash.

**Verified** (iPhone 18 Pro Max, iOS 27.0, from a fresh install): the launcher UI, the JIT JRE booting,
getdown downloading the game, and the logon window rendering through gl4es. The VM creates its mirror-mapped
code cache in-process (`[JIT26] mapping at RW=…, RX=…`) and the code cache fills (3 to 8 MB in use), so
HotSpot compiles: the macOS kernel grants executable memory with no debugger and no `brk #0x69`.

**Sim-only** (what passes only because of an accommodation; `TARGET_OS_SIMULATOR` in `utils.m`, compiled
out of the device build):

- `DeviceGetJITFlags()` is 0, so `DeviceHasTXM()` (which libjvm `dlsym`s) says no TXM and no mirrored
  mapping; `isJITEnabled()` is YES, so the pill is green and a launch never waits for a debugger.
- The JRE and LWJGL natives are retagged device builds, not rebuilt. GL ES is Apple's simulator
  implementation, not the device GPU (`default FBO binding: 1`).
- `os_proc_available_memory` is 0 in the `[mem]` lines.
- The log shows `MacContextUpdate install failed` (`NoSuchMethodError` on `GLFW.getLibrary`) from the
  game's Mac-only path; not compared with a device log.

The simulator is a testbed for boot, UI, input and layout. It is **not** one for what depends on the
device: the StikJIT attach, `SKJITHelper.appex`, pairing and LocalDevVPN, the SIGTRAP guard and the
`brk #0x69` path (TXM), jetsam and memory pressure, thermal throttling, Metal/gl4es performance, or Game
Mode. Call a result "sim-only" when it rests on a simulator accommodation. The repo's `.claude/skills/`
carry the simulator-driving skills (`skapsule-simulator` says how they apply here).

### Footguns

- **The `[Pre-Init] Commit:` line goes stale.** `Natives/config.h` is generated by
  `configure_file` but also checked in, and only regenerates when CMake *configures*. Do
  not use it to decide whether a build contains a change; jars and dylibs stage from
  `out/` independently.
- **The deployment target is 17.4 everywhere** (`Makefile`, `project.yml`, the JIT helper):
  the oldest iOS the JIT methods (StikJIT, StikDebug) work on. Raising it drops TrollStore
  installs on iOS 17.0 and older; the TrollStore build is untested either way. Keep the app,
  helper and `apps.json` `minOSVersion` in step.
- **The "SKapsule Heap Diagnostics" scheme does nothing.** Its `MallocScribble` /
  `MallocGuardEdges` only apply when launching from Xcode, and Xcode's debugger cannot
  service the JIT trap.
- **Game Mode not engaging is not proof the keys are wrong.** `LSApplicationCategoryType`
  is what the OS decides from (`LSSupportsGameMode` / `GCSupportsGameMode` only opt in or
  out), and it skips a relaunch that follows too soon after the last quit; allow ~5 minutes
  between test launches. It never engages in the simulator.

---

## Known gaps

- iOS has no hardware-key auto-repeat (UIKit does not repeat `UIPress`; needs a timer keyed
  off `pressesBegan`/`pressesEnded`) and reports no NUM_LOCK bit.
- `glfwGetJoystickHats`/`Name`/`GUID` return null while `glfwJoystickPresent` returns true,
  and only `jid 0` is supported: a second controller is invisible.
- Mouse-button callbacks always report `mods = 0`, so shift/ctrl-click is invisible to SK.
- The input queue drops the *newest* records when full (`glfw_ios.m`), which for keys means
  a lost release and a stuck key. Related: a held button latches if its input source
  disconnects while another source is still active.
- UI: `handleChromeDrag` doesn't clamp, so a gear button dragged off-screen is
  unrecoverable; cancelling the "Waiting for JIT" alert leaves `bootOverlay` with no dismiss
  path.

---

## Touch parity with Android

Ported from `SKapsule/launcher/.../touch/`. **Keep the two in sync**: the layout schema,
default node table and slider ranges are meant to stay comparable, so a change to one
usually belongs in the other.

- `Natives/SKTouchControls.{h,m}`: percent-based node model + `SKTouchLayout`
  (`globalOpacity`, `controlsEnabled`, `actionBarVisible`, `renderScale`, nodes),
  JSON-persisted in `NSUserDefaults`. All 16 Android default nodes including `btn_esc`
  (GLFW 256). `scale`/`renderScale` clamp on load so an older schema can't decode to 0.
- `Natives/SKTouchControlOverlay.{h,m}`: edit mode, per-node visible/scale, opacity and
  resolution sliders, **Show Controls** / **Show Action Bar**, double-tap-confirm Reset.
  Every appearance change re-asserts `sk_gamepad_set_virtual_active(controlsEnabled)`, or a
  latched `Strafe` toggle has no reset path. Right stick presses axis 5 and holds the last
  aim direction 200 ms on release. **Deadzone applies to physical sticks only.**
- `Natives/SKLayoutShare.{h,m}` (Foundation only): the layout **export/import format** and the preset
  store, a port of Android's `touch/TouchLayoutShare.kt` + `TouchLayoutPresets.kt`. An export from either
  app must import on the other, so the two must accept and refuse the same files. The file is
  `{format:"skapsule-controls", version:1 (an integer), name, globalOpacity, actionBarVisible, nodes:[{id,
  xPercent, yPercent, scale, visible, floating?}]}` (`floating`: optional boolean, written only when true,
  joystick-only when applied; a non-boolean refuses the file). Only the arrangement is shared (not `renderScale` or
  `controlsEnabled`), and a file is untrusted: size capped at 64 KB, at most 64 nodes, finite numbers clamped
  to the editor's own ranges, a repeated known id refused, unknown ids ignored, and any structural error
  refuses the whole file. `-[SKTouchLayout applySharedLayout:]` lays the values over the app's own nodes by id,
  so a file can move controls but never change what they send. `Natives/Tests/SKLayoutShareTests.m`
  (`make test`) and Android's `TouchLayoutShareTest.kt` parse the same two fixtures, one written by each app
  (`Natives/Tests/fixtures/`, copied to Android's `src/test/resources/`); keep them identical.
- **Editor pages and floating sticks.** The overlay's tab strip (Edit | Settings; the gear closes the editor, the standalone editor has Done) switches `_page`: Edit shows the selected control's own dialog, docked by
  `SKDockPlacement.h` (fixed at the top right, moved down only to clear the standalone editor's Done button; same rule
  and cases as Android's `DialogDock.kt`), Settings the full panel with controls shown untouchable. A floating stick
  (`SKControlNode.floating`) is a square zone, not a circle, and on by default: the overlay lays its view out as the zone (1.5 stick
  diameters, capped at 62% of the height and 36% of the width) centred on `xPercent`/`yPercent`, kept on screen, and
  sets `stickRadius` for the stick inside it. The view is hit like any control (buttons are added later, so they win), `hitTest:` returns nil for
  anything else so it reaches the game, `touchesBegan:` puts the base (`_base`) under the thumb clamped inside the
  zone, the base follows a thumb dragged past 0.6 of the stick radius (still inside the zone), and release puts it
  back at the middle. The zone is drawn always (rounded square, hairline edge); the stick only under a held thumb,
  a faint ghost otherwise. The editor drags a zone like any control. Android does the same (`TouchJoystickView`). Touch defaults: opacity 100%
  (`SKDefaultOpacity`), Show Buttons on, every button (ESC too) at 0.8 of its base size, positions on a grid in
  `defaultLayout` (identical to Android's `createDefaultLayout`). The chrome row (gear, keyboard, eye) defaults to fixed
  centres on y 0.05 (`kChrome*` in `GameViewController.m`, same as Android's `CHROME_*`; bump the layout version when
  they change), uses the touch buttons' fill and `-[SKTouchControlOverlay effectiveOpacity]`, and drags freely: the
  tap slop applies only until the finger first crosses it (`chromeDragActive`). The FPS pill sits at the top centre.
- **Combat button icons.** `btn_strafe/defend/attack/dodge/shieldbash` draw a vector glyph (`SKGlyphForNode` in
  `SKTouchControlOverlay.m`; path data is absolute M/L/C/Z on a 24-unit grid, parsed by `SKGlyphPath`) instead of
  their label, tinted in the game's HUD colours (attack red `#EB2121`, defend blue `#3B82F6`, dodge cyan `#28D9FF`,
  bash stun-star gold `#FEB200`; strafe stays neutral). Keep the paths and colours identical to Android's
  `ControlGlyphs.kt`. `btn_attack` (right trigger, axis 5, above Defend, at 0.664, 0.431) is added by `loadLayout` to
  layouts saved before it existed; the share fixtures are old exports without it, which still import.
- **The launcher turns.** `LauncherViewController` supports every orientation but upside down; the centre column
  has a portrait and a landscape constraint set (`portraitConstraints` / `landscapeConstraints`) swapped in
  `viewWillLayoutSubviews` by the view's aspect. `refreshOrientation` (from `viewDidAppear:`) asks the scene to
  follow the device again after the landscape-only game controller is dismissed. Open Folder opens the Files app on
  the Documents folder with `shareddocuments://`, and falls back to the folder picker only if that fails.
- `Natives/SKKeyboardBridge.{h,m}`: offscreen `UIKeyInput` first responder.
- **Touch routing differs by necessity.** iOS relies on UIKit hit testing: each control is
  a real subview with its own `UITouch`, and the overlay's `hitTest:` returns nil in the
  gaps so misses reach the GL surface. Android's overlay routes pointers by hand (ViewGroup
  dispatch would give one child the whole gesture). Both ports release every held control on
  layout rebuild, edit-mode toggle and Show-Controls-off, or a button latches.
- `GameViewController.m`: ⚙ / Keyboard chrome buttons (draggable in edit mode, 20 pt slop,
  persisted in `game_chrome_prefs`); the overlay is sized to `surfaceView`, not `self.view`.

---

## History (condensed)

- **JVM boot & staging.** `JavaLauncher.m` boots JRE 25 via `JLI_Launch`; `SKInstaller.m`
  stages jars/assets version-aware. The JRE and natives are codesigned at build time, so
  there is no dyld validation bypass.
- **Panama upcall stubs crash the JIT JVM.** The stub's blob header is written through the
  RX alias instead of the RW mirror of the code cache, so **any** upcall stub dies with
  SIGBUS `BUS_ADRALN` in `CodeBlob::CodeBlob` ← `UpcallStub::create`. Fixes:
  - LWJGL `Callback` classes: SK's GLFW is fully shadowed, so `sk-bootstrap.jar` shadows
    the `GLFW*Callback` classes. `assets/shadow/org/lwjgl/openal/SOFTSystemEventProc.java`
    does the same for OpenAL's device-event callback (address 0, so no device events). If a
    new `org.lwjgl.*Callback`/`*Proc` shows up in an `hs_err` under
    `UpcallLinker::make_upcall_stub`, shadow it the same way.
  - `sun.font.HBShaper` (JDK, cannot be shadowed): `-Dsun.font.layout.ffm=false`
    (`JavaLauncher.m`) selects the JNI HarfBuzz path. Unverified on device: a Mac test
    cannot run Java2D without the cacio agent.
- **Rendering.** `CAEAGLLayer`-backed `EAGLContext` with color + depth/stencil
  renderbuffers. gl4es fixes along the way: FBO 0 handling, a `glGetUniformLocation` NULL-name
  crash, `buffers.c` updating all VAOs in `glstate->vaos` rather than the active one, plus
  the heap corruption and ES3 formats described under *gl4es*.
- **Fonts (cacio).** `SunFontManager` only auto-registers the JRE font directory on Linux,
  so iOS needed a forced `registerFontDir()`, a hand-built `fonts.dir` XLFD mapping and a
  null-safe `findFont2D` fallback.
- **AWT / Java2D.** `awt_stubs.c` replaces `libawt_headless.dylib`; its exported symbol set
  had to be exact: over-stubbing shadowed real rendering-loop registration, under-stubbing
  produced `UnsatisfiedLinkError` on platform-backend `initIDs`.
- **Steam login.** frenchpress starts a QR sign-in that the user approves in the Steam mobile app, or,
  when they tap **Use username and password** (no second device), `SteamSession.signInWithPassword`
  collects credentials before connecting and signs in with `beginAuthSessionViaCredentials`; its
  authenticator always asks for a typed Steam Guard code. The password lives in memory only (`SKNativeBridge`
  hands it over once); only the refresh token is stored. Switching QR/form is a flag
  (`nativeSignInPasswordRequested`), separate from cancel (which means web account). Four more natives
  (`nativeShowSignInForm`, `nativeSignInPasswordRequested`, `nativeTakeSignInCredentials`,
  `nativeTakeSignInGuardCode`) are looked up one by one by `NativeBridgePrompt`, so QR works without them.
  Untested on a device: a real credentials/Guard login. The JVM talks
  to the UI through the `SkBootstrap` natives (`JavaLauncher.m`, `NativeBridge.m`). The sign-in runs
  first, in `SkBootstrap.signInToSteam`, before the updater and the game: it uses a loader of its own,
  stores the token and disconnects, and the game's frenchpress then signs in from the token. It is
  skipped when a token file exists, and a cancel sets `frenchpress.signInDeclined` so the game does not
  ask again. That sign-in is shown in portrait: `GameViewController` reports portrait while
  `signInInPortrait` is set (Steam, no token file), and the hide handler, which SkBootstrap fires once
  more when the phase is over, turns the screen landscape. The JVM is always given landscape
  dimensions, and the drawable is resized after the turn (rebuilt on the main thread while the render
  thread has not yet taken the context, else by the render thread). The natives:
  `nativeShowSignIn(url, modules)` and `nativeHideSignIn()` never block (the QR is drawn by
  `GameViewController` from the module grid, updated in place when Steam rotates the challenge), and
  `nativeSignInCancelled()` is polled by the JVM, so a Cancel needs no parked thread. A sign-in with no
  handler registered reports itself cancelled rather than waiting. A background task is held while the
  QR is up, because the Steam app takes the foreground; it lasts seconds, so frenchpress restarts the
  challenge if the connection dies. **Open Steam app** opens the challenge URL as a universal link
  (`UniversalLinksOnly`), which fails visibly instead of opening a web page. Untested on a device: that
  the Steam app accepts the link, and that a sign-in survives the app switch.
- **Input bridge.** Touch, on-screen controls, gamepad and keyboard/mouse all feed two shared
  native structures, a 4-int-record event ring buffer and a GLFW standard-layout gamepad
  mailbox, so SK never knows which producer it is hearing. Wire protocol is in
  `external/bootstrap/.../GLFW.java`; trigger axes rest at **−1**, not 0.

---

## Build & verification

```sh
make native                      # CMake build of the native app (builds the Rust pairing lib if missing)
make test                        # host-side tests (zip parsing, mouse buttons)
./scripts/build-gl4es-ios.sh     # -> out/gl4es/libgl4es.dylib
make package                     # -> .ipa in out/artifacts/
make sim-run                     # build + run in the iOS Simulator (scripts/sim/; SIM_ARGS=--fresh|--launcher-only)
```

Deploy to device via Xcode; the post-build phase re-runs `make xcode-payload`. Adding a
source file under `Natives/` needs `xcodegen generate`: `project.yml` globs the directory,
but `SKapsule.xcodeproj` is checked in and no build step regenerates it, so a missing run
shows up as `Undefined symbol: _OBJC_CLASS_$_…` long after `make native` passed.
