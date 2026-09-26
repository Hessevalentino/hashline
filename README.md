<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Ikona aplikace Hashline">
</p>

<h1 align="center">Hashline</h1>

<p align="center">
  <strong>Nativní markdown editor pro macOS.</strong><br>
  Vlevo zdroj se zvýrazněnou syntaxí, vpravo živý HTML náhled. Obyčejné soubory <code>.md</code>, žádná databáze, žádný účet.
</p>

<p align="center">
  <a href="https://github.com/Hessevalentino/hashline/releases/latest"><img src="https://img.shields.io/github/v/release/Hessevalentino/hashline?label=verze&color=DF4A29" alt="Poslední verze"></a>
  <a href="https://github.com/Hessevalentino/hashline/releases"><img src="https://img.shields.io/github/downloads/Hessevalentino/hashline/total?label=sta%C5%BEeno&color=DF4A29" alt="Počet stažení"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-MIT-2ea44f" alt="Licence MIT"></a>
  <img src="https://img.shields.io/badge/open%20source-%E2%9C%93-2ea44f" alt="Open source">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14 a novější">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-000000?logo=apple&logoColor=white" alt="Apple Silicon">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-%2B%20AppKit-0A84FF?logo=swift&logoColor=white" alt="SwiftUI a AppKit">
  <img src="https://img.shields.io/badge/Markdown-CommonMark%20%2B%20GFM-000000?logo=markdown&logoColor=white" alt="CommonMark a GFM">
  <img src="https://img.shields.io/badge/sandbox-ano-555555?logo=apple&logoColor=white" alt="App Sandbox">
  <img src="https://img.shields.io/badge/telemetrie-%C5%BE%C3%A1dn%C3%A1-555555" alt="Bez telemetrie">
  <img src="https://img.shields.io/badge/jazyk-%C4%8De%C5%A1tina%20%C2%B7%20English-555555" alt="Čeština a angličtina">
</p>

<p align="center">
  <a href="https://github.com/Hessevalentino/hashline/releases/latest/download/Hashline.dmg"><strong>Stáhnout DMG</strong></a>
  &nbsp;·&nbsp;
  <a href="https://hashline.hesse.works/">Web projektu</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Změny</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/screenshot-dark.png">
  <img src="docs/images/screenshot-light.png" alt="Hashline: vlevo zdroj Markdownu se zvýrazněnou syntaxí, vpravo vykreslený náhled s tabulkou, kódem a matematikou">
</picture>

## Obsah

- [Proč Hashline](#proč-hashline)
- [Stažení a instalace](#stažení-a-instalace)
- [Funkce](#funkce)
- [Technologie](#technologie)
- [Výkon](#výkon)
- [Sestavení ze zdrojů](#sestavení-ze-zdrojů)
- [Licence](#licence)

## Proč Hashline

- **Píše se, nic se nenastavuje.** Otevře se okamžitě, ukáže text a pak nepřekáží.
- **Soubor je pravda.** Pracuje s obyčejnými `.md` na disku. Žádný vlastní formát ani databáze.
- **Nativní.** Swift, AppKit a TextKit 2, žádný Electron. Světlý i tmavý režim, zkratky, Undo, Služby, Quick Look.
- **Rychlý.** Psaní pod 10 ms i v 1MB dokumentu, otevření 1MB souboru zhruba za 0,2 s. Měří se, neodhaduje ([docs/perf.md](docs/perf.md)).
- **Bezpečný a soukromý.** Sandbox, náhled bez JavaScriptu stránky, sanitizace HTML, žádná telemetrie. Asistent AI je jen volitelný a bez vašeho klíče nic neposílá.

## Stažení a instalace

Požadavky: **macOS 14 Sonoma** nebo novější, Mac s **Apple Silicon**.

Hashline je podepsaný jen ad-hoc (bez placeného účtu Apple Developer), takže macOS stažený soubor napoprvé zablokuje s hláškou, že ho nelze ověřit. Nejrychlejší je jeden příkaz v Terminálu, nebo povolení v Nastavení systému.

**Rychle přes Terminál** (doporučeno):

1. Stáhněte [`Hashline.dmg`](https://github.com/Hessevalentino/hashline/releases/latest/download/Hashline.dmg).
2. Odstraňte příznak „staženo z internetu“:

   ```sh
   xattr -d com.apple.quarantine ~/Downloads/Hashline.dmg
   ```

3. Otevřete DMG a přetáhněte Hashline do složky **Aplikace**. Spustí se bez dalších dotazů.

**Bez Terminálu, přes Nastavení systému:**

1. Dvakrát klikněte na `Hashline.dmg`. V hlášce, že soubor nelze ověřit, klikněte na **Hotovo** (ne na „Přesunout do koše“).
2. Otevřete **Nastavení systému ▸ Soukromí a zabezpečení**, sjeďte dolů do části **Zabezpečení** a u hlášky o `Hashline.dmg` klikněte na **Přesto otevřít**. Potvrďte heslem nebo Touch ID. Tlačítko se ukazuje zhruba hodinu po pokusu o otevření.
3. Otevřete DMG znovu, v dialogu klikněte na **Otevřít** a přetáhněte Hashline do složky **Aplikace**.
4. Při prvním spuštění Hashline zopakujte kroky 1–2 pro aplikaci (**Přesto otevřít** u „Hashline“). Pak se spouští normálně.

Když už aplikaci máte v Aplikacích a macOS ji blokuje, pomůže i `xattr -dr com.apple.quarantine /Applications/Hashline.app`.

**Aktualizace:** při druhém spuštění se Hashline zeptá, jestli má jednou týdně hledat nové verze ([Sparkle](https://sparkle-project.org)). Aktualizace jsou podepsané klíčem EdDSA, takže se nainstaluje jen verze z tohoto projektu, a další povolení v Nastavení systému už nevyžadují. Ručně: **Hashline ▸ Vyhledat aktualizace…**

## Funkce

| | |
|---|---|
| ✍️ **Editor** | TextKit 2, zvýraznění Markdownu i bloků kódu (36 nejběžnějších jazyků), formátovací lišta, chytré seznamy, úprava tabulek tabulátorem |
| 👁️ **Náhled** | GFM tabulky, úkoly, poznámky pod čarou, `[toc]`, emoji, matematika (KaTeX), diagramy (Mermaid), lokální i vzdálené obrázky, synchronní scrollování |
| 🗂️ **Knihovna** | Složka dokumentů, strom složek, osnova, hledání v knihovně ⇧⌘F, rychlé otevření ⌘P, najít a nahradit s regexem, přesun do koše (pravé tlačítko nebo ⌘⌫) |
| 🎨 **Vzhled** | Přepínač ☀︎ / ☾ v liště, témata `theme.json` + `theme.css` (Paper, Tomorrow Night, Solarized), písmo, výška řádku, šířka textu |
| 📖 **Čtení** | Tlačítko s knížkou v liště (⌘/): jen vykreslený dokument jako čitelná stránka, bez zdrojového kódu |
| 🧘 **Režimy** | Soustředění F8, psací stroj F9, stavový řádek se slovy, znaky a dobou čtení |
| 📤 **Export** | Markdown (kopie kamkoli), HTML, PDF se záložkami, PNG, přes [Pandoc](https://pandoc.org) DOCX, ODT, RTF, ePub, LaTeX, MediaWiki, RST, import přes Pandoc |
| 🍎 **macOS** | Quick Look pro `.md` ve Finderu, Služby („Nový dokument Hashline s výběrem“), Sdílení, čeština a angličtina, přístupnost |
| 🤖 **Asistent AI** | Volitelný, ve výchozím stavu vypnutý (Nastavení ▸ Obecné ▸ Pokročilé). Chat u každého dokumentu s Claude, OpenAI nebo DeepSeek na vlastní klíč API (uložený jen v Klíčence), nebo s lokálním modelem v Ollamě či LM Studiu, kdy text neopustí Mac. Na požádání rovnou upravuje text, každý pokyn jde vrátit jedním ⌘Z, volitelná rešerše na webu se zdroji. Vidí jen svůj dokument. |
| 🔒 **Bezpečnost** | App Sandbox, CSP, allow-list sanitizace HTML, test proti 77 XSS vektorům, ochrana proti nepřátelským dokumentům |

## Technologie

<p>
  <img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/JavaScript-F7DF1E?logo=javascript&logoColor=black" alt="JavaScript">
  <img src="https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white" alt="HTML5">
  <img src="https://img.shields.io/badge/CSS3-1572B6?logo=css3&logoColor=white" alt="CSS3">
  <img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Shell-4EAA25?logo=gnubash&logoColor=white" alt="Shell">
  <img src="https://img.shields.io/badge/Xcode-147EFB?logo=xcode&logoColor=white" alt="Xcode">
  <img src="https://img.shields.io/badge/Markdown-000000?logo=markdown&logoColor=white" alt="Markdown">
</p>

| Oblast | Použito |
|---|---|
| Jazyk a UI | Swift 6 (strict concurrency), SwiftUI pro okna a nastavení, AppKit (`NSTextView`, `NSToolbar`) |
| Editor | TextKit 2, inkrementální parsování po blocích, stylování jen viditelné oblasti |
| Markdown | [swift-markdown](https://github.com/swiftlang/swift-markdown) (cmark-gfm): CommonMark + GitHub Flavored Markdown |
| Náhled | WebKit (`WKWebView`) bez JavaScriptu stránky, DOM se mění po blocích z izolovaného světa skriptů |
| Zvýraznění kódu | [highlight.js](https://highlightjs.org) v JavaScriptCore mimo hlavní vlákno |
| Matematika a diagramy | [KaTeX](https://katex.org) (JavaScriptCore), [Mermaid](https://mermaid.js.org) |
| Export | WebKit tisk a PDFKit (záložky), volitelně Pandoc |
| Aktualizace | [Sparkle 2](https://sparkle-project.org) s podpisem EdDSA |
| Build a kvalita | XcodeGen, Swift Testing, XCUITest, SwiftLint, os_signpost + Instruments |

Kód: ~10 800 řádků Swiftu v aplikaci a jádru (`HashlineCore`, testovatelné bez UI), ~2 300 řádků testů.

## Výkon

| Metrika | Rozpočet | Naměřeno (M4) |
|---|---|---|
| Latence psaní v 1MB dokumentu | < 16 ms | p50 ~6 ms, p95 ~7 ms |
| Otevření 1MB souboru | < 200 ms | 187–202 ms |
| Přepnutí režimu nebo tématu (1 MB) | < 50 ms | 2–40 ms (první přepnutí tématu až 70 ms) |
| Velikost aplikace | < 15 MB | 13 MB |

Podrobnosti a metodika v [docs/perf.md](docs/perf.md).

## Sestavení ze zdrojů

Vyžaduje Xcode 16+ a XcodeGen.

```sh
brew install xcodegen swiftlint
git clone https://github.com/Hessevalentino/hashline.git
cd hashline
xcodegen generate
open Hashline.xcodeproj
```

Testy a měření z příkazové řádky:

```sh
swift test --scratch-path ~/Library/Caches/Hashline-spm   # jádro (parser, renderer, export, bezpečnost)
scripts/verify-security.sh                                 # XSS v prohlížeči, nepřátelské dokumenty
scripts/bench-typing.sh 3                                  # latence psaní
```

Pravidla projektu jsou v [CLAUDE.md](CLAUDE.md), architektonická rozhodnutí v [docs/adr](docs/adr) a plán v [docs/roadmap.md](docs/roadmap.md). Vydání: `scripts/release.sh`. Zdroj webu je ve složce [WEB](WEB).

## Licence

Hashline je open source pod licencí [MIT](LICENSE). Převzaté části (MacDown, highlight.js, KaTeX, Mermaid, gemoji, Sparkle, swift-markdown, cmark-gfm) mají vlastní licence, viz [Sources/Hashline/Resources/Licenses](Sources/Hashline/Resources/Licenses).
