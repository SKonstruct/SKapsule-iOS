# Changelog

Notable changes per release. Versions are the git tags the IPAs are built from
(`vX.Y.Z` → `SKapsule.ipa` on that release). Before releasing, rename **Unreleased** to the new
version: the Release workflow publishes that section as the release notes.

## 1.1.0

### Added

- **Languages.** The app has string files for Arabic, German, Spanish, Estonian, French, Italian, Japanese, Polish,
  Brazilian Portuguese, Russian and Simplified and Traditional Chinese; pick one in iOS Settings > SKapsule > Language
  (text not translated yet shows in English). The interface text now goes through `NSLocalizedString`.
- **A credit.** "Built with ♥ by SirDank" in the top-left corner of the main screen, quiet and grey with a
  pink heart; the name opens the author's site.
- **FPS counter.** A small "FPS 55" in the top-left corner, on by default. **Show FPS counter** in the
  settings panel (tap ⚙ in game) turns it off.
- **Sharpening.** A slider in the same panel sharpens the picture on its way to the screen, which is what
  you want when **Resolution** is below 100%: the game is drawn smaller and stretched, and sharpening
  brings the edges back. 0% (the default) leaves the picture as it was.
- **Sharp HUD (experimental).** Below 100% resolution the HUD is drawn small and stretched too, so its text
  is soft. With this on, the scene stays at your resolution and the HUD is drawn at the screen's full
  resolution, so its text is crisp. The HUD is then smaller, so raise the game's own UI scale. Off by default.
- **Layouts: presets, export and import.** **Layouts…** in the Edit Controls panel keeps named presets of your
  control layout (plus the built-in default), and exports or imports one as a `.json` file through the Files
  picker. A layout exported here imports on SKapsule for Android, and the other way round. Only the arrangement
  travels: where each control sits, its size and whether it shows, plus opacity and **Show Buttons**. Resolution
  and **Show Controls** stay yours, and a file can never change what a control does. Importing saves a new
  preset and asks before applying it.
- **Graphics settings in the sidebar.** **Show FPS counter**, **Sharpening** and **Sharp HUD** are now also in
  the sidebar, so you can set them without starting the game. They are the same settings as the in-game panel.
- **Mods apply by themselves.** There is no Apply Mods button: when the mods folder changes (a download, or a
  mod you added) or the game updates, SKapsule applies the mods when you open the launcher, and restores the game
  once if you remove every mod. **Remove Mods** is now **Reset Game Files**; the mods already in the folder stay
  unapplied after it until the folder changes.
- **The game's own mouse cursor.** **Show mouse cursor** in the sidebar and in the editor's Settings tab shows
  Spiral Knights' real cursor, the one the game draws on desktop, where the game last saw the pointer. It follows a
  finger, a trackpad or an external mouse, and a mouse's own pointer is hidden while it shows, so there is only one.
  Off by default.
- **Avoid screen edges in the editor.** The Settings tab has the same switch as the sidebar, and it re-insets the
  game at once.
- **A calmer touch-controls editor.** A tab strip at the top switches between **Edit** and **Settings**. On Edit,
  the small dialog for the selected control only appears when something is selected, and it docks away from
  that control so it never covers what you are dragging. Settings shows the full panel with the controls
  visible but untouchable.
  The tab strip is Edit | Settings: the settings button closes the editor.
- **A tidier sidebar.** The descriptions under **Send crash reports**, **Sharp HUD** and **Floating right stick** are
  gone, and the settings sidebar runs to the bottom edge of the screen.
- **Floating thumb sticks.** Turn on **Floating left stick** and/or **Floating right stick** in Settings: the stick
  appears where your thumb lands on that half of the screen and follows it, leaving a faint ghost where it
  waits. Buttons still win a touch. The choice is saved in layouts, presets and exported files (older versions
  ignore it).
- **The modpack button says what to do.** It reads **Download Modpack**, **Update Modpack** when the modpack
  has changed, or **Modpack up to date**. SKapsule asks GitHub once when it starts.

### Fixed

- **Typing in the game's text boxes works as you type.** The text showed up but did nothing (a search or filter did not
  update, a form did not enable) until Enter or Backspace was pressed. The on-screen keyboard now sends each
  character the way a desktop keyboard does, key press then the character then key release.
- **Mods apply in a fixed order.** They used to apply in whatever order iOS listed the files, so which mod won a
  clash could differ between devices. The mods that change the most files now go first and equal ones by name, so a
  small, targeted mod wins over a broad one (the same rule as SKradle and SKapsule for Android). There is nothing to
  sort by hand.

### Changed

- **Steam sign-in is by QR code or the Steam app, with no username or password.** The first Steam launch
  shows a QR code in portrait, before the game starts and the screen turns landscape: scan it with the Steam mobile app and approve, or tap **Open Steam app**. SKapsule
  no longer asks for your Steam password or a Steam Guard code, and keeps only the sign-in token it
  already stored. If you were signed in you stay signed in. **Cancel** carries on without Steam.
- **The default memory limit for the game is now 1024 MB** (it was 768 MB). It applies if you never changed
  the setting, and it is only a ceiling: the game still starts small and takes what it needs.
- **The game now runs with two more of KnightLauncher's recommended settings.** Its own requests to run
  garbage collection are ignored, which avoids some freezes, and textures it no longer uses are released
  sooner.
- **Built-in JIT is updated to StikJIT 2.0.** It checks more carefully for a broken connection before
  trying, and no longer leaves handles open when it fails.
- The graphics and audio libraries are updated to their latest upstream versions (rendering fixes and
  new OpenGL features, and many OpenAL Soft changes).

## 1.0.4

### Fixed

- **Game froze when opening the friends list with Steam sign-in.** The game's 10 November update added a
  Steam call the Steam stand-in did not have, which stopped the game's render loop. The friends list now
  opens.

## 1.0.3

### Added

- **Connect to custom servers.** A **Server** picker above Web / Steam lists Official and the servers you
  add: tap it to choose one, and use the **+** beside it to add a server (name, address, port, and
  optionally the server's public key, client and content URLs and a username and password for quick
  login, kept in the Keychain and only handed to the game if the game is set up for that server) or the
  pencil to edit or delete the selected one. The chosen server is written into the game's `config.jar` at
  every launch, so switching back to Official undoes it. A private server uses the game's own logon
  window, so the Web / Steam switch is hidden while one is selected. If the game has an update pending, the
  launcher asks you to update on Official first, because the updater would otherwise replace the edit
  and quietly connect you to Official.
- **JIT Setup has an Automatic method** (the default): it uses the StikDebug app when it is installed
  and built-in JIT otherwise. You can still pin either one.
- **Built-in JIT connects LocalDevVPN for you.** If it isn't routing, SKapsule opens LocalDevVPN to
  connect, and carries on when you come back. Failures explain a replaced pairing file, another VPN,
  or cellular data (which breaks LocalDevVPN's loopback).
- **A pairing file left at `Documents/pairingFile.plist`** (where iloader and most JIT apps put it) is
  picked up automatically, like the one under `StikJIT/`.
- **JIT Setup is a bottom sheet** with every way to get JIT and its numbered steps: pair on this
  device, use a pairing file, StikDebug, TrollStore and a jailbreak (both before iOS 26). It walks
  through LocalDevVPN, Check setup and Enable JIT, and says what to do when one of them fails.
- **Pair on This Device** (iOS 27 and later): built-in JIT can now make its own pairing file, with no
  computer. Start it in the sheet, then in Settings > Privacy & Security > Developer Mode tap "Pair with
  SKapsule" and enter the code shown. The pairing keeps running while you are in Settings.
- iOS now asks for **Local Network** access: built-in JIT needs it on iOS 26 and later to find the
  device's debug service, and a private server on your network needs it to be reached.

### Changed

- **Built-in JIT on iOS 26 and later looks up the device's debug port** instead of assuming one, and
  its debugger now handles JIT memory at any address (a bundled StikJIT patch). Both are for devices where
  the old assumptions failed; they have not been tested on every device.
- **A JIT request nothing answers no longer kills the app silently.** The game screen says JIT was not
  enabled and what to do.

## 1.0.2

### Fixed

- **Mods can no longer replace the behavior, spawn table and variant table configs** (`config/behavior`,
  `spawn_table`, `variant_table`, `.dat` and `.xml`). The protected list was still six entries short of
  KnightLauncher's.
- **A first launch that downloads the game could be called a failed start.** The 90-second start
  timer ran from the moment the game launched, even while the download was reporting progress. It now
  restarts with every status message, so only 90 seconds of silence counts.
- **Apply Mods before the game has been launched once** asks for a launch first and no longer sends an
  error report, and cancelling the JIT wait is no longer reported as a failure.

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
