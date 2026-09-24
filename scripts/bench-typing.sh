#!/bin/zsh
# Typing latency without XCTest: the app types into a copy of the 1 MB fixture itself
# (Profile build, launched in the background so it never takes the keyboard focus).
# Usage: scripts/bench-typing.sh [runs] [extra launch arguments…]
set -euo pipefail
ROOT=${0:A:h:h}
DD="$HOME/Library/Developer/Xcode/DerivedData/Hashline"
CONTAINER=~/Library/Containers/cz.hashline.Hashline/Data/tmp
RUNS=${1:-3}; shift || true
cd "$ROOT"
python3 scripts/make-fixtures.py >/dev/null
xcodebuild build -project Hashline.xcodeproj -scheme Hashline -configuration Profile -destination "platform=macOS" \
  -derivedDataPath "$DD" 2>&1 | grep -E "BUILD FAILED|: error:" && exit 1
APP="$DD/Build/Products/Profile/Hashline.app"
for run in $(seq 1 $RUNS); do
  mkdir -p "$CONTAINER"; cp Fixtures/generated/1mb.md "$CONTAINER/bench-1mb.md"
  pkill -x Hashline 2>/dev/null || true; while pgrep -x Hashline >/dev/null; do sleep 0.2; done
  start=$(date '+%Y-%m-%d %H:%M:%S')
  open -g -n -a "$APP" --args -ApplePersistenceIgnoreState YES -HashlineUITestDocument bench-1mb.md \
    -HashlineTypingBenchmark 200 "$@"
  while ! pgrep -x Hashline >/dev/null; do sleep 0.2; done
  while pgrep -x Hashline >/dev/null; do sleep 0.5; done
  echo "run $run: $(/usr/bin/log show --start "$start" --style compact --predicate 'subsystem == "cz.hashline.Hashline"' 2>/dev/null | grep -oE '(Typing latency|Keystroke processing).*' | tail -2 | tr '\n' ' ')"
done
