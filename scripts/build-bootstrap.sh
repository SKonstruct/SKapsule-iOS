#!/usr/bin/env bash

# Compiles the bootstrap Java source into sk-bootstrap.jar.
# Requires JDK 25 and getdown-pro.jar on the classpath.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_SRC="$REPO_ROOT/external/bootstrap/src/main/java"
OUT_DIR="$REPO_ROOT/out/bootstrap"
BUILD_DIR="$OUT_DIR/classes"

# getdown-pro.jar is needed at compile time (SkBootstrap references it)
GETDOWN_JAR="${GETDOWN_JAR:-$REPO_ROOT/assets/getdown-pro.jar}"
[[ -f "$GETDOWN_JAR" ]] || {
                             echo "ERROR: getdown-pro.jar not found at $GETDOWN_JAR" >&2
                                                                                          exit 1
}

JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
JAR_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}jar"

command -v "$JAVA_BIN" > /dev/null 2>&1 || {
                                            echo "ERROR: javac not found" >&2
                                                                               exit 1
}

echo "Compiling bootstrap Java source…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# Extract lwjgl modules to temp dir to get jars
LWJGL_ZIP="$REPO_ROOT/out/lwjgl3/lwjgl-3.4.1-ios-modules.zip"
FRENCHPRESS_JAR="$REPO_ROOT/out/frenchpress/frenchpress.jar"
mkdir -p "$OUT_DIR/lwjgl_tmp"
[[ -f "$LWJGL_ZIP" ]] && unzip -qo "$LWJGL_ZIP" -d "$OUT_DIR/lwjgl_tmp"

# Build classpath
CP="$GETDOWN_JAR"
[[ -f "$FRENCHPRESS_JAR" ]] && CP="$CP:$FRENCHPRESS_JAR"
if [[ -d "$OUT_DIR/lwjgl_tmp" ]]; then
    while IFS= read -r jar; do
        CP="$CP:$jar"
    done < <(find "$OUT_DIR/lwjgl_tmp" -name "*.jar")
fi

find "$BOOTSTRAP_SRC" -name "*.java" | xargs "$JAVA_BIN" \
    -d "$BUILD_DIR" \
    -cp "$CP" \
    --add-exports java.base/java.lang=ALL-UNNAMED \
    -source 25 -target 25

rm -rf "$OUT_DIR/lwjgl_tmp"

echo "Packaging sk-bootstrap.jar…"
"$JAR_BIN" cf "$OUT_DIR/sk-bootstrap.jar" -C "$BUILD_DIR" .

echo
echo "=== done ==="
ls -lh "$OUT_DIR/sk-bootstrap.jar"
