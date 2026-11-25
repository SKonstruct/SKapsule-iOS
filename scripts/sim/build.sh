#!/usr/bin/env bash

# Builds SKapsule for the iOS Simulator: build/sim/SKapsule.app, ad-hoc signed, with no signing
# profile, no JIT helper and no device. The device build (make native / payload / package) is not
# touched; everything here lives under build/sim and out/sim.
#
#   scripts/sim/build.sh
#
# Needs the simulator libraries (scripts/sim/build-libs.sh, run for you when missing) and the jars
# the device build stages from out/ (cacio, frenchpress, bootstrap, LWJGL, see scripts/build.sh).
#
# What differs from the device bundle: the app, gl4es, openal and the pairing library are compiled
# for the simulator; the JRE and LWJGL natives are the device builds with their Mach-O platform
# retagged (the arm64 code is the same); no PlugIns/SKJITHelper.appex, no StikJIT.framework.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIM_OUT="$ROOT/out/sim"
BUILD="$ROOT/build/sim"
NATIVE="$BUILD/native"
APP="$BUILD/SKapsule.app"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
MIN_OS=17.4
BUNDLE_ID=com.skonstruct.skapsule  # as the Makefile's BUNDLE_ID; a simulator is its own world
VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2> /dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-1.0.0}"
JOBS="$(sysctl -n hw.logicalcpu 2> /dev/null || echo 4)"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Turns a device Mach-O into a simulator one: same arm64 code, different platform in
# LC_BUILD_VERSION (dyld in a simulator process refuses an iOS-platform image). Re-signs ad hoc,
# which the edit invalidates.
retag_sim() {
    local f
    for f in "$@"; do
        if vtool -show-build "$f" 2> /dev/null | grep -q 'platform IOS$'; then
            vtool -set-build-version iossim "$MIN_OS" "$MIN_OS" -replace -output "$f.retag" "$f" > /dev/null 2>&1
            mv "$f.retag" "$f"
        fi
        codesign --force --sign - "$f" 2> /dev/null
    done
}

[[ -f "$SIM_OUT/gl4es/libgl4es.dylib" && -f "$SIM_OUT/openal/libopenal.dylib" && -f "$SIM_OUT/rppairing/libskrppairing.a" ]] ||
    "$ROOT/scripts/sim/build-libs.sh"
for j in cacio/cacio-shared.jar cacio/cacio-tta.jar frenchpress/frenchpress.jar bootstrap/sk-bootstrap.jar \
    lwjgl3/lwjgl-3.4.1-ios-natives-arm64.zip lwjgl3/lwjgl-3.4.1-ios-modules.zip; do
    [[ -f "$ROOT/out/$j" ]] || die "missing out/$j: run ./scripts/build.sh --natives first (the device build's jars are reused)"
done

# --- the app -----------------------------------------------------------------------------------
say "compiling the app for the simulator"
mkdir -p "$NATIVE"
# CMake writes Natives/config.h (version, commit) into the source tree, where the Xcode build reads it
# too: put it back afterwards so this build's stamp does not leak into a device build.
CONFIG_H="$ROOT/Natives/config.h"
if [[ -f "$CONFIG_H" ]]; then
    cp "$CONFIG_H" "$BUILD/config.h.orig"
    trap 'cp "$BUILD/config.h.orig" "$CONFIG_H"' EXIT
fi
(cd "$NATIVE" && cmake \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CROSSCOMPILING=true \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_OS" \
    -DCMAKE_C_FLAGS="-arch arm64" \
    -DSK_RPPAIRING_LIB="$SIM_OUT/rppairing/libskrppairing.a" \
    -DCONFIG_VERSION="$VERSION" \
    -DCONFIG_BRANCH="$(git -C "$ROOT" branch --show-current 2> /dev/null || echo unknown)" \
    -DCONFIG_COMMIT="$(git -C "$ROOT" log --oneline -1 2> /dev/null | cut -b 1-7 || echo unknown)-sim" \
    -DCONFIG_RELEASE=0 \
    "$ROOT/Natives" > /dev/null)
cmake --build "$NATIVE" -j"$JOBS" 2>&1 | grep -E "error|warning: .*(link|ld)|Undefined" || true
[[ -x "$NATIVE/SKapsule.app/SKapsule" ]] || die "the app did not build"

# --- the JRE -----------------------------------------------------------------------------------
# The same layout and trimming as METHOD_STAGE_JRE in the Makefile (keep them in step), staged under
# out/sim so the device JRE in out/ is left as it is, and retagged once.
if [[ ! -f "$SIM_OUT/jre25/release" ]]; then
    say "staging the JRE (retagged for the simulator)"
    mkdir -p "$SIM_OUT"
    rm -rf "$SIM_OUT/jre25"
    unzip -q "$ROOT/assets/jre25-ios-aarch64.zip" -d "$SIM_OUT"
    J="$SIM_OUT/jre25"
    [[ -d "$J/lib/zero" ]] && mv "$J/lib/zero" "$J/lib/server"
    [[ -f "$J/lib/jvm.cfg" ]] && echo "-server KNOWN" > "$J/lib/jvm.cfg"
    for stub in "awt_stubs.c:libawt_headless" "prefs_stubs.c:libprefs"; do
        xcrun --sdk iphonesimulator clang -shared -arch arm64 -isysroot "$SIM_SDK" \
            -I"$J/include" -I"$J/include/darwin" -mios-simulator-version-min="$MIN_OS" \
            -o "$J/lib/${stub#*:}.dylib" "$ROOT/Natives/${stub%%:*}"
    done
    xcrun --sdk iphonesimulator clang -shared -arch arm64 -isysroot "$SIM_SDK" \
        -mios-simulator-version-min="$MIN_OS" -o "$J/lib/libawt_xawt.dylib" "$ROOT/Natives/awt_xawt/xawt_fake.m"
    rm -rf "$J"/{bin,include,jre,man,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}}
    find "$J" -type l -delete
    retag_sim $(find "$J" -name '*.dylib' -o -name 'jspawnhelper' | sort)
fi

# --- the bundle --------------------------------------------------------------------------------
say "assembling $APP"
rm -rf "$APP"
cp -R "$NATIVE/SKapsule.app" "$APP"
rm -f "$APP"/*.dylib
mkdir -p "$APP/Frameworks" "$APP/libs"
cp -R "$SIM_OUT/jre25" "$APP/jre25"

xcrun actool "$ROOT/Natives/Assets.xcassets" --compile "$APP" --platform iphonesimulator \
    --minimum-deployment-target "$MIN_OS" --app-icon AppIcon \
    --output-partial-info-plist "$BUILD/actool-info.plist" > /dev/null
PL="$APP/Info.plist"
cp "$ROOT/Natives/Info.plist" "$PL"
for k in CFBundleIcons CFBundleIcons~ipad; do
    plutil -extract "$k" json -o - "$BUILD/actool-info.plist" | xargs -0 -I{} plutil -replace "$k" -json '{}' "$PL"
done
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PL"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PL"
plutil -replace CFBundleVersion -string 1 "$PL"
plutil -replace BGTaskSchedulerPermittedIdentifiers -json "[\"$BUNDLE_ID.pairing.*\"]" "$PL"
plutil -replace SKBuildStamp -string "$(date '+%Y-%m-%d %H:%M:%S') (simulator)" "$PL"
plutil -replace MinimumOSVersion -string "$MIN_OS" "$PL"
plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$PL"
plutil -replace UIDeviceFamily -json '[1,2]' "$PL"
plutil -replace DTPlatformName -string iphonesimulator "$PL"

# The device build's staging: jars, fonts, the JIT script, LWJGL. It also copies the device slices of
# gl4es, openal and the LWJGL natives into Frameworks/; those are replaced and retagged next.
APP_DIR="$APP" "$ROOT/scripts/stage-app-assets.sh" > /dev/null
cp "$SIM_OUT/gl4es/libgl4es.dylib" "$SIM_OUT/openal/libopenal.dylib" "$APP/Frameworks/"
cp "$SIM_OUT/rppairing/LICENSES-rppairing-crates.txt" "$APP/legal/" 2> /dev/null || true
retag_sim "$APP"/Frameworks/*.dylib

# Nothing here is signed by a profile: ad hoc, with no entitlements (so no get-task-allow either; a
# simulator needs neither).
codesign --force --sign - "$APP"
say "built $APP"
for f in "$APP/SKapsule" "$APP/Frameworks/libgl4es.dylib" "$APP/jre25/lib/server/libjvm.dylib"; do
    printf '    %-34s %s\n' "${f#$APP/}" "$(vtool -show-build "$f" | awk '/platform/{print $2; exit}')"
done
