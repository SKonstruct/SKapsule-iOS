---
name: skapsule-simulator
description: How the simulator skills (run-simulator, ios-simulator-skill, flow-walkthrough) apply to SKapsule-iOS. Use before building, launching or driving SKapsule in the iOS Simulator, or when reporting a result from it.
---

# SKapsule in the simulator

Read `ENGINEERING.md` ▸ Simulator first.

- **Build and run with `make sim-run`** (`scripts/sim/build-libs.sh`, `build.sh`, `run.sh`). It builds
  `build/sim/SKapsule.app`, installs it, taps Launch and waits for the game's first frame; output is in
  `build/sim/runs/<time>/`. `make sim-build` builds only; `SIM_ARGS=--launcher-only` stops at the
  launcher, `--fresh` forgets the downloaded game. Do not install a device `.app`: it is the wrong
  platform and will not launch. `run-simulator`'s generic discovery (scheme, product path) does not
  apply: the app is not an Xcode build here.
- **JIT works in the simulator** (verified on iOS 27.0): the macOS kernel grants executable memory, so
  the VM maps its code cache with no debugger. `isJITEnabled()` is forced YES there, and TXM, StikJIT,
  `SKJITHelper.appex`, pairing, LocalDevVPN, jetsam and thermal behaviour are device-only.
- **Label simulator results "sim-only"** when they rest on a simulator accommodation (the list is in
  `ENGINEERING.md`).
- Driving the UI: `run.sh` already taps Launch through `idb`. For other screens use `ios-simulator-skill`
  (tap by accessibility label, screenshots, logs; it needs `idb_companion` running for the device) and
  `flow-walkthrough` for multi-screen flows. Game Mode never engages in the simulator.
- The vendored skills in this folder are unmodified copies (see `THIRD-PARTY.md`); put
  SKapsule-specific guidance here, not in them.
