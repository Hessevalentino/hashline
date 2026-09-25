#!/bin/zsh
# Release: Release build (arm64, ad-hoc signed) → DMG → Sparkle EdDSA signature → appcast.xml →
# GitHub Release. Usage: scripts/release.sh <version> <build> "<notes line 1>" ["<notes line 2>" …]
# The version must match CFBundleShortVersionString/CFBundleVersion in Support/Info.plist.
# Ad-hoc signing (no Apple Developer account, decision 2026-09-24): users allow the app once in
# System Settings ▸ Privacy & Security ▸ Open Anyway. Sparkle verifies updates with EdDSA instead.
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
VERSION=${1:?version, e.g. 0.1.0}; BUILD=${2:?build number}; shift 2
NOTES=("$@")
REPO=Hessevalentino/hashline
DD="$HOME/Library/Developer/Xcode/DerivedData/Hashline"
OUT="$ROOT/build/release"
SPARKLE_BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"

plist_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
plist_build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Support/Info.plist)
[[ "$plist_version" == "$VERSION" && "$plist_build" == "$BUILD" ]] || {
  echo "Info.plist has $plist_version ($plist_build); set it to $VERSION ($BUILD) first." >&2; exit 1; }
grep -q "<sparkle:version>$BUILD</sparkle:version>" appcast.xml && { echo "Build $BUILD is already in appcast.xml" >&2; exit 1; }

echo "== Build"
xcodegen generate >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild clean build -project Hashline.xcodeproj -scheme Hashline -configuration Release \
  -destination "platform=macOS" -derivedDataPath "$DD" 2>&1 | grep -E "BUILD FAILED|: error:" && exit 1
APP="$DD/Build/Products/Release/Hashline.app"
ditto "$APP" "$OUT/Hashline.app"
xattr -cr "$OUT/Hashline.app"
codesign --verify --deep --strict "$OUT/Hashline.app"

echo "== DMG"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
ditto "$OUT/Hashline.app" "$STAGE/Hashline.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Hashline.dmg"
hdiutil create -volname "Hashline $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
codesign -s - "$DMG"

echo "== Sparkle signature"
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG")   # sparkle:edSignature="…" length="…"
echo "$SIGNATURE"

echo "== appcast.xml"
python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$REPO" "${NOTES[@]}" <<'PY'
import sys, html, email.utils
version, build, signature, repo, *notes = sys.argv[1:]
items = "".join(f"<li>{html.escape(n)}</li>" for n in notes) or "<li>Opravy a vylepšení.</li>"
item = f"""    <item>
      <title>Hashline {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="https://github.com/{repo}/releases/download/v{version}/Hashline.dmg" type="application/octet-stream" {signature} />
    </item>
"""
path = "appcast.xml"
text = open(path, encoding="utf-8").read()
marker = "    <language>cs</language>\n"
assert marker in text
open(path, "w", encoding="utf-8").write(text.replace(marker, marker + item, 1))
PY

echo "== GitHub"
git add appcast.xml Support/Info.plist CHANGELOG.md
git commit -m "Release $VERSION ($BUILD)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" || true
git tag -f "v$VERSION"
git push origin HEAD --tags
NOTES_TEXT=$(printf -- '- %s\n' "${NOTES[@]}")
# Quoted heredoc: the backticks are Markdown, not command substitution.
INSTALL_NOTE=$(cat <<'MD'
Aplikace je podepsaná ad-hoc (bez účtu Apple Developer), macOS stažený DMG napoprvé zablokuje. Nejrychleji: `xattr -d com.apple.quarantine ~/Downloads/Hashline.dmg`, pak DMG otevřít. Bez Terminálu: Nastavení systému ▸ Soukromí a zabezpečení ▸ Přesto otevřít (pro DMG i aplikaci). Podrobně v README.
MD
)
gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Hashline $VERSION" --notes "$NOTES_TEXT

$INSTALL_NOTE"
# raw.githubusercontent.com caches for up to 5 minutes; until then Sparkle still sees the old feed.
echo "== Waiting for the published appcast"
FEED=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" Support/Info.plist)
for _ in {1..40}; do
  curl -fsS -H "Cache-Control: no-cache" "$FEED" | grep -q "<sparkle:version>$BUILD</sparkle:version>" && break
  /bin/sleep 15
done
curl -fsS "$FEED" | grep -q "<sparkle:version>$BUILD</sparkle:version>" \
  && echo "Appcast serves build $BUILD: updates are live." || echo "Appcast still old after 10 min; check $FEED" >&2
echo "Done: https://github.com/$REPO/releases/tag/v$VERSION"
