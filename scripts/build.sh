#!/usr/bin/env bash

# One command for the whole iOS build: the native components and jars, then the app. It is the
# "Build All", "Build Debug", "Build Release" and "Build TrollStore" tasks of .vscode/tasks.json.
#
#   ./scripts/build.sh                       Xcode debug build into out/artifacts/Payload (native parts built only when missing)
#   ./scripts/build.sh release               out/artifacts/SKapsule.ipa
#   ./scripts/build.sh trollstore            out/artifacts/*-trollstore.tipa (JIT entitlements)
#   ./scripts/build.sh --natives             rebuild every native component first (after a submodule bump)
#   ./scripts/build.sh --test --deploy       run the host tests, then install on DEVICE_ID and start it
#   ./scripts/build.sh release --version 1.0.1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

usage() {
    awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

MODE=debug
FORCE_NATIVES=0
RUN_TESTS=0
DEPLOY=0
MAKE_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        debug | release | trollstore) MODE="$1" ;;
        --natives) FORCE_NATIVES=1 ;;
        --test) RUN_TESTS=1 ;;
        --deploy) DEPLOY=1 ;;
        --version)
            [[ $# -ge 2 ]] || die "--version needs a value"
            MAKE_ARGS+=("SK_VERSION=$2")
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

[[ "$DEPLOY" == 0 || "$MODE" == debug ]] || die "--deploy installs the debug build only"
[[ "$(uname)" == Darwin ]] || die "the iOS build needs macOS and the Xcode command line tools"
command -v xcrun > /dev/null 2>&1 || die "xcrun not found: install Xcode"

# The Java parts of the natives need JDK 25; LWJGL's multi-release layer needs JDK 8.
# SK_JAVA_HOME / SK_JAVA8_HOME override the lookup; jenv, then the macOS java_home, are tried.
find_jdk() {
    local jenv_name="$1" mac_version="$2"
    jenv prefix "$jenv_name" 2> /dev/null && return
    /usr/libexec/java_home -v "$mac_version" 2> /dev/null && return
    return 1
}

JAVA_HOME="${SK_JAVA_HOME:-$(find_jdk 25 25 || true)}"
[[ -n "$JAVA_HOME" && -x "$JAVA_HOME/bin/java" ]] || die "JDK 25 not found: set SK_JAVA_HOME or add it to jenv"
export JAVA_HOME
export CACIO_JAVA_HOME="$JAVA_HOME"
export FRENCHPRESS_JAVA_HOME="$JAVA_HOME"
JAVA8_HOME="${SK_JAVA8_HOME:-$(find_jdk 1.8 1.8 || true)}"
export JAVA8_HOME

if [[ "$RUN_TESTS" == 1 ]]; then
    echo "=== host tests ==="
    make test
fi

# --- native components ---------------------------------------------------------------------

# submodule | main output | script. A component is built when its output is missing or --natives is given.
# frenchpress and the bootstrap are seconds of Maven or javac, so they are always rebuilt: the
# shared submodules change often.
NATIVES=(
    "gl4es|out/gl4es/libgl4es.dylib|build-gl4es-ios.sh"
    "openal-soft|out/openal/libopenal.dylib|build-openal-ios.sh"
    "lwjgl3|out/lwjgl3/lwjgl-3.4.1-ios-natives-arm64.zip|build-lwjgl3-ios.sh"
    "caciocavallo17|out/cacio/cacio-shared.jar|build-cacio-ios.sh"
)

for entry in "${NATIVES[@]}"; do
    IFS='|' read -r name output script <<< "$entry"
    if [[ "$FORCE_NATIVES" == 1 || ! -f "$output" ]]; then
        [[ -n "$(ls -A "external/$name" 2> /dev/null)" ]] \
            || die "external/$name is empty: git submodule update --init --recursive"
        if [[ "$name" == lwjgl3 && -z "$JAVA8_HOME" ]]; then
            die "JDK 8 not found (LWJGL needs it): set SK_JAVA8_HOME or add 1.8 to jenv"
        fi
        echo "=== $name ==="
        "./scripts/$script"
    else
        echo "=== $name: up to date ($output) ==="
    fi
done

echo "=== frenchpress ==="
./scripts/build-frenchpress-ios.sh
echo "=== bootstrap ==="
./scripts/build-bootstrap.sh

# --- app ------------------------------------------------------------------------------------

# Staging (scripts/stage-app-assets.sh) is part of `make payload`, so it is not run separately.
case "$MODE" in
    debug)
        if [[ "$DEPLOY" == 1 ]]; then
            make deploy ${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"}
        else
            make xcode-build ${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"}
        fi
        ;;
    release) make clean package RELEASE=1 ${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"} ;;
    trollstore) make clean package TROLLSTORE_JIT_ENT=1 ${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"} ;;
esac

echo
echo "Built:"
case "$MODE" in
    debug) ls -d out/artifacts/Payload/SKapsule.app ;;
    *) ls -lh out/artifacts/*.ipa out/artifacts/*.tipa 2> /dev/null || true ;;
esac
