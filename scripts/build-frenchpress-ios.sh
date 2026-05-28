#!/usr/bin/env bash

# Builds frenchpress JAR. Pure Java — same build as Android.
# Output: out/frenchpress/frenchpress.jar

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRENCHPRESS_SRC="${FRENCHPRESS_SRC:-$REPO_ROOT/frenchpress}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/frenchpress}"
FRENCHPRESS_VERSION="0.1-SNAPSHOT"

[[ -f "$FRENCHPRESS_SRC/pom.xml" ]] || {
    echo "ERROR: frenchpress source not found at $FRENCHPRESS_SRC" >&2
    exit 1
}

if [[ -n "${FRENCHPRESS_JAVA_HOME:-}" ]]; then
    export JAVA_HOME="$FRENCHPRESS_JAVA_HOME"
fi
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
command -v mvn >/dev/null 2>&1 || { echo "ERROR: 'mvn' not on PATH" >&2; exit 1; }

JAVA_MAJOR="$("$JAVA_BIN" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')"
if [[ -z "$JAVA_MAJOR" || "$JAVA_MAJOR" -lt 25 ]]; then
    echo "ERROR: frenchpress needs JDK 25 (found '${JAVA_MAJOR:-?}')." >&2
    exit 1
fi
echo "Building frenchpress with JDK $JAVA_MAJOR"

( cd "$FRENCHPRESS_SRC" && mvn -B -DskipTests package )

mkdir -p "$OUT_DIR"
jar="$FRENCHPRESS_SRC/target/frenchpress-$FRENCHPRESS_VERSION.jar"
[[ -f "$jar" ]] || { echo "ERROR: $jar missing" >&2; exit 1; }

cp -v "$jar" "$OUT_DIR/frenchpress.jar"

echo
echo "=== done ==="
ls -lh "$OUT_DIR/frenchpress.jar"
