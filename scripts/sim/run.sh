#!/usr/bin/env bash

# Installs the simulator build (scripts/sim/build.sh), launches it, taps Launch, waits for the game's
# first frame, and reads everything back from the app's container: logs, screenshots, a summary.
# The exit status is 0 only when the launcher UI came up and the game rendered with no crash.
#
#   scripts/sim/run.sh                  # launcher, then the game up to its first frame
#   scripts/sim/run.sh --launcher-only  # stop at the launcher screen
#   scripts/sim/run.sh --fresh          # uninstall first: forgets the downloaded game and settings
#   scripts/sim/run.sh --wait 240       # seconds to wait for the first frame (default 150)
#   SK_SIM_DEVICE="iPhone 17e" scripts/sim/run.sh
#
# Output: build/sim/runs/<time>/ (summary.txt, launcher.png, game.png, latestlog.txt, vmlog-*.log,
# hs_err*.log, crash reports). The game is downloaded on the first launch (getdown), so that one is
# slower; later runs keep it unless --fresh. Needs idb (idb_companion) to tap Launch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/build/sim/SKapsule.app"
BUNDLE=com.skonstruct.skapsule
DEVICE="${SK_SIM_DEVICE:-iPhone 18 Pro Max}"
WAIT=150
LAUNCHER_ONLY=0
FRESH=0

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --launcher-only) LAUNCHER_ONLY=1; shift;;
        --fresh) FRESH=1; shift;;
        --wait) WAIT="$2"; shift 2;;
        *) die "unknown option $1";;
    esac
done
[ -d "$APP" ] || die "no $APP: run scripts/sim/build.sh"

OUT="$ROOT/build/sim/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# --- the simulator -----------------------------------------------------------------------------
UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | grep -o '[0-9A-F]\{8\}-[0-9A-F-]\{27\}' | head -1 || true)"
[ -n "$UDID" ] || die "no simulator named '$DEVICE' (xcrun simctl list devices available; SK_SIM_DEVICE=...)"
if ! xcrun simctl list devices booted | grep -q "$UDID"; then
    say "booting $DEVICE"
    xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b > /dev/null
RUNTIME="$(xcrun simctl list devices available | awk -v u="$UDID" '/^-- /{r=$0} index($0,u){print r; exit}' | tr -d '-' | xargs)"

[ "$FRESH" = 1 ] && xcrun simctl uninstall "$UDID" "$BUNDLE" 2> /dev/null || true
xcrun simctl terminate "$UDID" "$BUNDLE" 2> /dev/null || true
say "installing"
xcrun simctl install "$UDID" "$APP"
D="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"
rm -f "$D"/latestlog.txt "$D"/vmlog-*.log "$D"/hs_err*.log 2> /dev/null || true

# --- idb, to tap Launch ------------------------------------------------------------------------
COMPANION_PID=""
cleanup() { [ -n "$COMPANION_PID" ] && kill "$COMPANION_PID" 2> /dev/null || true; }
trap cleanup EXIT
if [ "$LAUNCHER_ONLY" = 0 ]; then
    command -v idb > /dev/null && command -v idb_companion > /dev/null || die "idb and idb_companion are needed to tap Launch (or use --launcher-only)"
    mkdir -p /tmp/idb
    idb_companion --udid "$UDID" --grpc-domain-sock "/tmp/idb/${UDID}_companion.sock" > "$OUT/idb-companion.log" 2>&1 &
    COMPANION_PID=$!
    sleep 3
fi

# The centre of the first accessibility element whose label contains $1, in points; fails if none.
find_label() {
    idb ui describe-all --udid "$UDID" 2> /dev/null | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    if sys.argv[1] in (e.get("AXLabel") or ""):
        f = e["frame"]; print(round(f["x"] + f["width"] / 2), round(f["y"] + f["height"] / 2)); sys.exit(0)
sys.exit(1)
' "$1" 2> /dev/null
}
tap_label() {
    local pt
    pt="$(find_label "$1")" || return 1
    # shellcheck disable=SC2086
    idb ui tap $pt --udid "$UDID" > /dev/null
}

# --- launcher ----------------------------------------------------------------------------------
say "launching on $DEVICE ($RUNTIME)"
xcrun simctl launch "$UDID" "$BUNDLE" > "$OUT/launch.txt" 2>&1 || { cat "$OUT/launch.txt" >&2; die "launch failed"; }
LAUNCHER=no
for _ in $(seq 1 30); do
    sleep 1
    if [ "$LAUNCHER_ONLY" = 1 ]; then
        xcrun simctl io "$UDID" screenshot "$OUT/launcher.png" > /dev/null 2>&1 && LAUNCHER=yes
        pgrep -f "SKapsule.app/SKapsule" > /dev/null && break || LAUNCHER=no
    elif find_label "Launch" > /dev/null; then
        LAUNCHER=yes; break
    fi
done
sleep 1
xcrun simctl io "$UDID" screenshot "$OUT/launcher.png" > /dev/null 2>&1 || true
say "launcher UI: $LAUNCHER"

# --- the game ----------------------------------------------------------------------------------
STATE="not tried"
if [ "$LAUNCHER_ONLY" = 0 ] && [ "$LAUNCHER" = yes ]; then
    tap_label "Launch" || die "could not find the Launch button"
    say "waiting up to ${WAIT}s for the game's first frame"
    STATE=timeout
    for _ in $(seq 1 "$WAIT"); do
        sleep 1
        if grep -q "\[NativeBridge\] renderReady" "$D/latestlog.txt" 2> /dev/null; then STATE=rendered; break; fi
        pgrep -f "SKapsule.app/SKapsule" > /dev/null || { STATE=died; break; }
    done
    [ "$STATE" = rendered ] && sleep 3
    xcrun simctl io "$UDID" screenshot "$OUT/game.png" > /dev/null 2>&1 || true
fi
say "game: $STATE"

# --- read back ---------------------------------------------------------------------------------
for f in "$D"/latestlog.txt "$D"/vmlog-*.log "$D"/hs_err*.log; do if [ -f "$f" ]; then cp "$f" "$OUT/"; fi; done
: > "$OUT/crash-names.txt"
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'SKapsule*.ips' -newer "$OUT/launch.txt" 2> /dev/null | while read -r c; do
    cp "$c" "$OUT/" && basename "$c" >> "$OUT/crash-names.txt"
done || true
CRASHES="$(wc -l < "$OUT/crash-names.txt" | tr -d ' ')"
LOG="$OUT/latestlog.txt"
CODECACHE="$(grep -ho 'used: [0-9.]* MB' "$OUT"/vmlog-*.log 2> /dev/null | tail -1 || true)"

{
    echo "device: $DEVICE ($RUNTIME)   build: $(plutil -extract SKBuildStamp raw -o - "$APP/Info.plist")"
    echo "launcher UI: $LAUNCHER   game: $STATE   crash reports: $CRASHES"
    echo "---- JIT"
    grep -a "\[JIT\]\|\[JIT26\]" "$LOG" 2> /dev/null | cut -c1-160 | head -6 || true
    echo "code cache in use at last report: ${CODECACHE:-none}"
    echo "hs_err files: $(ls "$OUT"/hs_err*.log 2> /dev/null | wc -l | tr -d ' ')"
    echo "---- log tail"
    tail -8 "$LOG" 2> /dev/null | cut -c1-200 || true
    echo "---- sim-only: isJITEnabled() is YES without a debugger; DeviceHasTXM() is NO; no SKJITHelper or"
    echo "     StikJIT; JRE and LWJGL natives are device builds retagged for the simulator."
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"
say "everything is in $OUT"

[ "$LAUNCHER" = yes ] && [ "$CRASHES" = 0 ] && { [ "$LAUNCHER_ONLY" = 1 ] || [ "$STATE" = rendered ]; }
