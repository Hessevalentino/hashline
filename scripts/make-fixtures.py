#!/usr/bin/env python3
"""Generates the test corpus in Fixtures/. Small files are committed; large ones
(Fixtures/generated/) are rebuilt deterministically and ignored by git."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "Fixtures"
generated = root / "generated"
generated.mkdir(parents=True, exist_ok=True)

SAMPLE = """# Hashline

Příliš **žluťoučký** kůň úpěl *ďábelské* ódy. Inline `kód`, [odkaz](https://example.com) a ~~škrt~~.

## Seznam

- první položka
- druhá položka
  - vnořená
- [ ] úkol
- [x] hotový úkol

> Citace s **tučným** textem.

```swift
let greeting = "Ahoj"
```

---

| Sloupec | Hodnota |
|---------|--------:|
| a       | 1       |

Emoji 🙂 a znaky mimo BMP 𝒳.
"""

def write(name: str, data: bytes) -> None:
    (root / name).write_bytes(data)

write("small.md", SAMPLE.encode())
write("crlf.md", SAMPLE.replace("\n", "\r\n").encode())
write("cr.md", SAMPLE.replace("\n", "\r").encode())
write("mixed-endings.md", b"line lf\nline crlf\r\nline cr\rend\n")
write("utf8-bom.md", b"\xef\xbb\xbf" + SAMPLE.encode())
write("utf16le-bom.md", b"\xff\xfe" + SAMPLE.encode("utf-16-le"))
write("utf16be-bom.md", b"\xfe\xff" + SAMPLE.encode("utf-16-be"))
latin = SAMPLE.replace("🙂", ":)").replace("𝒳", "X")
write("cp1250.md", latin.encode("cp1250"))
write("no-trailing-newline.md", SAMPLE.rstrip("\n").encode())
write("trailing-whitespace.md", b"trailing spaces   \nhard break  \n\t\ttabs\t\n\n\n")
write("empty.md", b"")

CODE = """# Code

```swift
struct Greeting {
    let text = "Ahoj 🙂"  // pozdrav
    func show() -> Int { return 42 }
}
```

```python
def area(r: float) -> float:
    \"\"\"Circle area.\"\"\"
    return 3.14159 * r ** 2
```

```javascript
const items = [1, 2, 3].map((x) => x * 2);
console.log(`Total: ${items.length}`);
```

```bash
for f in *.md; do echo "$f"; done
```

```unknownlang
plain text stays uncoloured
```
"""
write("code.md", CODE.encode())

EXTENDED = """---
title: Rozšířená syntaxe
tags: [hashline, test]
---

[toc]

# Tabulky

| Název | Cena | Stav |
|:------|-----:|:----:|
| Kůň | 120 | ✓ |
| Žluťoučký | 3 | ✗ |

# Poznámky

Text s poznámkou[^1] a emoji :rocket: :tada:.

[^1]: Toto je poznámka pod čarou.

## HTML

<kbd>⌘</kbd> + <kbd>S</kbd> uloží, <mark>zvýraznění</mark> a <script>alert(1)</script>.

<details><summary>Více</summary>Skrytý text.</details>
"""
write("extended.md", EXTENDED.encode())

MATH = r"""# Matematika a diagramy

Einsteinova rovnice $E = mc^2$ a zlomek $\frac{a}{b}$ v textu. Cena $5 a $10 zůstane textem.

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

```math
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
```

```mermaid
flowchart LR
    A[Napsat] --> B{Hotovo?}
    B -- ano --> C[Uložit]
    B -- ne --> A
```

```mermaid
sequenceDiagram
    Autor->>Hashline: píše
    Hashline-->>Autor: náhled
```

```mermaid
flowchart LR
    A[Napsat] --> B{Hotovo?}
    B -- ano --> C[Uložit]
    B -- ne --> A
```
"""
write("math-mermaid.md", MATH.encode())

def large(name: str, size: int) -> None:
    chunks, total, i = [], 0, 0
    while total < size:
        chunk = SAMPLE.replace("# Hashline", f"# Kapitola {i}") + "\n"
        chunks.append(chunk)
        total += len(chunk.encode())
        i += 1
    (generated / name).write_bytes("".join(chunks).encode())

# 100 local images (small PNGs) for the lazy-loading budget in F4.
import struct, zlib
def png(width, height, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
images = generated / "images"
images.mkdir(exist_ok=True)
lines = ["# 100 obrázků\n"]
for i in range(100):
    (images / f"img{i:03}.png").write_bytes(png(320, 200, ((i * 37) % 256, (i * 91) % 256, 160)))
    lines.append(f"Obrázek {i}\n\n![obrázek {i}](images/img{i:03}.png)\n")
(generated / "many-images.md").write_text("\n".join(lines))

large("1mb.md", 1_000_000)
large("10mb.md", 10_000_000)
print(f"Fixtures written to {root}")
