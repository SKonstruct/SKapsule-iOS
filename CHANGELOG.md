# Changelog

Notable changes per release. Versions are the git tags the IPAs are built from
(`v1.0.0` → `SKapsule.ipa` on that release). Before releasing, rename **Unreleased** to the new
version: the Release workflow publishes that section as the release notes.

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
