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
the `.ipa`. Native-component submodules live at the repo root; build scripts
live in `scripts/`.

### Sister projects (reference only)

- **[SKapsule](https://github.com/SKonstruct/SKapsule)** — the Android version.
  Architecture reference for the bootstrap, JVM launch, input/GL bridges, and
  Steam login. Most Java code (external/bootstrap/) is shared.
- **[Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS)** — an iOS
  Minecraft launcher that informed the JVM-on-iOS approach (JIT enablement,
  dyld bypass, fishhook, cacio bridge, Makefile+CMake build system).

---

## Repository layout

```
Makefile               top-level build driver (native → payload → package)
Natives/               iOS app (Objective-C) + CMake build
  CMakeLists.txt       CMake project
  main.m               app entry point (JIT, home dir, stdio redirect)
  AppDelegate.*        UIApplicationDelegate
  SceneDelegate.*      UISceneDelegate (iOS 13+)
  LauncherViewController.*  launcher home screen (Play Web / Play Steam)
  GameViewController.*      game surface + JVM host
  JavaLauncher.*       JVM bootstrap (dlopen libjli, JLI_Launch)
  SKInstaller.*        runtime extraction + installation check
  NativeBridge.*       JVM ↔ UI bridge (boot status, Steam Guard prompts)
  utils.*              JIT detection, entitlements, file helpers
  dyld_bypass_validation.m  library validation bypass for unsigned dylibs
  awt_xawt/            cacio AWT stubs
  Info.plist           iOS app metadata
  Assets.xcassets/     app icon + launch screen
  resources/           bundled frameworks, storyboards
external/bootstrap/    Java bootstrap module (shared with Android)
  SkBootstrap.java     runs HeadlessGetdown → launches ProjectXApp
  HeadlessGetdown.java headless getdown driver
  NativeBridgePrompt.java   frenchpress credential prompt
  GLFW.java            GLFW shim routing to native implementations
scripts/               build-*-ios.sh per native component + stage-app-assets.sh
gl4es/                 submodule — GL → GLES translation
openal-soft/           submodule — audio
lwjgl3/                submodule — LWJGL iOS build
caciocavallo17/        submodule — headless AWT
frenchpress/           submodule — Steam login
fishhook/              submodule — runtime function hooking
entitlements.*.xml     signing entitlements (sideload / TrollStore)
out/                   native build outputs (generated, gitignored)
out/artifacts/         packaged IPA output (generated, gitignored)
```

---

## Build & verification

- **Native app (CMake):** `make native` (requires Xcode CLI tools + iOS SDK)
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
- **Add new source files to Xcode without updating `project.yml`.** The Xcode project is generated by XcodeGen. Ensure you update `project.yml` if you introduce files that need to be compiled by the Xcode target directly.

---

## When you're unsure

Ask. A short clarifying question is always cheaper than a wrong-direction change.
