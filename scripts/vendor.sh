#!/bin/zsh
# Rebuilds the vendored web libraries (versions pinned below; licences in Resources/Licenses).
#   highlight.js → HashlineCore/Resources/highlight.min.js (+ hljs CSS in app Styles)
#   KaTeX        → HashlineCore/Resources/katex.min.js, app Styles/katex-inline.css (fonts as data URLs)
#   Mermaid      → app Resources/mermaid.min.js.lzfse (LZFSE, unpacked on first diagram)
set -euo pipefail
ROOT=${0:A:h:h}
KATEX=0.18.9
MERMAID=12.0.0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -sSfL "https://registry.npmjs.org/katex/-/katex-$KATEX.tgz" | tar xz -C "$WORK"
mv "$WORK/package" "$WORK/katex"
cp "$WORK/katex/dist/katex.min.js" "$ROOT/Sources/HashlineCore/Resources/katex.min.js"
cp "$WORK/katex/LICENSE" "$ROOT/Sources/Hashline/Resources/Licenses/katex-LICENSE.txt"
python3 - "$WORK/katex/dist" "$ROOT/Sources/Hashline/Resources/Styles/katex-inline.css" <<'PY'
import base64, re, sys, pathlib
dist, out = pathlib.Path(sys.argv[1]), sys.argv[2]
css = (dist / "katex.min.css").read_text()
def inline(match):
    name = match.group(1)
    data = base64.b64encode((dist / "fonts" / f"{name}.woff2").read_bytes()).decode()
    return f'url(data:font/woff2;base64,{data}) format("woff2")'
# Keep only the woff2 source of each @font-face and inline it (the preview allows fonts only as data:).
css = re.sub(r'url\(fonts/([A-Za-z0-9_-]+)\.woff2\) format\("woff2"\)(,url\([^)]*\) format\("[a-z]+"\))*', inline, css)
pathlib.Path(out).write_text(css)
PY

curl -sSfL "https://registry.npmjs.org/mermaid/-/mermaid-$MERMAID.tgz" | tar xz -C "$WORK"
mv "$WORK/package" "$WORK/mermaid"
cp "$WORK/mermaid/LICENSE" "$ROOT/Sources/Hashline/Resources/Licenses/mermaid-LICENSE.txt"
swift - "$WORK/mermaid/dist/mermaid.min.js" "$ROOT/Sources/Hashline/Resources/mermaid.min.js.lzfse" <<'SWIFT'
import Foundation
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let compressed = try (input as NSData).compressed(using: .lzfse) as Data
try compressed.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("mermaid: \(input.count / 1024) KB → \(compressed.count / 1024) KB")
SWIFT
echo "KaTeX $KATEX, Mermaid $MERMAID vendored"
