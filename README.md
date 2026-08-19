# SKapsule-iOS

Spiral Knights on iOS/iPadOS — an iOS launcher that runs the real Spiral Knights
desktop client on-device: a bundled JRE 25, the game's OpenGL renderer translated to
OpenGL ES through [gl4es](https://github.com/SKonstruct/gl4es), OpenAL audio, touch and
gamepad controls, and Web or Steam login (including Steam Guard).

## Requirements

- iPhone or iPad, **iOS/iPadOS 17.4+** (developed against iOS 26).
- A sideloading method that grants the `get-task-allow` entitlement — Xcode, AltStore,
  SideStore or TrollStore.
- **[StikDebug / StikJIT](https://github.com/StephenDev0/StikJIT)** with a paired device.
  **JIT is mandatory.** Without it the JVM falls back to its interpreter and the game is
  far too slow to play.
- ~1.5 GB free (the client downloads ~440 MB of game data on first launch).

## Enabling JIT

Spiral Knights runs on a JIT-enabled JVM. On A17/M-series devices running iOS 26 the
hardware Trusted Execution Monitor enforces W^X, so the JVM cannot make its own
executable pages. Instead it traps (`brk #0x69`) and asks an attached debugger to map
them, which is what `UniversalJIT26.js` does. That script has to be registered with
StikDebug once.

### One-time setup

1. Install and launch SKapsule once. On startup it writes `UniversalJIT26.js` into its
   own Documents folder, so the file appears in **Files → On My iPhone → SKapsule**.
   The launcher's **Open Folder** button takes you straight there.
2. In StikDebug/StikJIT, open **Tools** and **import** `UniversalJIT26.js`.
3. Enable advanced options, then **assign the script to SKapsule's bundle id**. This
   step is required: the `stikjit://enable-jit` URL only accepts a bundle id and pid, so
   the script cannot be handed over at launch time — it must already be associated with
   the app.

### Every launch

Open SKapsule and tap the **Enable JIT** pill on the home screen. It hands off to
StikDebug and turns green ("JIT enabled") once the mapping succeeds; the script detaches
itself immediately afterwards so it doesn't interfere with the running game. Then tap
**Launch**. If you tap Launch first, the app requests JIT itself and waits, continuing
automatically as soon as it's granted.

## Building

```sh
make native          # CMake build of the native app
make xcode-payload   # stage the JRE, jars and dylibs into the .app
```

Then build and deploy the generated Xcode project to a device. The Xcode post-build
phase re-runs the staging step, so a normal Run picks up rebuilt jars and dylibs.

Some components are built separately and are consumed from `out/`:

```sh
./scripts/build-gl4es-ios.sh   # -> out/gl4es/libgl4es.dylib
./scripts/build-bootstrap.sh   # -> out/bootstrap/sk-bootstrap.jar
```

Adding a source file under `Natives/` also needs `xcodegen generate`: `project.yml` globs
the directory, but `SKapsule.xcodeproj` is checked in and nothing regenerates it during a
build, so a missed run surfaces as a link error long after `make native` passed.

## Troubleshooting

Use **Share Logs** in the launcher sidebar. It collects everything useful:

| File | Contents |
| --- | --- |
| `latestlog.txt` / `latestlog.old.txt` | Full launcher + JVM + game output for the current and previous run |
| `hs_err_pid*.log` | HotSpot crash report, if the JVM died |
| `vmlog-*.log` | GC, class-unloading and code-cache logging |

The JVM names the last two per-pid, so they never overwrite each other; the launcher prunes
each to the 3 newest at startup. Pruning happens on launch rather than on exit, so a crash
report always survives the relaunch you share it from.

These are captured even when launching outside Xcode, which is the normal case since the
game must be started via StikDebug.

- **"StikJIT not found" when tapping Enable JIT** — StikJIT/StikDebug isn't installed, or
  no device pairing file has been imported into it.
- **The JIT pill never turns green** — the script probably isn't assigned to SKapsule's
  bundle id (step 3 above). StikDebug's own log should show it allocating a JIT page.
- **Game is running but unplayably slow** — it launched without JIT.
- **The HUD is tiny** — Resolution in the ⚙ panel is a framebuffer divisor; lower it and
  relaunch. It applies at launch, not immediately.

## Related projects

- [SKapsule](https://github.com/SKonstruct/SKapsule) — the Android port; shares the
  `bootstrap` and `frenchpress` submodules.
- [KnightLauncher](https://github.com/lucasluqui/KnightLauncher) — the desktop launcher.
- [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) — the iOS Minecraft
  launcher this project borrows its JIT and dyld-bypass techniques from.
