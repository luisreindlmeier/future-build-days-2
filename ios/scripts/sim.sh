#!/bin/zsh
# Isolated simulator for Kairos: its own CoreSimulator device set, headless,
# invisible to `simctl ... booted` and to other agents using the default set. `test` is the
# exception: it needs a simulator of the default set, since xcodebuild sees no other.
set -euo pipefail

ROOT="${0:A:h:h}"
# KAIROS_SIM_SET gives a session its own device set, so parallel agents never share a simulator.
SET="${KAIROS_SIM_SET:-$ROOT/.build/simulators}"
NAME="Kairos iPhone 17 Pro"
TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
# SIM_DEVICE=pad runs the same commands on an iPad, for the branch terminal.
if [[ "${SIM_DEVICE:-phone}" == "pad" ]]; then
  NAME="Kairos iPad Air"
  TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M2"
fi
BUNDLE_ID="com.luisreindlmeier.kairos"
DD="$ROOT/.build/dd"
APP="$DD/Build/Products/Debug-iphonesimulator/Kairos.app"

sim() { xcrun simctl --set "$SET" "$@"; }

device_id() {
  mkdir -p "$SET"
  local id
  id=$(sim list devices -j | python3 -I -c "import json, sys; d = json.load(sys.stdin)['devices']; print(next((x['udid'] for r in d.values() for x in r if x['name'] == sys.argv[1]), ''))" "$NAME")
  [[ -n "$id" ]] || id=$(sim create "$NAME" "$TYPE" "$RUNTIME")
  echo "$id"
}

boot() {
  local id
  id=$(device_id)
  sim bootstatus "$id" -b >/dev/null
  echo "$id"
}

build() {
  cd "$ROOT"
  xcodegen generate --quiet
  mkdir -p "$ROOT/.build"
  local log="$ROOT/.build/build.log" code=0
  xcodebuild -project Kairos.xcodeproj -scheme Kairos \
    -destination 'generic/platform=iOS Simulator' -configuration Debug \
    -derivedDataPath "$DD" ARCHS=arm64 build >"$log" 2>&1 || code=$?
  grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" "$log" | grep -v appintents || true
  return $code
}

# Launches one design screen (see Kairos/Router.swift) and saves a screenshot.
# APP_LANGUAGE=de shows it in German (the launch argument sets the app language for that run); APP_ARGS passes
# more launch arguments, any UserDefaults key for that run ("-practiceBackground photo-cocora").
shot_screen() {
  local id=$1 screen=$2 out=$3
  # Arrays, so zsh passes an argument and its value as two words.
  local -a language=() more=(${=APP_ARGS:-})
  [[ -n "${APP_LANGUAGE:-}" ]] && language=(-appLanguage "$APP_LANGUAGE")
  sim launch --terminate-running-process "$id" "$BUNDLE_ID" -screen "$screen" "${language[@]}" "${more[@]}" >/dev/null
  sleep "${SHOT_DELAY:-2.5}"
  sim io "$id" screenshot "$out" >/dev/null 2>&1
  echo "$out"
}

case "${1:-}" in
  build)
    build
    ;;
  run)
    shift
    id=$(boot)
    build
    sim install "$id" "$APP"
    sim launch --terminate-running-process "$id" "$BUNDLE_ID" "$@"
    ;;
  install)
    id=$(boot)
    sim install "$id" "$APP"
    ;;
  shot)
    id=$(boot)
    sim io "$id" screenshot "${2:-$ROOT/.build/screenshot.png}" >/dev/null 2>&1
    echo "${2:-$ROOT/.build/screenshot.png}"
    ;;
  screens)
    # scripts/sim.sh screens <out dir> <screen> [<screen> ...]
    out=$2; shift 2
    mkdir -p "$out"
    id=$(boot)
    sim status_bar "$id" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
    for screen in "$@"; do
      shot_screen "$id" "$screen" "$out/$screen.png"
    done
    ;;
  record)
    # scripts/sim.sh record <out.mp4> <screen> [seconds]: records the first seconds of a design screen
    # Python drives the recorder: a zsh background job would ignore the SIGINT that stops it.
    out=$2; screen=$3; seconds=${4:-8}
    id=$(boot)
    python3 -I - "$SET" "$id" "$BUNDLE_ID" "$out" "$screen" "$seconds" <<'PY'
import signal, subprocess, sys, time
device_set, device, bundle, out, screen, seconds = sys.argv[1:7]
simctl = ["xcrun", "simctl", "--set", device_set]
recorder = subprocess.Popen(simctl + ["io", device, "recordVideo", "--codec", "h264", "--force", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
subprocess.run(simctl + ["launch", "--terminate-running-process", device, bundle, "-screen", screen], stdout=subprocess.DEVNULL, check=True)
time.sleep(float(seconds))
recorder.send_signal(signal.SIGINT)
recorder.wait(timeout=60)
print(out)
PY
    ;;
  memory)
    # scripts/sim.sh memory <screen> [seconds]: prints the app's memory footprint while a screen is shown
    screen=$2; seconds=${3:-10}
    id=$(boot)
    log="$ROOT/.build/memory-$screen.log"
    sim launch --console --terminate-running-process "$id" "$BUNDLE_ID" -screen "$screen" -logMemory 1 >"$log" 2>&1 &
    console=$!
    sleep "$seconds"
    kill "$console" 2>/dev/null || true
    sim terminate "$id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    grep "memory footprint" "$log" | tail -4 || echo "no footprint lines in $log"
    ;;
  test)
    # scripts/sim.sh test: runs the unit tests (KairosTests) on "Kairos Tests", a simulator of the default
    # device set, the only set xcodebuild can see; its own derived data keeps the app build untouched.
    cd "$ROOT"
    xcodegen generate --quiet
    id=$(xcrun simctl list devices -j | python3 -I -c "import json, sys; d = json.load(sys.stdin)['devices']; print(next((x['udid'] for r in d.values() for x in r if x['name'] == sys.argv[1]), ''))" "Kairos Tests")
    [[ -n "$id" ]] || id=$(xcrun simctl create "Kairos Tests" "$TYPE" "$RUNTIME")
    log="$ROOT/.build/test.log"
    xcodebuild test -project Kairos.xcodeproj -scheme Kairos \
      -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$DD-tests" >"$log" 2>&1 \
      || { grep -E "✘|error:|failed" "$log" | head -40; exit 1; }
    grep -E "Test run" "$log" | tail -1
    ;;
  ui)
    # scripts/sim.sh ui light|dark: toggles appearance for checks
    id=$(boot)
    sim ui "$id" appearance "${2:-light}"
    ;;
  shutdown)
    sim shutdown all
    ;;
  clean)
    # Removes the simulator through CoreSimulator first; deleting the folder alone leaves a stale device behind.
    sim shutdown all >/dev/null 2>&1 || true
    sim delete all >/dev/null 2>&1 || true
    rm -rf "$SET" "$DD"
    ;;
  *)
    echo "usage: scripts/sim.sh build | run [launch args] | install | shot [file] | screens <dir> <screen>... | record <out.mp4> <screen> [seconds] | memory <screen> [seconds] | test | ui light|dark | shutdown | clean"
    exit 1
    ;;
esac
