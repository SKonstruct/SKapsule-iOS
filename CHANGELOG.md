# Changelog

Notable changes per release. Versions are the git tags the IPAs are built from
(`vX.Y.Z` → `SKapsule.ipa` on that release). Before releasing, rename **Unreleased** to the new
version: the Release workflow publishes that section as the release notes.

## 1.0.1

### Added

- **Check for Updates** in the sidebar asks GitHub right away (the automatic check can be up to six
  hours old) and always answers: update available (with a link to the release), up to date, or
  couldn't check.

### Security

- **Mod archives are parsed defensively**: sizes are capped before anything is allocated, offsets
  are range-checked, `mod.json` values are type-checked, and locale bundle names cannot leave the
  extracted folder. Archives with data descriptors, which the old reader missed, now read correctly.
- **The news feed's cleartext exception is limited to `flamingo.knightlauncher.com`** (it had covered
  every knightlauncher.com subdomain), and links from the feed open only if they are http(s).
- **Crash reports and Share Logs scrub more**: Authorization headers, JSON tokens, SteamIDs and
  passwords containing spaces.
- Dead code is gone: the unused dyld-signature bypass and its fishhook dependency are no longer
  compiled. The JDK's license files now ship inside the app.
- Build: release workflows pin actions to commits, check the new version is higher than the last
  release, and fail if the app is missing its runtime or natives. `make test` runs host-side tests
  of the zip code. libffi and shaderc downloads in the LWJGL build are pinned and checksummed.

### Fixed

- **Mods whose `mod.json` ends with a trailing comma** (several in the modpack) are read, so their
  name and type are no longer lost.
- **Mouse and trackpad buttons are tracked separately.** Letting go of the left button and quickly
  pressing the right (charge, release, shield) could be delayed or register wrongly, because the
  button was fixed when the click began. Each button's press and release now follows the pointer's
  button state.
- **A fresh update could show in yellow as a "development build"** (`SKapsule v1.0.1-dev`). The remembered
  answer of the update check (kept for six hours) survived an update. It now belongs to the installed
  version, and Check for Updates repaints the title.
- **Download Modpack deleted your own mods** from the mods folder. It now removes only files an
  earlier download added, checks every file against GitHub before keeping it, and says when
  some failed.
- **Apply Mods could leave the game half-modded** (for example on a full disk). It now stops, keeps
  the game files as they were and tells you why. It also keeps going briefly if you switch apps.
- **The game could be killed when you left the app** (or pulled down Control Center). Rendering now
  pauses while SKapsule is not active.
- **The update notice could be hidden** by the player count. It now has its own line, and Check for
  Updates shows "Checking..." and ignores repeated taps.
- **A stalled game download is reported** after two minutes without progress, instead of sitting on
  "Validating". The updater is also given a message for every way it can fail.
- **A timed-out or offline Steam sign-in no longer discards your saved login.** Only Steam
  rejecting the token does.
- **Steam Guard prompts could fail to appear** over another dialog, and the game then waited forever.
  They now wait their turn and give up after a few minutes.
- **Built-in JIT could hang** on "Enabling" if the helper stopped answering. It now times out with a
  message.
- The Steam login text no longer says nothing is stored: a login token is kept encrypted so you stay
  signed in, never the password. The game files and that token are excluded from device backups.

## 1.0.0

First public release.

### Added

- Runs the real Spiral Knights desktop client on iPhone and iPad: a bundled Java 25 runtime,
  the game's OpenGL renderer through gl4es, OpenAL audio, and Web or Steam login (including
  Steam Guard). The game downloads from the official servers on first launch.
- **Built-in JIT**: a bundled helper enables JIT with a pairing file and LocalDevVPN, no other
  app needed. The StikDebug app still works, and is handed the JIT script automatically.
- **Touch controls** with an editor (position, visibility, size, opacity, resolution), also
  reachable from the sidebar before launching. Bluetooth controllers, keyboards, and mice and
  trackpads on iPad.
- **Mods**: download the Spiral Knights Modpack, apply, and remove, restoring the game's own
  files. Configs that clash with game updates are never replaced.
- **News card** with the current in-game events, from the same feed as KnightLauncher.
- **Game Mode** on iOS 18 and later.
- **Crash reporting** to Sentry, scrubbed of credentials and emails, with a switch in the
  sidebar. **Share Logs** collects every log a bug report needs.
- Update notice on the home screen when a newer release exists.
- Buy Me a Coffee button on the home screen.

### Requirements

- iOS/iPadOS 17.4 or later, and JIT.
