#!/usr/bin/env bash

# Builds openal-soft for iOS arm64. Output: out/openal/libopenal.dylib

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENAL_SRC="${OPENAL_SRC:-$REPO_ROOT/external/openal-soft}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/openal}"
BUILD_DIR="${BUILD_DIR:-$OUT_DIR/build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

SDKPATH="${SDKPATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
[[ -d "$SDKPATH" ]] || { echo "ERROR: iOS SDK not found at $SDKPATH" >&2; exit 1; }
[[ -d "$OPENAL_SRC" ]] || { echo "ERROR: openal-soft source not found at $OPENAL_SRC" >&2; exit 1; }

JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

echo "openal-soft source: $OPENAL_SRC"
echo "iOS SDK:            $SDKPATH"
echo "Build type:         $BUILD_TYPE"
echo

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

cmake -S "$OPENAL_SRC" -B "$BUILD_DIR" \
    -DCMAKE_CROSSCOMPILING=true \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_SYSROOT="$SDKPATH" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_CXX_FLAGS="-D_LIBCPP_DISABLE_AVAILABILITY" \
    -DLIBTYPE=SHARED \
    -DALSOFT_UTILS=OFF \
    -DALSOFT_EXAMPLES=OFF \
    -DALSOFT_TESTS=OFF \
    -DALSOFT_INSTALL=OFF \
    -DALSOFT_NO_CONFIG_UTIL=ON \
    -DALSOFT_EAX=OFF \
    -DALSOFT_BACKEND_COREAUDIO=ON \
    -DALSOFT_BACKEND_OPENSL=OFF \
    -DALSOFT_BACKEND_WAVE=OFF \
    -DALSOFT_UPDATE_BUILD_VERSION=OFF

cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --target OpenAL -j"$JOBS"

SRC_LIB=""
for cand in "$BUILD_DIR/libopenal.dylib" "$BUILD_DIR/lib/libopenal.dylib"; do
    [[ -e "$cand" ]] && SRC_LIB="$(readlink -f "$cand" 2>/dev/null || realpath "$cand")" && break
done
if [[ -z "$SRC_LIB" || ! -f "$SRC_LIB" ]]; then
    echo "ERROR: could not locate built libopenal.dylib" >&2
    exit 1
fi

cp -v "$SRC_LIB" "$OUT_DIR/libopenal.dylib"

echo
echo "=== done ==="
ls -lh "$OUT_DIR/libopenal.dylib"
