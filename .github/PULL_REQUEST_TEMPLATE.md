## What this changes

<!-- One logical change per PR. If you're tempted to write "and also", it's probably two PRs. -->

## Why

<!-- The problem being solved. Link the issue if there is one: Fixes #123 -->

## How it was verified

<!-- Say what you actually ran. "Should work" is not verification; say so plainly if you couldn't build. -->

- [ ] `make native` succeeds
- [ ] Tested on a device with JIT enabled — device and iOS version:

<!-- For UI or touch-control changes, a screenshot or short clip saves a round trip. -->

## Checklist

- [ ] Docs updated in the same change (README / ROADMAP / AGENTS), or nothing needed updating
- [ ] New files under `Natives/` — ran `xcodegen generate` and committed `SKapsule.xcodeproj`
      (the project is generated *and* checked in; nothing regenerates it at build time)
- [ ] No new third-party dependencies, or they're called out above and justified
- [ ] No secrets or signing certificates
- [ ] No submodule pointer moved as a side effect
- [ ] No changes to `.github/workflows/`, signing config or entitlement files — or they
      were agreed beforehand
- [ ] Nothing bypasses Cacio
- [ ] Touch-control behaviour, defaults or layout: checked against
      [SKapsule](https://github.com/SKonstruct/SKapsule) so the two ports stay comparable

## Anything reviewers should look at closely

<!-- Tradeoffs you made, things you're unsure about, or code you'd like a second opinion on. -->
