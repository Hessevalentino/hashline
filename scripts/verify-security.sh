#!/bin/zsh
# F10 checks through the real app (Debug build, launched in the background):
#  1. the XSS corpus (Fixtures/xss-corpus.md) rendered as export and as preview page, loaded with page
#     JavaScript ON and even without CSP: no vector may run; an unsanitized control vector must run;
#  2. hostile documents (Fixtures/hostile/*.md: deep nesting, math bombs) open without a crash.
set -euo pipefail
ROOT=${0:A:h:h}
DD="$HOME/Library/Developer/Xcode/DerivedData/Hashline"
CONTAINER=~/Library/Containers/cz.hashline.Hashline/Data/tmp
APP="$DD/Build/Products/Debug/Hashline.app"
cd "$ROOT"
xcodebuild build -project Hashline.xcodeproj -scheme Hashline -configuration Debug -destination "platform=macOS" \
  -derivedDataPath "$DD" 2>&1 | grep -E "BUILD FAILED|: error:" && exit 1
fail=0
mkdir -p "$CONTAINER"; cp Fixtures/xss-corpus.md "$CONTAINER/"
start=$(date '+%Y-%m-%d %H:%M:%S')
open -g -n -W "$APP" --args -ApplePersistenceIgnoreState YES -HashlineXSSTest xss-corpus.md
results=$(/usr/bin/log show --start "$start" --style compact --predicate 'subsystem == "cz.hashline.Hashline"' 2>/dev/null \
  | grep -oE 'XSS probe .*')
echo "$results"
if echo "$results" | grep -v control | grep -qE 'PWNED|handlers [1-9]|script elements [1-9]|js urls [1-9]'; then
  echo "FAIL  a vector ran or survived"; fail=1
else
  echo "ok    corpus inert"
fi
echo "$results" | grep -q 'control.*PWNED' && echo "ok    control vector ran (probe works)" || { echo "FAIL  control did not run"; fail=1; }
for file in Fixtures/hostile/*.md; do
  name=hostile-${file:t}
  cp "$file" "$CONTAINER/$name"
  open -g -n "$APP" --args -ApplePersistenceIgnoreState YES -HashlineUITestDocument "$name"
  sleep 6
  if pgrep -x Hashline >/dev/null; then echo "ok    ${file:t} opens"; else echo "FAIL  ${file:t} crashed"; fail=1; fi
  pkill -x Hashline || true; sleep 1
done
exit $fail
