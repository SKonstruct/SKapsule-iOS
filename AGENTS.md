# AGENTS.md

Instructions for AI coding agents working in this repo. The goal is for
agent-authored changes to be indistinguishable in style and scope from
human-authored ones.

If a request conflicts with anything below, **stop and ask** rather than guess.

---

## What this project is

SKapsule-iOS is an unofficial iOS (arm64) port of _Spiral Knights_. It is the
iOS counterpart of [SKapsule](https://github.com/SKonstruct/SKapsule) (Android).
The iOS app boots a bundled JRE 25 that runs the real desktop game client, with
native shims (gl4es, openal-soft, LWJGL, caciocavallo, frenchpress) supplying
what the desktop client expects from its host platform. Game code and assets are
downloaded at runtime via getdown, exactly like the desktop client.

The buildable project is the repo root — the `Makefile` drives `CMake` to build
the `Natives/` Objective-C app, then assembles the `.app` bundle and packages
the `.ipa`. Native-component submodules live in `external/`; build scripts
live in `scripts/`.

### Sister projects (reference only)

- **[SKapsule](https://github.com/SKonstruct/SKapsule)** — the Android version.
  Architecture reference for the bootstrap, JVM launch, input/GL bridges, and
  Steam login. Most Java code (external/bootstrap/) is shared.
- **[Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS)** — an iOS
  Minecraft launcher that informed the JVM-on-iOS approach (JIT enablement,
  cacio bridge, Makefile+CMake build system).

---

## Repository layout

```
Makefile               top-level build driver (native → payload → package)
CHANGELOG.md           release notes source (see Releasing)
Natives/               iOS app (Objective-C) + CMake build
  CMakeLists.txt       CMake project
  main.m               app entry point (JIT, home dir, stdio redirect)
  AppDelegate.*        UIApplicationDelegate
  SceneDelegate.*      UISceneDelegate (iOS 13+)
  LauncherViewController.*  launcher home screen (Play Web / Play Steam)
  GameViewController.*      game surface + JVM host
  JavaLauncher.*       JVM bootstrap (dlopen libjli, JLI_Launch)
  SKTouchControls.*    touch-control node model + persisted layout
  SKTouchControlOverlay.*   touch-control overlay, edit mode, settings panel
  SKKeyboardBridge.*   offscreen UIKeyInput -> GLFW char/key events
  SKInstaller.*        runtime extraction + installation check
  SKZipUtils.*         zip read/write (central directory), git blob SHA
  SKModManager.*       modpack download, apply and remove
  SKNewsFeed.*         home-screen news card feed (KnightLauncher's Flamingo service)
  SKReporter.*         Sentry failure/crash reports, log scrubbing
  glfw_ios.m           GLFW natives for the JVM: input queue, buffer swap, gamepad
  NativeBridge.*       JVM ↔ UI bridge (boot status, Steam Guard prompts)
  utils.*              JIT detection, entitlements, file helpers
  SKBuiltinJIT.*       JIT method choice, pairing file, starts the JIT helper extension
  JITHelper/           Swift app extension linking StikJIT (attaches the JIT debugger)
  awt_xawt/            cacio AWT stubs
  Info.plist           iOS app metadata
  Assets.xcassets/     app icon, Buy Me a Coffee image
external/bootstrap/    Java bootstrap module (shared with Android)
  SkBootstrap.java     runs HeadlessGetdown → launches ProjectXApp
  HeadlessGetdown.java headless getdown driver
  NativeBridgePrompt.java   frenchpress credential prompt
  GLFW.java            GLFW shim routing to native implementations
scripts/               build-*-ios.sh per native component + stage-app-assets.sh
assets/                bundled JRE zip, fonts, JIT script, iOS-only shadow classes
external/gl4es/        submodule — GL → GLES translation
external/openal-soft/  submodule — audio
external/lwjgl3/       submodule — LWJGL iOS build
external/caciocavallo17/  submodule — headless AWT
external/frenchpress/  submodule — Steam login
external/StikJIT/      submodule — built-in JIT framework (MPL-2.0), unmodified
entitlements.*.xml     signing entitlements (sideload / TrollStore)
out/                   native build outputs (generated, gitignored)
out/artifacts/         packaged IPA output (generated, gitignored)
```

---

## Build & verification

- **Everything:** `./scripts/build.sh [debug|release|trollstore] [--natives] [--test] [--deploy]` builds missing natives and the jars, then the app (`--help`).
- **Native app (CMake):** `make native` (requires Xcode CLI tools + iOS SDK)
- **Host-side tests:** `make test` builds `Natives/Tests/` for the Mac and runs it (zip parsing, git blob SHA). Add a case there when touching `SKZipUtils`. The **Test** workflow runs it on every push and pull request.
- **Full package:** `make package` (produces `.ipa` in `out/artifacts/`)
- **TrollStore:** `make package TROLLSTORE_JIT_ENT=1` (produces `.tipa`)
- **Release:** `make all RELEASE=1`
- **Xcode IDE Build:** The user builds and tests on-device via Xcode. **CRITICAL**: The Xcode build uses `make xcode-payload` as a post-build step. Any new stub dylibs or source files must be available through this pathway. Both the CMake and Xcode pipelines must be kept functional.
- **Native submodules:** rebuild via the matching script in `scripts/`.
    - `build-gl4es-ios.sh` — needs iOS SDK
    - `build-openal-ios.sh` — needs iOS SDK
    - `build-lwjgl3-ios.sh` — needs JDK 25 + iOS SDK + ant
    - `build-cacio-ios.sh` — needs JDK 25 + Maven
    - `build-frenchpress-ios.sh` — needs JDK 25 + Maven

If you cannot run the build, say so. Do not claim a change is verified when it isn't. Always run `make native` after changes to verify compilation.

### Releasing

1. Rename `## Unreleased` in `CHANGELOG.md` to `## <version>` (no `v`) and merge that.
2. Actions → **Release iOS** → Run workflow, with the version. It builds `SKapsule.ipa` and
   `SKapsule-TrollStore.tipa` from `main` and, only if that succeeds, creates the `v<version>`
   tag and the release, with that changelog section followed by GitHub's generated notes.
   Never push the tag yourself: a failed build leaves nothing behind, so just run it again.
3. List it in the AltStore / SideStore source, [SirDank/sources](https://github.com/SirDank/sources):
   download the released `SKapsule.ipa`, run `./update.sh <ipa> <download URL>` there, and
   commit `apps.json` by hand. Use the released file, not a local build: the source records its
   size and sha256, and a mismatch makes stores refuse the install.

Nothing commits automatically. `apps.json`'s `appPermissions.entitlements` must list every
entitlement in the IPA's signature (stores check it), so update it when entitlements change.

### On-device runs need JIT

The bundled JRE is the AngelAuraMC JDK-25 **JIT** build, not the Zero interpreter. On
A17+/iOS 26 the Trusted Execution Monitor enforces W^X, so the VM traps (`brk #0x69`) for
an attached debugger to map its code pages. That debugger is attached by the built-in
helper (StikJIT) or the StikDebug app, both running `assets/skapsule-jit.js` passed inline —
see [README.md](README.md). Consequences when debugging:

- **Xcode's debugger cannot service the JIT trap.** A run started from Xcode dies at
  `BreakGetJITMapping`; ask for a launch from the home screen with JIT instead.
- Console output is unavailable in that case. Logs come from **Share Logs**:
  `latestlog.txt`, `hs_err_pid*.log` and `vmlog-*.log` in `SKAPSULE_HOME`.
- `gl4es` is a fork we patch (`external/gl4es`, SKonstruct/gl4es), so a rendering fix may
  belong there rather than in `Natives/`. Rebuild with `scripts/build-gl4es-ios.sh`.
- **When a fix lands in a jar or dylib rather than Objective-C, confirm the running build
  actually contains it before diagnosing further.** Those are staged from `out/` and are
  independent of the app's compiled-in commit stamp, which has been seen to go stale.

---

## Keep the docs current, and short

`ROADMAP.md`, `README.md` and `CHANGELOG.md` are maintained as part of the change, not
afterwards. Every change that alters behaviour, adds an invariant, or resolves an
investigation updates them **in the same pass**.

- **Write conclusions, not narratives.** A resolved bug is its root cause, the fix, and any
  rule it established — not the sequence of hypotheses that got there. Git history keeps
  the blow-by-blow.
- **Delete as you add.** When something is fixed, remove the open-question text it
  replaces; do not leave both. Contradictory sections are worse than no section.
- **ROADMAP.md is for what is still load-bearing:** invariants that prevent regressions,
  open gaps, live diagnostics, and a short condensed history. If a section no longer
  changes anyone's decisions, cut it.
- **README.md is end-user facing.** Install, JIT setup, troubleshooting, build. No internals.
- **CHANGELOG.md gets every user-visible change** under `## Unreleased`, in Added / Changed /
  Fixed. It becomes the release notes, so write it for players.

---

## Scope discipline

- **One PR = one logical change.**
- **Don't bundle drive-by cleanups** into a feature/fix PR.
- **Don't refactor opportunistically.**
- **Don't add features or abstractions that weren't asked for.**
- **Don't write new files when an existing one will do.**

When in doubt about scope, smaller is better.

---

## Commit & PR conventions

**Format:** [Conventional Commits](https://www.conventionalcommits.org/),
lowercase type, lowercase subject, no trailing period, no emoji:

```
feat: add initial launcher UI
fix: resolve JRE path lookup on sideloaded installs
chore: bump gl4es submodule
```

Common types: `feat`, `fix`, `perf`, `chore`, `test`, `docs`.

---

## Code style

### Objective-C (Natives/)

- Match the surrounding file. Indentation, brace placement, import order.
- **Comments: write fewer.** Only comment the _why_ when non-obvious.
- No `TODO(agent):` or agent-attribution markers.
- Don't reformat code you aren't changing.

### Java (external/bootstrap/)

- This code is shared with SKapsule (Android). Changes here may need to be
  synced upstream. Keep it platform-independent.

### Build scripts (scripts/, Makefile)

- Keep them readable and reproducible. CI must run them unattended.
- Don't add interactive prompts.

---

## Things to never do without asking

- Force-push or rewrite shared history.
- Push to `main`. All work goes through PRs.
- Modify `.github/workflows/`, signing config, or entitlement files.
- Update submodule pointers as a side effect of an unrelated change.
- Add new top-level files or directories.
- Introduce new third-party dependencies.
- Commit secrets or signing certificates.
- **Attempt to bypass Cacio.** Cacio is strictly required on iOS; without it, the JVM falls back to the macOS AWT stack, which will crash.
- **Change the touch-control layout, defaults or settings without checking SKapsule.**
  `Natives/SKTouchControls.*` and `SKTouchControlOverlay.*` are a port of the Android
  port's `touch/` package and are meant to stay comparable; a change to one usually
  belongs in the other.
- **Add new source files to Xcode without updating `project.yml` and re-running
  `xcodegen generate`.** The Xcode project is generated by XcodeGen but `SKapsule.xcodeproj`
  is *also checked in*, and no build step regenerates it. `project.yml` globs `Natives/`, so
  a new file there needs no yml edit — but the committed project won't see it until
  `xcodegen generate` is run, and the failure is a link error (`Undefined symbol:
  _OBJC_CLASS_$_...`) long after `make native` has passed.

---

## When you're unsure

Ask. A short clarifying question is always cheaper than a wrong-direction change.
