#!/bin/zsh
# Exports a fixture to every format through the app (Debug build, launched in the background)
# and checks the results: HTML without scripts and with diagrams, PDF with bookmarks, PNG.
# Pandoc formats run only with a path: scripts/verify-export.sh /opt/homebrew/bin/pandoc
# (the sandbox must be able to read it; without a user choice it normally cannot).
set -euo pipefail
ROOT=${0:A:h:h}
DD="$HOME/Library/Developer/Xcode/DerivedData/Hashline"
CONTAINER=~/Library/Containers/cz.hashline.Hashline/Data/tmp
cd "$ROOT"
xcodebuild build -project Hashline.xcodeproj -scheme Hashline -configuration Debug -destination "platform=macOS" \
  -derivedDataPath "$DD" 2>&1 | grep -E "BUILD FAILED|: error:" && exit 1
mkdir -p "$CONTAINER/expdoc"; rm -rf "$CONTAINER/exp"
cat Fixtures/extended.md Fixtures/math-mermaid.md Fixtures/code.md > "$CONTAINER/expdoc/doc.md"
extra=()
[[ -n "${1:-}" ]] && extra=(-HashlinePandocPath "$1")
open -g -n "$DD/Build/Products/Debug/Hashline.app" --args -ApplePersistenceIgnoreState YES \
  -HashlineUITestDocument expdoc/doc.md -HashlineExportTest exp "${extra[@]}"
sleep 2; for i in {1..60}; do pgrep -x Hashline >/dev/null || break; sleep 1; done; pkill -x Hashline || true
out="$CONTAINER/exp"
fail=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi }
check "HTML exists"            "[[ -s $out/export.html ]]"
check "HTML has no scripts"    "! grep -q '<script' $out/export.html"
check "HTML embeds diagrams"   "grep -q 'hashline-mermaid-1' $out/export.html"
check "HTML keeps KaTeX"       "grep -q 'class=\"katex' $out/export.html"
check "PDF has bookmarks"      "[[ \$(swift scripts/pdf-outline.swift $out/export.pdf | grep -c ' -> p') -ge 3 ]]"
check "PNG exists"             "[[ -s $out/export.png ]]"
if [[ -n "${1:-}" ]]; then
  for ext in docx odt rtf epub tex wiki rst; do check "Pandoc $ext" "[[ -s $out/export.$ext ]]"; done
fi
/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "cz.hashline.Hashline"' 2>/dev/null \
  | grep -oE 'Export [a-z-]+: [0-9]+ ms' || true
exit $fail
