# SKapsule-iOS

Play **Spiral Knights** on iPhone and iPad. SKapsule runs the real desktop game client on
your device: a bundled Java 25 runtime, the game's OpenGL renderer translated to OpenGL ES,
OpenAL audio, touch and controller support, and Web or Steam login (including Steam Guard).

SKapsule is an unofficial fan project, not affiliated with or endorsed by
Grey Havens. It doesn't include the game: the client is downloaded from the official servers
on first launch, exactly like on desktop, and you play on your own account.

The Android version is [SKapsule](https://github.com/SKonstruct/SKapsule).

## Contents

- [Requirements](#requirements)
- [Installing](#installing)
- [Enabling JIT](#enabling-jit)
- [Playing](#playing)
- [Troubleshooting](#troubleshooting)
- [Privacy](#privacy)
- [Building from source](#building-from-source)
- [Credits and licences](#credits-and-licences)

## Requirements

- An iPhone or iPad on **iOS/iPadOS 17.4 or later**. Development happens on iOS 26.
- **JIT**. It is not optional: without it the game falls back to an interpreter and is far
  too slow to play. SKapsule can enable it itself, or through the
  [StikDebug](https://github.com/StikDebug/StikDebug) app (see [Enabling JIT](#enabling-jit)).
- About **1.5 GB** of free space. The game downloads about 440 MB on first launch.

## Installing

**From a source (AltStore, SideStore and other stores that take AltStore sources).** Add
this source URL in your store, then install SKapsule from it and get updates automatically:

```
https://raw.githubusercontent.com/SirDank/sources/main/apps.json
```

**Manually.** Download `SKapsule.ipa` from
[Releases](https://github.com/SKonstruct/SKapsule-iOS/releases) and install it with your
store, Xcode or a signing service.

The install must keep the `get-task-allow` entitlement, because that is what lets a
debugger attach and enable JIT. Sideloading with your own Apple ID keeps it, and so can
signing services. If SKapsule reports **"This install lacks get-task-allow"**, reinstall
with a method that keeps it.

On a free Apple ID, SKapsule uses two of your three app IDs: one for the app and one for
its built-in JIT helper.

A `SKapsule-TrollStore.tipa` is also built, which keeps the entitlements TrollStore preserves so
it can enable JIT without a debugger app (see [Enabling JIT](#enabling-jit)). It has not been tested.

## Enabling JIT

Open **JIT Setup** in the sidebar (or tap the **Enable JIT** pill when nothing is set up yet).
It opens a sheet with the ways to get JIT; tap one for its steps. You only need one.
**Automatic** (the default) uses the StikDebug app when it is installed and the built-in method
otherwise; picking a way pins it, and **Choose automatically** undoes that.

### Built-in (no other app needed)

Pick **Pair on this iPhone** (iOS 27 or later) or **Use a pairing file**, then:

1. Turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode.
2. **Pair.** On iOS 27 tap **Start pairing**, then in Settings → Privacy & Security → Developer
   Mode tap **Pair with SKapsule** and enter the code the sheet shows (also sent as a
   notification). Otherwise import a pairing file: the one StikDebug uses, or one made with
   `idevice_pair` on a computer. A file left at `Documents/pairingFile.plist` is picked up too.
3. Install **LocalDevVPN**. SKapsule opens it to connect when it isn't, and carries on when you
   come back; you can also connect it yourself first.
4. Tap **Check setup**, then **Enable JIT**. The first time, SKapsule downloads and mounts the
   Developer Disk Image, which takes a while. It then stays mounted until the device restarts.

iOS asks for **Local Network** access the first time: SKapsule uses it to find your device's
debug service on iOS 26 and later, and to pair with itself on iOS 27.

If you have no Wi-Fi, turn on cellular data, connect LocalDevVPN, then turn on Airplane Mode
before returning to the app. If preparing keeps failing, restart the device or use **Reset
Developer Disk Image** on the Enable page.

The pairing file is a credential for your whole device, so SKapsule keeps it where the Files
app can't reach it. Built-in JIT is unavailable inside LiveContainer.

### StikDebug

Install [StikDebug](https://github.com/StikDebug/StikDebug) and set it up, then tap **Enable
JIT** in SKapsule. SKapsule hands StikDebug its JIT script in the same request, so there is
nothing to import.

Older StikDebug versions ignore that script. If the JIT pill never turns green, update
StikDebug, or import `skapsule-jit.js` from SKapsule's folder (**Open Folder** in the
sidebar) in StikDebug's Tools and assign it to SKapsule.

### TrollStore and jailbreaks (before iOS 26)

Before iOS 26 a process a debugger touched may make executable memory itself, so these two work
without a pairing file. **Use TrollStore** asks TrollStore to enable JIT whenever the game starts
(install SKapsule through TrollStore and turn on its URL Scheme setting). **Use a jailbreak** needs
a jailbreak that marks apps as debugged, such as Dopamine's **Allow JIT in Apps**; close SKapsule
completely and open it again after turning that on. From iOS 26 JIT also needs a debugger that
stays attached, so neither is offered there.

## Playing

1. Tap **Enable JIT** and wait for the pill to turn green ("JIT enabled").
2. Tap **Launch** and pick Web or Steam login.

If you tap **Launch** first, SKapsule asks for JIT itself and starts as soon as it is
granted. The first launch downloads the game, so give it a few minutes.

**Controls.** On-screen touch controls appear in game. To rearrange them, tap ⚙ in game or
**Edit Controls** in the sidebar: drag controls around, show or hide each one, and change
their size, their opacity and the render resolution. Bluetooth controllers and keyboards
are supported, and so are mice and trackpads on iPad (less tested).

**Mods.** **Download Modpack** in the sidebar fetches the [Spiral Knights Modpack](https://github.com/SirDank/Spiral-Knights-Modpack); you can also put
your own mods in the `mods` folder (**Open Folder**). **Apply Mods** installs them and
**Remove Mods** restores the game's original files. A few config files that often clash with
game updates are never replaced, the same ones [KnightLauncher](https://github.com/lucasluqui/KnightLauncher) skips. Downloading the modpack
never deletes mods you added yourself.

**Custom servers.** The **Server** picker above Web / Steam chooses Official or a saved server; the **+**
beside it adds one (address, port, and optionally its public key and client/content URLs) and the pencil
edits the selected one. The Web / Steam switch is Official's, so it is hidden for a private server. At launch the connection settings
are written into the game's `code/config.jar` (`deployment.properties`), as KnightLauncher does, and
Official's values are written back when you switch. A private server gets the game's own logon window, or your
saved login for it if you gave one (kept in the Keychain; the game's bootstrap drops it unless the game's
`server_host` is that server). Steam sign-in is unavailable while a private server is selected. With a game update pending the launch is refused until
you update on Official, since the updater would replace the edit.

**News.** The home screen shows current in-game events from the same feed as
[KnightLauncher](https://github.com/lucasluqui/KnightLauncher). Tap a card to open the event
page.

**Game Mode.** On iOS 18 and later, iOS turns on Game Mode while SKapsule runs, which cuts
background activity and lowers controller latency. iOS may skip it if you reopen the app
moments after closing it.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| "Couldn't enable JIT" | The message gives the reason. For built-in JIT it is usually LocalDevVPN not connected, a missing pairing file, or the Developer Disk Image failing to mount. |
| The JIT pill never turns green | With StikDebug, update it or assign the script by hand (see [StikDebug](#stikdebug)). |
| "This install lacks get-task-allow" | Reinstall with a method that keeps the entitlement (see [Installing](#installing)). |
| The game runs but is unplayably slow | It launched without JIT. |
| The game's interface is tiny | Raise **Resolution** in the ⚙ panel. The change applies immediately and is remembered. |
| The `home` folder looks empty in Files | The game's settings are in hidden folders. Connect the device to a Mac and browse SKapsule in Finder to see them. |

If the game crashes or misbehaves, open the sidebar and tap **Share Logs**, then attach the
files to a [bug report](https://github.com/SKonstruct/SKapsule-iOS/issues/new/choose):

| File | Contents |
| --- | --- |
| `latestlog.txt`, `latestlog.old.txt` | Everything the launcher and game printed, for this run and the one before |
| `hs_err_pid*.log` | Java crash report, if the game crashed |
| `vmlog-*.log`, `vmout-*.log` | Java runtime logs |

Logs are shared as they are and may contain your Steam account name. Skim them before
posting them publicly.

## Privacy

When the game crashes, SKapsule sends a crash report to Sentry. A report includes the device
model, iOS version, app version, whether JIT was active and, for a Java crash, the crash
report plus the end of the previous log. Passwords, tokens, email addresses and the app's
folder path are removed from the log before sending, but it can still contain your Steam
account name. Reports don't include your device name or location.

To stop sending them, turn off **Send crash reports** in the sidebar.

## Building from source

You need a Mac with Xcode, Homebrew, Git LFS, and JDK 25 and JDK 8 (CI uses Zulu). These
are the steps [CI](.github/workflows/build-ios.yml) runs:

```sh
git clone --recursive https://github.com/SKonstruct/SKapsule-iOS.git
cd SKapsule-iOS
brew install ant maven ninja wget ldid xcodegen rustup
rustup-init -y && rustup target add aarch64-apple-ios   # on-device pairing library

# JAVA_HOME must point at JDK 25 and JAVA8_HOME at JDK 8
./scripts/build-gl4es-ios.sh
./scripts/build-openal-ios.sh
./scripts/build-lwjgl3-ios.sh
./scripts/build-cacio-ios.sh
./scripts/build-frenchpress-ios.sh
./scripts/build-rppairing-ios.sh
./scripts/build-bootstrap.sh

./scripts/stage-app-assets.sh
make package RELEASE=1      # -> out/artifacts/com.skonstruct.skapsule-<version>.ipa
```

`make package TROLLSTORE_JIT_ENT=1` builds the TrollStore `.tipa`.

**Xcode.** Run `make native && make xcode-payload`, then build the `SKapsule` scheme in
`SKapsule.xcodeproj`. A post-build step re-stages the runtime, so a normal Run picks up
rebuilt components. An app started from Xcode can't get JIT, though, so launch it from the
home screen to play. After adding a source file under `Natives/`, run `xcodegen generate`.

Contributors: [AGENTS.md](AGENTS.md) has the project conventions and
[ENGINEERING.md](ENGINEERING.md) the engineering notes and invariants.

## Credits and licences

SKapsule-iOS is free software under the [GNU GPL v3](LICENSE): you can use, study, change and
share it, and anything you distribute built from it must stay GPL-3.0 with its source. It
contains code adapted from Amethyst-iOS (GPL-3.0). It builds on:

| Project | Used for | Licence |
| --- | --- | --- |
| [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) | JIT script, launch code and build layout | GPL-3.0 |
| [AngelAuraMC OpenJDK build](https://github.com/AngelAuraMC/angelauramc-openjdk-build) | The bundled Java 25 runtime | GPLv2 with Classpath Exception |
| [gl4es](https://github.com/SKonstruct/gl4es) ([upstream](https://github.com/ptitSeb/gl4es)) | OpenGL to OpenGL ES | MIT |
| [OpenAL Soft](https://github.com/SKonstruct/openal-soft) ([upstream](https://github.com/kcat/openal-soft)) | Audio | LGPLv2 |
| [LWJGL 3](https://github.com/SKonstruct/lwjgl3) ([upstream](https://github.com/LWJGL/lwjgl3)) | Java bindings | BSD-3-Clause |
| [Caciocavallo](https://github.com/SKonstruct/caciocavallo17) | Headless AWT | GPLv2 with Classpath Exception |
| [idevice](https://github.com/jkcoxson/idevice) | On-device pairing (Rust crates, notices in the app's `legal` folder) | MIT |
| [StikJIT](https://github.com/StikDebug/StikJIT) | Built-in JIT | MPL-2.0, with one patch ([scripts/patches](scripts/patches)) |
| [bootstrap](https://github.com/SKonstruct/bootstrap) | Game bootstrap, shared with Android | MIT |
| [frenchpress](https://github.com/SKonstruct/frenchpress) | Steam login | |
| [Getdown](https://github.com/threerings/getdown) (the official client's build) | Game downloads and updates | |
| [DejaVu fonts](https://github.com/dejavu-fonts/dejavu-fonts) | Bundled fonts | [Bitstream Vera licence](assets/fonts/LICENSE) |
| [Simple Icons](https://simpleicons.org) | Buy Me a Coffee glyph | CC0 |

Spiral Knights is © Grey Havens, LLC.

If you enjoy SKapsule, you can [buy me a coffee](https://buymeacoffee.com/sirdankk).
