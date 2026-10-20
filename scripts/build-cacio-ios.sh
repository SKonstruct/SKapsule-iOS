#!/usr/bin/env bash

# Builds caciocavallo17 JARs. Pure Java — same build as Android.
# Output: out/cacio/cacio-shared.jar, out/cacio/cacio-tta.jar

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACIO_SRC="${CACIO_SRC:-$REPO_ROOT/external/caciocavallo17}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/cacio}"
CACIO_VERSION="1.18-SNAPSHOT"

[[ -f "$CACIO_SRC/pom.xml" ]] || {
    echo "ERROR: caciocavallo17 source not found at $CACIO_SRC" >&2
    echo "       Did you 'git submodule update --init caciocavallo17'?" >&2
    exit 1
}

if [[ -z "${JAVA_HOME:-}" ]]; then
    export JAVA_HOME="$(jenv prefix zulu64-25.0.3 2> /dev/null || jenv prefix 25 2> /dev/null || echo "")"
fi
if [[ -n "${CACIO_JAVA_HOME:-}" ]]; then
    export JAVA_HOME="$CACIO_JAVA_HOME"
fi
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
command -v mvn > /dev/null 2>&1 || {
                                    echo "ERROR: 'mvn' not on PATH" >&2
                                                                         exit 1
}

# Verify the build JDK is 25+; the java-25 branch adapts to JDK 25 internals
# (e.g. removed SurfaceManager) and won't compile/run correctly on older JDKs.
JAVA_MAJOR="$("$JAVA_BIN" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')"
if [[ -z "$JAVA_MAJOR" || "$JAVA_MAJOR" -lt 25 ]]; then
    echo "ERROR: cacio java-25 branch needs JDK 25 to build (found '${JAVA_MAJOR:-?}')." >&2
    echo "       Point CACIO_JAVA_HOME at a JDK 25." >&2
    exit 1
fi
echo "Building cacio with JDK $JAVA_MAJOR (${JAVA_HOME:-system default})"

( cd "$CACIO_SRC" && mvn -B -DskipTests \
    -Dmaven.javadoc.skip=true -Dmaven.source.skip=true \
    package )

mkdir -p "$OUT_DIR"
for mod in cacio-shared cacio-tta; do
    jar="$CACIO_SRC/$mod/target/$mod-$CACIO_VERSION.jar"
    [[ -f "$jar" ]] || {
                         echo "ERROR: $jar missing" >&2
                                                         exit 1
    }
    cp -v "$jar" "$OUT_DIR/$mod.jar"
done

echo
echo "=== done ==="
ls -lh "$OUT_DIR/cacio-shared.jar" "$OUT_DIR/cacio-tta.jar"
