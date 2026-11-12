#!/usr/bin/env bash

# Builds libskrppairing.a (Natives/RPPairing: on-device pairing for built-in JIT) for iOS arm64.
# Output: out/rppairing/libskrppairing.a, and the licence texts of the Rust crates it links in
# (out/rppairing/LICENSES-rppairing-crates.txt), which the app bundles.
#
# Needs rustup with the iOS target: rustup target add aarch64-apple-ios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATE="$REPO_ROOT/Natives/RPPairing"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out/rppairing}"
TARGET=aarch64-apple-ios

if ! command -v cargo > /dev/null; then
    # rustup's shims may not be on PATH in a non-login shell.
    CARGO="$(rustup which cargo 2> /dev/null || true)"
    [[ -n "$CARGO" ]] && export PATH="$(dirname "$CARGO"):$PATH"
fi
command -v cargo > /dev/null || {
    echo "ERROR: cargo not found (install rustup, then: rustup target add $TARGET)" >&2
    exit 1
}
rustup target list --installed 2> /dev/null | grep -qx "$TARGET" || rustup target add "$TARGET"

# Match the app's deployment target, or the linker warns on every object.
export IPHONEOS_DEPLOYMENT_TARGET=17.4
export CARGO_TARGET_DIR="$OUT_DIR/target"

(cd "$CRATE" && cargo build --release --locked --target "$TARGET")
mkdir -p "$OUT_DIR"
cp "$CARGO_TARGET_DIR/$TARGET/release/libskrppairing.a" "$OUT_DIR/libskrppairing.a"

# Every crate in the build, with the licence files shipped in its source.
(cd "$CRATE" && cargo metadata --locked --format-version 1 --filter-platform "$TARGET") |
    python3 -I "$SCRIPT_DIR/rppairing-notices.py" > "$OUT_DIR/LICENSES-rppairing-crates.txt"

echo
ls -la "$OUT_DIR/libskrppairing.a" "$OUT_DIR/LICENSES-rppairing-crates.txt"
