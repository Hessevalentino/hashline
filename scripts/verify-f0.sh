#!/bin/zsh
# F0 acceptance: open, edit (type + delete) and save every fixture in the real app,
# then require the saved file to be byte-identical to the original.
set -euo pipefail

ROOT=${0:A:h:h}
CONTAINER=~/Library/Containers/cz.hashline.Hashline/Data/tmp
cd "$ROOT"
python3 scripts/make-fixtures.py >/dev/null
mkdir -p "$CONTAINER"

typeset -a names originals
for f in Fixtures/*.md Fixtures/generated/*.md; do
  name="roundtrip-${f:t}"
  cp "$f" "$CONTAINER/$name"
  names+=$name; originals+=$f
done
cp Fixtures/generated/1mb.md "$CONTAINER/latency-1mb.md"
marker=$(mktemp); touch "$marker"; sleep 1

xcodegen generate >/dev/null
TEST_RUNNER_HASHLINE_ROUNDTRIP_FILES=${(j:,:)names} \
TEST_RUNNER_HASHLINE_LATENCY_FILE=latency-1mb.md \
xcodebuild test -project Hashline.xcodeproj -scheme Hashline -configuration "${CONFIGURATION:-Profile}" -destination "platform=macOS" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Hashline" -only-testing:HashlineUITests/RoundTripUITests ENABLE_TESTABILITY=YES 2>&1 \
  | grep -E "(TEST SUCCEEDED|TEST FAILED|error:)" || true

failed=0
for i in {1..${#names}}; do
  saved="$CONTAINER/${names[$i]}"
  if [[ ! "$saved" -nt "$marker" ]]; then
    echo "NOT SAVED  ${originals[$i]}"; failed=1
  elif cmp -s "${originals[$i]}" "$saved"; then
    echo "identical  ${originals[$i]}"
  else
    echo "DIFFERENT  ${originals[$i]}"; failed=1
  fi
done
rm -f "$marker"
exit $failed
