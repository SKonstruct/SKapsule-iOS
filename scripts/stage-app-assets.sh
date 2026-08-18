#!/usr/bin/env bash

# Stages all native + Java build outputs into the app payload for bundling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="${APP_DIR:-$REPO_ROOT/Natives/build/SKapsule.app}"

stage() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        echo "  MISS: $src" >&2
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    cp -v "$src" "$dst"
}

echo "=== libgl4es.dylib ==="
stage "$REPO_ROOT/out/gl4es/libgl4es.dylib" \
      "$APP_DIR/Frameworks/libgl4es.dylib" ||
    echo "  (run ./scripts/build-gl4es-ios.sh first)"

echo
echo "=== libopenal.dylib ==="
stage "$REPO_ROOT/out/openal/libopenal.dylib" \
      "$APP_DIR/Frameworks/libopenal.dylib" ||
    echo "  (run ./scripts/build-openal-ios.sh first)"

echo
echo "=== caciocavallo (AWT bridge) ==="
stage "$REPO_ROOT/out/cacio/cacio-shared.jar" \
      "$APP_DIR/libs_cacio/cacio-shared.jar" ||
    echo "  (run ./scripts/build-cacio-ios.sh first)"
stage "$REPO_ROOT/out/cacio/cacio-tta.jar" \
      "$APP_DIR/libs_cacio/cacio-tta.jar" ||
    echo "  (run ./scripts/build-cacio-ios.sh first)"

echo
echo "=== frenchpress (Steam login) ==="
stage "$REPO_ROOT/out/frenchpress/frenchpress.jar" \
      "$APP_DIR/libs/frenchpress.jar" ||
    echo "  (run ./scripts/build-frenchpress-ios.sh first)"

echo
echo "=== sk-bootstrap.jar ==="
stage "$REPO_ROOT/out/bootstrap/sk-bootstrap.jar" \
      "$APP_DIR/libs/sk-bootstrap.jar" ||
    echo "  (run ./scripts/build-bootstrap.sh first)"

echo
echo "=== getdown-pro.jar ==="
stage "$REPO_ROOT/assets/getdown-pro.jar" \
      "$APP_DIR/libs/getdown-pro.jar" ||
    echo "  (place getdown-pro.jar in assets/)"

echo
echo "=== Fonts ==="
mkdir -p "$APP_DIR/jre25/lib/fonts"
cp "$REPO_ROOT/assets/fonts/"* "$APP_DIR/jre25/lib/fonts/" 2> /dev/null ||
    echo "  (place .ttf font files in assets/fonts/)"

echo "=== fontconfig.properties ==="
stage "$REPO_ROOT/assets/fontconfig.properties" \
      "$APP_DIR/jre25/lib/fontconfig.properties" ||
    echo "  (create assets/fontconfig.properties)"

echo
echo "=== JIT script (StikJIT, iOS 26 TXM) ==="
stage "$REPO_ROOT/assets/UniversalJIT26.js" \
      "$APP_DIR/UniversalJIT26.js" ||
    echo "  (assets/UniversalJIT26.js missing)"

echo
echo "=== LWJGL Modules ==="
LWJGL_MODS="$REPO_ROOT/out/lwjgl3/lwjgl-3.4.1-ios-modules.zip"
if [[ -f "$LWJGL_MODS" ]]; then
    mkdir -p "$APP_DIR/libs_lwjgl"
    # Unzip all jars flattening the structure, and overwrite if exists
    unzip -q -o -j "$LWJGL_MODS" '*.jar' -d "$APP_DIR/libs_lwjgl" || true
else
    echo "  (run ./scripts/build-lwjgl3-ios.sh first)"
fi

echo
echo "=== LWJGL Natives ==="
LWJGL_NATIVES="$REPO_ROOT/out/lwjgl3/lwjgl-3.4.1-ios-natives-arm64.zip"
if [[ -f "$LWJGL_NATIVES" ]]; then
    mkdir -p "$APP_DIR/Frameworks"
    # Unzip all dylibs flattening the structure, and overwrite if exists
    unzip -q -o -j "$LWJGL_NATIVES" '*.dylib' -d "$APP_DIR/Frameworks" || true
else
    echo "  (run ./scripts/build-lwjgl3-ios.sh first)"
fi

echo
echo "=== LWJGL AngelAura compat symlink ==="
ln -sfn Frameworks/liblwjgl.dylib "$APP_DIR/AngelAuraAmethyst"

echo
echo "done."
