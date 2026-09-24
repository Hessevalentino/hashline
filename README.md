# Hashline

Nativní markdown editor pro macOS. Vlevo zdroj se zvýrazněnou syntaxí, vpravo živý HTML náhled. Pracuje s obyčejnými soubory `.md` na disku, bez databáze a bez účtu.

Web: **https://hashline.hesse.works/**

## Stažení a instalace

Požadavky: macOS 14 Sonoma nebo novější, Mac s Apple Silicon.

1. Stáhněte `Hashline.dmg` z [posledního vydání](https://github.com/Hessevalentino/hashline/releases/latest).
2. Otevřete DMG a přetáhněte Hashline do složky Aplikace.
3. **Při prvním spuštění povolte výjimku.** Hashline je podepsaný jen ad-hoc (bez placeného účtu Apple Developer), takže ho macOS napoprvé zablokuje hláškou, že aplikaci nelze ověřit:
   - Klikněte na **Hotovo** (neklikejte na „Přesunout do koše“).
   - Otevřete **Nastavení systému ▸ Soukromí a zabezpečení**, sjeďte dolů k hlášce o aplikaci Hashline a klikněte na **Přesto otevřít**. Potvrďte heslem nebo Touch ID.
   - Pak už se Hashline spouští normálně.

   Alternativa pro Terminál: `xattr -dr com.apple.quarantine /Applications/Hashline.app`

Aktualizace: Hashline se při druhém spuštění zeptá, jestli má jednou týdně hledat nové verze (Sparkle). Aktualizace jsou podepsané klíčem EdDSA, takže je aplikace nainstaluje jen tehdy, když pocházejí z tohoto projektu. Ručně: menu Hashline ▸ Check for Updates…

## Co umí

- Editor s TextKit 2: zvýraznění Markdownu i kódu (highlight.js), psaní pod 10 ms i v 1MB souboru
- Náhled: GFM tabulky, úkoly, poznámky pod čarou, `[toc]`, emoji, matematika (KaTeX), diagramy (Mermaid), obrázky
- Formátovací lišta, přepínač světlý/tmavý vzhled, režimy čtení, soustředění a psacího stroje, stavový řádek
- Knihovna (složka dokumentů), osnova, hledání v knihovně ⇧⌘F, rychlé otevření ⌘P, najít a nahradit s regexem
- Export do HTML, PDF (se záložkami), PNG a přes Pandoc do DOCX, ODT, RTF, ePub, LaTeX a dalších
- Témata (`theme.json` + `theme.css`), čeština a angličtina, Quick Look pro `.md` ve Finderu, Služby
- Sandbox, náhled bez JavaScriptu, sanitizace HTML, žádná telemetrie

## Sestavení ze zdrojů

Vyžaduje Xcode 16+ a XcodeGen (`brew install xcodegen swiftlint`).

```sh
xcodegen generate
open Hashline.xcodeproj
```

Příkazy pro build, testy a měření jsou v [CLAUDE.md](CLAUDE.md), rozhodnutí v [docs/adr](docs/adr), plán v [docs/roadmap.md](docs/roadmap.md) a měření v [docs/perf.md](docs/perf.md). Vydání: `scripts/release.sh`. Zdroj webu je ve složce [WEB](WEB).

## Licence třetích stran

MacDown (styly a témata), highlight.js, KaTeX, Mermaid, gemoji, Sparkle, swift-markdown. Texty licencí jsou v `Sources/Hashline/Resources/Licenses`.
