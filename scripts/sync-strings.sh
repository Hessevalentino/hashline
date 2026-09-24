#!/bin/zsh
# Updates the String Catalogs from the strings the compiler found (SWIFT_EMIT_LOC_STRINGS) and
# reports keys without a Czech translation. Run after UI text changes; translate in the .xcstrings.
set -euo pipefail
ROOT=${0:A:h:h}
DD="$HOME/Library/Developer/Xcode/DerivedData/Hashline"
cd "$ROOT"
xcodebuild build -project Hashline.xcodeproj -scheme Hashline -configuration Debug -destination "platform=macOS" \
  -derivedDataPath "$DD" 2>&1 | grep -E "BUILD FAILED|: error:" && exit 1
B="$DD/Build/Intermediates.noindex/Hashline.build/Debug"
sync() {
  local catalog=$1 target=$2 args=()
  for f in $(find "$B/$target.build" -name "*.stringsdata"); do args+=(--stringsdata "$f"); done
  xcrun xcstringstool sync "$catalog" "${args[@]}"
}
sync Sources/Hashline/Resources/Localizable.xcstrings Hashline
sync Sources/HashlineQuickLook/Localizable.xcstrings HashlineQuickLook
python3 - <<'PY'
import json
for path in ["Sources/Hashline/Resources/Localizable.xcstrings", "Sources/HashlineQuickLook/Localizable.xcstrings"]:
    strings = json.load(open(path))["strings"]
    missing = [k for k, v in strings.items()
               if v.get("shouldTranslate", True) and "cs" not in v.get("localizations", {})]
    print(f"{path}: {len(strings)} keys, {len(missing)} without Czech")
    for key in missing[:40]:
        print("  -", key.replace("\n", "\\n")[:100])
PY
