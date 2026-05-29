#!/usr/bin/env bash

# Compiles the bootstrap Java source into sk-bootstrap.jar.
# Requires JDK 25 and getdown-pro.jar on the classpath.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_SRC="$REPO_ROOT/bootstrap/src/main/java"
OUT_DIR="$REPO_ROOT/out/bootstrap"
BUILD_DIR="$OUT_DIR/classes"

# getdown-pro.jar is needed at compile time (SkBootstrap references it)
GETDOWN_JAR="${GETDOWN_JAR:-$REPO_ROOT/assets/sk/getdown-pro.jar}"
[[ -f "$GETDOWN_JAR" ]] || { echo "ERROR: getdown-pro.jar not found at $GETDOWN_JAR" >&2; exit 1; }

JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
JAR_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}jar"

command -v "$JAVA_BIN" >/dev/null 2>&1 || { echo "ERROR: javac not found" >&2; exit 1; }

echo "Compiling bootstrap Java source…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

find "$BOOTSTRAP_SRC" -name "*.java" | xargs "$JAVA_BIN" \
    -d "$BUILD_DIR" \
    -cp "$GETDOWN_JAR" \
    --add-exports java.base/java.lang=ALL-UNNAMED \
    -source 17 -target 17

echo "Packaging sk-bootstrap.jar…"
"$JAR_BIN" cf "$OUT_DIR/sk-bootstrap.jar" -C "$BUILD_DIR" .

echo
echo "=== done ==="
ls -lh "$OUT_DIR/sk-bootstrap.jar"
