#!/usr/bin/env bash

# Builds StikJIT (MPL-2.0) for iOS arm64. Output: out/stikjit/StikJIT.framework
#
# StikJIT is the framework the built-in JIT helper (Natives/JITHelper) links to attach a
# debugger to SKapsule over the device's own debug tunnel, so StikDebug is not needed.
# Its idevice FFI ships prebuilt inside the submodule, so this needs only Xcode and
# xcodegen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STIKJIT_SRC="${STIKJIT_SRC:-$REPO_ROOT/external/StikJIT}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/stikjit}"
BUILD_DIR="${BUILD_DIR:-$OUT_DIR/build}"

[[ -f "$STIKJIT_SRC/project.yml" ]] || {
    echo "ERROR: StikJIT source not found at $STIKJIT_SRC (git submodule update --init)" >&2
    exit 1
}
command -v xcodegen > /dev/null || {
    echo "ERROR: xcodegen not found (brew install xcodegen)" >&2
    exit 1
}

echo "StikJIT source: $STIKJIT_SRC"
echo

rm -rf "$BUILD_DIR" "$OUT_DIR/StikJIT.framework"
mkdir -p "$OUT_DIR"
(cd "$STIKJIT_SRC" && xcodegen generate --quiet)
xcodebuild archive \
    -project "$STIKJIT_SRC/StikJIT.xcodeproj" \
    -scheme StikJIT \
    -destination 'generic/platform=iOS' \
    -archivePath "$BUILD_DIR/StikJIT" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

cp -R "$BUILD_DIR/StikJIT.xcarchive/Products/Library/Frameworks/StikJIT.framework" "$OUT_DIR/"
# MPL-2.0 travels with the binary.
cp "$STIKJIT_SRC/LICENSE" "$OUT_DIR/StikJIT.framework/LICENSE"

# StikJIT's project.yml declares no Info.plist, so the archive has none, and installd
# rejects an embedded framework without one.
PLIST="$OUT_DIR/StikJIT.framework/Info.plist"
if [[ ! -f "$PLIST" ]]; then
    VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$STIKJIT_SRC/project.yml" | head -1)"
    plutil -create xml1 "$PLIST"
    plutil -insert CFBundleIdentifier -string com.stik.StikJIT "$PLIST"
    plutil -insert CFBundleExecutable -string StikJIT "$PLIST"
    plutil -insert CFBundleName -string StikJIT "$PLIST"
    plutil -insert CFBundlePackageType -string FMWK "$PLIST"
    plutil -insert CFBundleShortVersionString -string "${VERSION:-1.0}" "$PLIST"
    plutil -insert CFBundleVersion -string "${VERSION:-1.0}" "$PLIST"
    plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
    plutil -insert CFBundleSupportedPlatforms -json '["iPhoneOS"]' "$PLIST"
    plutil -insert MinimumOSVersion -string 17.4 "$PLIST"
fi

echo
echo "=== done ==="
ls -la "$OUT_DIR/StikJIT.framework/StikJIT"
