#!/usr/bin/env bash

# Builds the iOS Simulator slices of the native libraries into out/sim/, leaving out/ (the device
# builds) alone. gl4es, openal-soft and the pairing library are rebuilt against the iphonesimulator
# SDK by the same scripts the device build uses. The JRE and LWJGL natives are prebuilt for the
# device; scripts/sim/build.sh retags those (see retag_sim).
#
#   scripts/sim/build-libs.sh           # build what is missing
#   scripts/sim/build-libs.sh clean     # delete out/sim

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIM_OUT="$REPO_ROOT/out/sim"

if [[ "${1:-}" == "clean" ]]; then
    rm -rf "$SIM_OUT"
    exit 0
fi

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
mkdir -p "$SIM_OUT"

if [[ ! -f "$SIM_OUT/gl4es/libgl4es.dylib" ]]; then
    echo "=== gl4es (simulator) ==="
    SDKPATH="$SIM_SDK" OUT_DIR="$SIM_OUT/gl4es" "$REPO_ROOT/scripts/build-gl4es-ios.sh"
fi

if [[ ! -f "$SIM_OUT/openal/libopenal.dylib" ]]; then
    echo "=== openal-soft (simulator) ==="
    SDKPATH="$SIM_SDK" OUT_DIR="$SIM_OUT/openal" "$REPO_ROOT/scripts/build-openal-ios.sh"
fi

if [[ ! -f "$SIM_OUT/rppairing/libskrppairing.a" ]]; then
    echo "=== pairing library (simulator) ==="
    RP_TARGET=aarch64-apple-ios-sim OUT_DIR="$SIM_OUT/rppairing" "$REPO_ROOT/scripts/build-rppairing-ios.sh"
fi

echo
echo "Simulator libraries:"
for f in gl4es/libgl4es.dylib openal/libopenal.dylib rppairing/libskrppairing.a; do
    printf '  %-32s %s\n' "$f" "$(vtool -show-build "$SIM_OUT/$f" 2> /dev/null | awk '/platform/{print $2; exit}')"
done
