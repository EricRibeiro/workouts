#!/usr/bin/env bash
# PLAN 6.4: records one PerfDriverUITests scenario with xctrace on a pool simulator.
#
#   scripts/perf-record.sh [--build] <exercises|detail|history> [template] [out-dir]
#   python3 -I scripts/perf-analyze.py <out-dir>/<scenario>-<template>.trace        (the numbers)
#
# --build        first build an optimised Debug app + the UI test runner into .build/PerfDerivedData (see below).
# template       an xctrace template name (default: Time Profiler). The Hitches and Core Animation FPS instruments are
#                NOT supported on the simulator (the SwiftUI and Animation Hitches templates abort with "Hitches is not
#                supported on this platform"), and Frame Lifetimes records no usable timestamps there. The default adds
#                Core Animation Commits (the app-side commit durations stand in for hitches); the Hangs track comes free.
#                Run again with PERF_EXTRA_INSTRUMENTS=SwiftUI PERF_TAG=swiftui for view-body updates (SwiftUI combined
#                with Core Animation Commits hit a fatal modeler error).
# out-dir        where the .trace goes (default: .build/perf).
#
# Environment: PERF_SIM (a simulator name for `sim run --simulator`; default: any generic simulator),
#              PERF_WORKOUTS (default 600), PERF_EXTRA_INSTRUMENTS (comma-separated, "-" for none),
#              PERF_TAG (suffix for the trace name). The simulator comes from `sim run`.
#
# The script re-runs itself under simkit's `sim run`, so the simulator is leased, booted and shut down by simkit.
#
# Why an optimised *Debug* build: the harness (-uiTesting, -sampleWorkouts, in-memory store) is #if DEBUG, so a Release
# build cannot be driven. Overriding SWIFT_OPTIMIZATION_LEVEL=-O on the command line optimises the app and the statically
# linked WorkoutsKit while keeping the DEBUG flag; project settings and signing are untouched. ENABLE_PREVIEWS and
# ENABLE_DEBUG_DYLIB are off so the app's code lives in the main executable (symbols attribute to Workouts, not a stub).
#
# Why attach + atos: on the simulator xctrace leaves every address of an app that XCUITest launched unsymbolicated (no
# image list for the process; an app launched by simctl or by xctrace itself is fine, but then XCUITest cannot adopt it
# and relaunches it). So the script attaches to the app the test launched, writes its load address (vmmap) next to the
# trace, and perf-analyze.py resolves the app's own frames with atos against the dSYM. System frames stay addresses.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

ORIG_ARGS=("$@")
BUILD=0
[[ "${1:-}" == "--build" ]] && { BUILD=1; shift; }
SCENARIO="${1:?usage: perf-record.sh [--build] <exercises|detail|history> [template] [out-dir]}"
TEMPLATE="${2:-Time Profiler}"
OUT="${3:-.build/perf}"
DERIVED=".build/PerfDerivedData"

if [[ -z "${SIMKIT_UDID:-}" ]]; then
  SIM="${SIMKIT_HOME:-$HOME/Projects/simkit}/bin/sim"
  [[ -x "$SIM" ]] || { echo "perf: simkit's sim not found at $SIM (set SIMKIT_HOME)" >&2; exit 1; }
  exec "$SIM" run ${PERF_SIM:+--simulator "$PERF_SIM"} --note "perf-record $SCENARIO" -- "$SELF" "${ORIG_ARGS[@]}"
fi
UDID="$SIMKIT_UDID"

if ((BUILD)); then
  xcodebuild build-for-testing -scheme Workouts -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" -quiet \
    SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym 2>&1 | grep -E "error:|BUILD" | grep -v "exit code 0" || true
fi

mkdir -p "$OUT"
SAFE_TEMPLATE="${TEMPLATE// /-}"
BASE="$OUT/$SCENARIO-$SAFE_TEMPLATE${PERF_TAG:+-$PERF_TAG}"
TRACE="$BASE.trace"
GO="$(mktemp -u "${TMPDIR:-/tmp}/perf-go.XXXXXX")"
rm -rf "$TRACE" "$BASE.xcresult" "$GO"
XCT="" TEST=""
cleanup() {
  [[ -z "$XCT" ]] || kill -INT "$XCT" 2>/dev/null || true
  [[ -z "$TEST" ]] || kill "$TEST" 2>/dev/null || true
  rm -f "$GO"
}
trap cleanup EXIT

case "$SCENARIO" in
  exercises) TEST_ID="testExercisesListScroll" ;;
  detail) TEST_ID="testExerciseDetailCharts" ;;
  history) TEST_ID="testHistoryDashboardAndList" ;;
  *) echo "perf: unknown scenario $SCENARIO" >&2; exit 1 ;;
esac

xcrun simctl terminate "$UDID" com.ericribeiro.Workouts 2>/dev/null || true

# The test launches the app, then waits for $GO before driving it.
export TEST_RUNNER_PERF_DRIVER=1 TEST_RUNNER_PERF_SCENARIO="$SCENARIO" TEST_RUNNER_PERF_WORKOUTS="${PERF_WORKOUTS:-600}"
export TEST_RUNNER_PERF_GO_FILE="$GO"
XCTESTRUN=$(ls "$DERIVED"/Build/Products/*.xctestrun | head -1)
xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:"WorkoutsUITests/PerfDriverUITests/$TEST_ID" -parallel-testing-enabled NO \
  -resultBundlePath "$BASE.xcresult" >"$BASE.xcodebuild.log" 2>&1 &
TEST=$!

# Wait for the app (exact bundle id: the runner is com.ericribeiro.WorkoutsUITests.xctrunner).
PID=""
for _ in $(seq 1 240); do
  PID=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null |
    awk -v b="UIKitApplication:com.ericribeiro.Workouts[" 'index($3, b) == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }')
  [[ -n "$PID" ]] && break
  kill -0 "$TEST" 2>/dev/null || { echo "perf: test ended before the app launched; see $BASE.xcodebuild.log" >&2; exit 1; }
  sleep 0.5
done
[[ -n "$PID" ]] || { echo "perf: app never launched" >&2; exit 1; }
sleep 2
# The main executable's __TEXT is the first mapping: the load address atos needs.
vmmap "$PID" 2>/dev/null | awk '/^__TEXT/ && /Workouts.app\/Workouts$/ { split($2, a, "-"); print "0x" a[1]; exit }' >"$BASE.loadaddr" || true # awk exits early: vmmap gets SIGPIPE
echo "perf: app pid $PID, load address $(cat "$BASE.loadaddr"); recording '$TEMPLATE' -> $TRACE"

ARGS=(record --template "$TEMPLATE" --device "$UDID" --attach "$PID" --output "$TRACE" --no-prompt --time-limit 600s)
EXTRA_LIST="${PERF_EXTRA_INSTRUMENTS-Core Animation Commits}"
if [[ -n "$EXTRA_LIST" && "$EXTRA_LIST" != "-" ]]; then
  IFS=',' read -ra EXTRA <<<"$EXTRA_LIST"
  for i in "${EXTRA[@]}"; do ARGS+=(--instrument "$i"); done
fi
xctrace "${ARGS[@]}" >"$BASE.xctrace.log" 2>&1 &
XCT=$!
for _ in $(seq 1 60); do grep -q "Ctrl-C" "$BASE.xctrace.log" && break; sleep 0.5; done
sleep 3
touch "$GO"
wait "$TEST" || echo "perf: xcodebuild reported failure; see $BASE.xcodebuild.log" >&2
TEST=""
sleep 2
kill -INT "$XCT" 2>/dev/null || true
wait "$XCT" 2>/dev/null || true
XCT=""
echo "perf: done: $TRACE ($(du -sh "$TRACE" | cut -f1))"
