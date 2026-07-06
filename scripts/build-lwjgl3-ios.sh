#!/usr/bin/env bash

# Builds LWJGL 3 for iOS arm64 using the fork's ci_build_ios.bash.
# Output: out/lwjgl3/ (native dylibs + module JARs)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LWJGL_SRC="${LWJGL_SRC:-$REPO_ROOT/external/lwjgl3}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/lwjgl3}"

[[ -d "$LWJGL_SRC" ]] || { echo "ERROR: lwjgl3 source not found at $LWJGL_SRC" >&2; exit 1; }
[[ -f "$LWJGL_SRC/ci_build_ios.bash" ]] || { echo "ERROR: ci_build_ios.bash missing" >&2; exit 1; }

if [[ -z "${JAVA_HOME:-}" ]]; then
    export JAVA_HOME="$(jenv prefix zulu64-25.0.3 2>/dev/null || jenv prefix 25 2>/dev/null || echo "")"
fi
if [[ -z "${JAVA8_HOME:-}" ]]; then
    export JAVA8_HOME="$(jenv prefix zulu64-1.8.0.492 2>/dev/null || jenv prefix 1.8 2>/dev/null || echo "")"
fi

if [[ -z "${JAVA_HOME:-}" || ! -d "$JAVA_HOME" ]]; then
    echo "ERROR: JAVA_HOME is not set or invalid." >&2
    echo "       Please run ./scripts/setup-mac.sh to configure the environment." >&2
    exit 1
fi

if [[ -z "${JAVA8_HOME:-}" || ! -f "${JAVA8_HOME:-}/jre/lib/rt.jar" ]]; then
    echo "ERROR: JAVA8_HOME must point at a JDK 8 install (with jre/lib/rt.jar)." >&2
    echo "       Please run ./scripts/setup-mac.sh to configure the environment." >&2
    exit 1
fi

echo "lwjgl3 source: $LWJGL_SRC"
echo "Output dir:    $OUT_DIR"
echo

echo "=== running LWJGL iOS build ==="
( cd "$LWJGL_SRC" && bash ci_build_ios.bash )

NATIVES_SRC="$LWJGL_SRC/bin/out"
RELEASE_SRC="$LWJGL_SRC/bin/RELEASE"
mkdir -p "$OUT_DIR"

NATIVES_ZIP="$OUT_DIR/lwjgl-3.4.1-ios-natives-arm64.zip"
MODULES_ZIP="$OUT_DIR/lwjgl-3.4.1-ios-modules.zip"

echo
echo "=== packaging natives -> $NATIVES_ZIP ==="
[[ -d "$NATIVES_SRC" ]] || { echo "ERROR: $NATIVES_SRC missing" >&2; exit 1; }
rm -f "$NATIVES_ZIP"
( cd "$NATIVES_SRC" && zip -j "$NATIVES_ZIP" ./*.dylib )

echo
echo "=== packaging modules -> $MODULES_ZIP ==="
[[ -d "$RELEASE_SRC" ]] || { echo "ERROR: $RELEASE_SRC missing" >&2; exit 1; }
rm -f "$MODULES_ZIP"
( cd "$RELEASE_SRC" && zip -r "$MODULES_ZIP" . \
    -i '*.jar' '*license*' 'LICENSE' 'build.txt' \
    -x '*-natives-*' '*-sources.jar' )

echo
echo "=== done ==="
ls -lh "$NATIVES_ZIP" "$MODULES_ZIP"
