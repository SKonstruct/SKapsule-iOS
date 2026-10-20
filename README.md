# SKapsule-iOS

Play **Spiral Knights** on iPhone and iPad. SKapsule runs the real desktop game client on
your device: a bundled Java 25 runtime, the game's OpenGL renderer translated to OpenGL ES,
OpenAL audio, touch and controller support, and Web or Steam login (including Steam Guard).

> [!WARNING]
> **Experimental.** Gameplay has been reached on device, but recent builds are still being
> stabilised and crashes are expected. Bug reports with logs are very welcome.

SKapsule is an unofficial fan project, not affiliated with or endorsed by SEGA or
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

A `SKapsule-TrollStore.tipa` is also built, which enables JIT through TrollStore instead.
It has not been tested.

## Enabling JIT

Open **JIT Setup** in the sidebar and pick one of the two methods below. You only need one.

### Built-in (no other app needed)

1. Turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode.
2. Install **LocalDevVPN** and connect it.
3. Get your device's **pairing file**: the one StikDebug uses, or one made with
   `idevice_pair` on a computer. In SKapsule, open **JIT Setup → Import Pairing File** and
   pick it.
4. Tap **Enable JIT**. The first time, SKapsule downloads and mounts the Developer Disk
   Image, which takes a while. It then stays mounted until the device restarts.

**Check Setup** tests the connection without launching the game. If you have no Wi-Fi, turn
on cellular data, connect LocalDevVPN, then turn on Airplane Mode before returning to the
app. If preparing keeps failing, restart the device or use **Reset Developer Disk Image**.

The pairing file is a credential for your whole device, so SKapsule keeps it where the Files
app can't reach it. Built-in JIT is unavailable inside LiveContainer.

### StikDebug

Install [StikDebug](https://github.com/StikDebug/StikDebug) and set it up, then tap **Enable
JIT** in SKapsule. SKapsule hands StikDebug its JIT script in the same request, so there is
nothing to import.

Older StikDebug versions ignore that script. If the JIT pill never turns green, update
StikDebug, or import `skapsule-jit.js` from SKapsule's folder (**Open Folder** in the
sidebar) in StikDebug's Tools and assign it to SKapsule.

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
game updates are never replaced, the same ones KnightLauncher skips.

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
brew install ant maven ninja wget ldid xcodegen

# JAVA_HOME must point at JDK 25 and JAVA8_HOME at JDK 8
./scripts/build-gl4es-ios.sh
./scripts/build-openal-ios.sh
./scripts/build-lwjgl3-ios.sh
./scripts/build-cacio-ios.sh
./scripts/build-frenchpress-ios.sh
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
[ROADMAP.md](ROADMAP.md) the engineering notes and invariants.

## Credits and licences

SKapsule-iOS is free software under the [GNU GPL v3](LICENSE): you can use, study, change and
share it, and anything you distribute built from it must stay GPL-3.0 with its source. It
contains code adapted from Amethyst-iOS (GPL-3.0). It builds on:

| Project | Used for | Licence |
| --- | --- | --- |
| [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) | JIT script, dyld bypass, launch code and build layout | GPL-3.0 |
| [AngelAuraMC OpenJDK build](https://github.com/AngelAuraMC/angelauramc-openjdk-build) | The bundled Java 25 runtime | GPLv2 with Classpath Exception |
| [gl4es](https://github.com/SKonstruct/gl4es) ([upstream](https://github.com/ptitSeb/gl4es)) | OpenGL to OpenGL ES | MIT |
| [OpenAL Soft](https://github.com/SKonstruct/openal-soft) ([upstream](https://github.com/kcat/openal-soft)) | Audio | LGPLv2 |
| [LWJGL 3](https://github.com/SKonstruct/lwjgl3) ([upstream](https://github.com/LWJGL/lwjgl3)) | Java bindings | BSD-3-Clause |
| [Caciocavallo](https://github.com/SKonstruct/caciocavallo17) | Headless AWT | GPLv2 with Classpath Exception |
| [fishhook](https://github.com/SKonstruct/fishhook) ([upstream](https://github.com/facebook/fishhook)) | Runtime symbol rebinding | BSD-3-Clause |
| [StikJIT](https://github.com/StikDebug/StikJIT) | Built-in JIT | MPL-2.0, bundled unmodified |
| [bootstrap](https://github.com/SKonstruct/bootstrap) | Game bootstrap, shared with Android | MIT |
| [frenchpress](https://github.com/SKonstruct/frenchpress) | Steam login | |
| [Getdown](https://github.com/threerings/getdown) (the official client's build) | Game downloads and updates | |
| [DejaVu fonts](https://github.com/dejavu-fonts/dejavu-fonts) | Bundled fonts | [Bitstream Vera licence](assets/fonts/LICENSE) |
| [Simple Icons](https://simpleicons.org) | Buy Me a Coffee glyph | CC0 |

Spiral Knights is © SEGA / Grey Havens, LLC.

If you enjoy SKapsule, you can [buy me a coffee](https://buymeacoffee.com/sirdankk).
