#!/usr/bin/env bash

# Builds gl4es for iOS arm64. Output: out/gl4es/libgl4es.dylib

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GL4ES_SRC="${GL4ES_SRC:-$REPO_ROOT/external/gl4es}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/gl4es}"
BUILD_DIR="${BUILD_DIR:-$OUT_DIR/build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

SDKPATH="${SDKPATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
[[ -d "$SDKPATH" ]] || {
                         echo "ERROR: iOS SDK not found at $SDKPATH" >&2
                                                                          exit 1
}
[[ -d "$GL4ES_SRC" ]] || {
                           echo "ERROR: gl4es source not found at $GL4ES_SRC" >&2
                                                                                   exit 1
}

JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2> /dev/null || echo 4)}"

# SK_ASAN=1 builds gl4es under AddressSanitizer. The heap corruption in this port has
# survived every other instrument -- libmalloc's own checker only fires on a random later
# victim, and malloc_zone_check is blind to iOS 27's xzone allocator. ASan reports the
# *writing* instruction. Off by default: it costs ~2-3x and needs the runtime staged into
# the bundle (scripts/stage-app-assets.sh).
GL4ES_CFLAGS="-fstack-protector-strong"
if [[ "${SK_ASAN:-0}" == "1" ]]; then
    GL4ES_CFLAGS="$GL4ES_CFLAGS -fsanitize=address -fno-omit-frame-pointer"
    echo "AddressSanitizer: ON"
fi

# -fstack-protector-strong: a transposed-matrix uniform overflowed a fixed stack buffer
# here and corrupted memory silently for days. The canary turns the next one into an
# immediate, localised abort. Costs a few percent; worth it while this port is unstable.
echo "gl4es source: $GL4ES_SRC"
echo "iOS SDK:      $SDKPATH"
echo "Build type:   $BUILD_TYPE"
echo

mkdir -p "$BUILD_DIR" "$OUT_DIR"

cmake -S "$GL4ES_SRC" -B "$BUILD_DIR" \
    -DCMAKE_CROSSCOMPILING=true \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_SYSROOT="$SDKPATH" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_C_FLAGS="$GL4ES_CFLAGS" \
    -DNOX11=ON \
    -DNOEGL=ON \
    -DDEFAULT_ES=2 \
    -DSTATICLIB=OFF \
    -DNO_INIT_CONSTRUCTOR=ON \
    -DGBM=OFF

# gl4es hardcodes EXPORT to empty on __APPLE__, and forces -fvisibility=hidden.
# This causes the resulting dylib to export zero symbols, breaking LWJGL3's symbol lookup.
# Strip -fvisibility=hidden from the generated ninja/make flags before building.
find "$BUILD_DIR" -type f -name "flags.make" -exec sed -i '' 's/-fvisibility=hidden//g' {} +
find "$BUILD_DIR" -type f -name "build.ninja" -exec sed -i '' 's/-fvisibility=hidden//g' {} + 2> /dev/null || true

cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" -j"$JOBS"

SRC_LIB=""
for cand in "$BUILD_DIR/libGL.dylib" "$GL4ES_SRC/lib/libGL.dylib"; do
    [[ -e "$cand" ]] && SRC_LIB="$(readlink -f "$cand" 2> /dev/null || realpath "$cand")" && break
done
if [[ -z "$SRC_LIB" || ! -f "$SRC_LIB" ]]; then
    echo "ERROR: could not locate built libGL.dylib" >&2
    find "$BUILD_DIR" "$GL4ES_SRC/lib" -maxdepth 3 -name 'libGL*' 2> /dev/null >&2
    exit 1
fi

cp -v "$SRC_LIB" "$OUT_DIR/libgl4es.dylib"

echo
echo "=== done ==="
ls -lh "$OUT_DIR/libgl4es.dylib"
