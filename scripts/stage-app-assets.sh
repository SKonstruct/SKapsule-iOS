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
      "$APP_DIR/Frameworks/libgl4es.dylib" || \
    echo "  (run ./scripts/build-gl4es-ios.sh first)"

echo
echo "=== libopenal.dylib ==="
stage "$REPO_ROOT/out/openal/libopenal.dylib" \
      "$APP_DIR/Frameworks/libopenal.dylib" || \
    echo "  (run ./scripts/build-openal-ios.sh first)"

echo
echo "=== caciocavallo (AWT bridge) ==="
stage "$REPO_ROOT/out/cacio/cacio-shared.jar" \
      "$APP_DIR/libs_cacio/cacio-shared.jar" || \
    echo "  (run ./scripts/build-cacio-ios.sh first)"
stage "$REPO_ROOT/out/cacio/cacio-tta.jar" \
      "$APP_DIR/libs_cacio/cacio-tta.jar" || \
    echo "  (run ./scripts/build-cacio-ios.sh first)"

echo
echo "=== frenchpress (Steam login) ==="
stage "$REPO_ROOT/out/frenchpress/frenchpress.jar" \
      "$APP_DIR/libs/frenchpress.jar" || \
    echo "  (run ./scripts/build-frenchpress-ios.sh first)"

echo
echo "=== sk-bootstrap.jar ==="
stage "$REPO_ROOT/out/bootstrap/sk-bootstrap.jar" \
      "$APP_DIR/libs/sk-bootstrap.jar" || \
    echo "  (run ./scripts/build-bootstrap.sh first)"

echo
echo "=== getdown-pro.jar ==="
stage "$REPO_ROOT/assets/sk/getdown-pro.jar" \
      "$APP_DIR/libs/getdown-pro.jar" || \
    echo "  (place getdown-pro.jar in assets/sk/)"

echo
echo "done."
