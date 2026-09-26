# Hashline – pravidla projektu

Minimalistický markdown editor pro macOS s rozvržením podle MacDownu: vlevo nativní editor zdroje se zvýrazněnou syntaxí, vpravo HTML náhled (ADR 0004). Role: seniorní macOS vývojář (Swift, AppKit, TextKit), který jako produktový designér škrtá a jako systémový programátor měří.

## Skilly

Při práci na Hashline vždy používej skilly `macos-*`:
- `macos-patterns`: před psaním jakéhokoli AppKit/SwiftUI kódu
- `macos-build`: build a oprava chyb (vyžaduje Xcode)
- `macos-settings-ui`: okno nastavení (pozor: skill cílí na macOS 26 Liquid Glass, Hashline má minimum macOS 14 → použít `if #available` a fallback)
- `macos-release` a `macos-auto-update`: distribuce DMG, notarizace, Sparkle (Sparkle je závislost → zdůvodnit před přidáním)

## Vize a principy

- Píše se, nic se nenastavuje. Otevře se okamžitě, zobrazí text a zmizí z cesty.
- Rozvržení jako MacDown (https://github.com/MacDownApp/macdown, MIT): editor zdroje se zvýrazněnou syntaxí, značky zůstávají vidět. Vedle je HTML náhled (WKWebView) se synchronním scrollováním. Náhled jde skrýt a ve výchozím stavu je zapnutý. Skrývání značek ve stylu Typory se nedělá.
- Soubor je pravda: obyčejné `.md` na disku, žádná databáze, žádný vlastní formát.
- Nativní vzhled a chování: světlý/tmavý režim, akcentní barva, zkratky, Undo, Services, Spotlight, Quick Look.
- Minimalismus: výchozí odpověď na nový nápad je „ne“. Rychlost je funkce, měří se, neodhaduje. Systémové komponenty mají přednost, žádný Electron ani webové jádro editoru.
- Každá závislost třetí strany potřebuje zdůvodnění (cena vlastní implementace, velikost, údržba, licence).
- Jednoduché řešení má přednost před chytrým. Abstrakce se zavádí až při třetím opakování.

## Technický základ

- Swift 6 se strict concurrency, macOS 14+, Apple Silicon
- SwiftUI pro okna, menu a nastavení. Editor je `NSTextView` na TextKit 2 v `NSViewRepresentable`. Náhled je `WKWebView` s HTML ze stejného rendereru jako export.
- `DocumentGroup` + `ReferenceFileDocument` (autosave, verze, Otevřít nedávné, iCloud Drive)
- Parser swift-markdown (cmark-gfm), inkrementálně po blocích, nikdy celý dokument na každý stisk klávesy
- Sandbox od začátku. Distribuce jako podepsaná a notarizovaná `.app` v DMG, později případně Mac App Store.

## Architektura

```
Sources/HashlineCore/   # bez AppKitu, testovatelné: Document (kodek), Parsing, Styling
Sources/Hashline/       # aplikace
  App/  Document/  Editor/{Behaviors}/  Export/  Settings/  Resources/
Tests/HashlineCoreTests/   # Swift Testing
Tests/HashlineUITests/     # XCUITest, jen kritické toky
Support/                   # Info.plist, entitlements
project.yml                # XcodeGen → Hashline.xcodeproj
Fixtures/                  # testovací korpus (scripts/make-fixtures.py)
docs/                      # perf.md, adr/, ideas.md
scripts/                   # make-fixtures.py, verify-f0.sh
```

- Text je jediný zdroj pravdy. Zvýraznění syntaxe mění jen atributy, nikdy obsah. Náhled je jen pro čtení.
- Po editaci se parsuje jen dotčený blok a jeho sousedé. Styluje se jen viditelná oblast.
- Parser nic neví o AppKitu, styling nic neví o souborech. Obojí jde testovat bez UI.

## Výkonnostní rozpočet

| Metrika | Cíl |
|---|---|
| Studený start do editovatelného okna | < 400 ms |
| Otevření 1MB souboru | < 200 ms |
| Latence psaní | < 16 ms (ideálně 8 ms) |
| Paměť aplikace: prázdné okno / 1 MB | < 60 MB / < 150 MB |
| Paměť procesů WebKitu (náhled) | < 50 MB navíc |
| Vykreslený náhled po startu | < 600 ms (editor musí být editovatelný dřív a nečekat na náhled) |
| Velikost .app | < 15 MB |
| CPU v klidu | 0 % |

Změny v renderingu a parsování ověřuj přes os_signpost (`Performance.signposter`) nebo v Instruments. Pokud změna rozpočet překročí, řekni to dřív, než ji navrhneš. Logy čti přes `/usr/bin/log` (v zsh je `log` vestavěný příkaz).

## Rozsah

Závazný plán je v `docs/roadmap.md` (fáze F0–F11). Rozsah níže je původní MVP pro kontext.

**MVP:** otevření, úprava a uložení `.md` (autosave, verze); živý náhled (nadpisy, odstavce, tučné a kurzíva, inline kód, odkazy, citace, seznamy včetně úkolových, bloky kódu se zvýrazněním, horizontální čára, GFM tabulky); obrázky (lokální i relativní, drag & drop do `./assets/`); zdrojový režim ⌘/; focus a typewriter mode; počet slov a znaků (lze skrýt); export do HTML a PDF; světlé/tmavé téma, volba písma a šířky textu.

**Mimo rozsah:** synchronizace, spolupráce v reálném čase, pluginy, mobilní verze. Výjimka: asistent AI u dokumentu (ADR 0019), ve výchozím stavu vypnutý. Nápady zapisuj do `docs/ideas.md`.

## Konvence

- Kód, názvy, komentáře a commity anglicky. README a docs česky.
- SwiftLint / swift-format s výchozími pravidly
- Swift Testing pro parser, styling a export. UI testy jen pro kritické toky.
- Žádné `!` mimo testy, žádný `print` (používej `Logger`). Veřejná API dokumentuj jen tam, kde nestačí název.

## Jak pracovat

- Fáze roadmapy navazují bez ptaní (rozhodnutí uživatele 2026-09-24). Po každé fázi pošli souhrn: co je hotové, měření a dluhy. Ptej se jen u skutečných produktových rozhodnutí nebo při střetu s rozpočtem či závislostmi.
- Malé kroky, každý končí sestavitelným stavem. Testy a měření se spouští až na konci větších celků (např. F1a), ne po každém kroku.
- Nevymýšlej API. Když si nejsi jistý chováním TextKitu 2 nebo swift-markdown, řekni to a navrhni, jak to ověřit.
- Když je zadání dvojznačné, ptej se. Když úkol roste, navrhni rozdělení.
- Odpovídej česky, stručně a věcně.

## Build a testy

Build výstupy patří mimo složku synchronizovanou Synology Drive (DerivedData v `~/Library/Developer/Xcode/DerivedData/Hashline`, SwiftPM v `~/Library/Caches/Hashline-spm`). Jinak synchronizace zpracovává gigabajty dat a zkresluje měření. Xcode projekt se generuje z `project.yml` (XcodeGen) a do gitu nepatří. Po změně souborů nebo nastavení spusť znovu `xcodegen generate`.

```sh
xcodegen generate
xcodebuild build -project Hashline.xcodeproj -scheme Hashline -destination "platform=macOS" -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Hashline"
xcodebuild test  -project Hashline.xcodeproj -scheme Hashline -destination "platform=macOS" -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Hashline"
swift test --scratch-path ~/Library/Caches/Hashline-spm   # jen HashlineCore, rychlé
swiftlint lint
scripts/verify-f0.sh          # round-trip fixtures v aplikaci
scripts/bench-typing.sh 3     # latence psaní bez XCTestu
```

- Snímky a měření spouštěj s `open -g` (bez aktivace), jinak aplikace převezme fokus a zachytí, co uživatel právě píše. Aplikace na pozadí bez náhledu běží na E-jádrech, proto se latence bez náhledu a s ním nedají přímo srovnávat.
- SwiftUI aplikace s DocumentGroup nemá v menu Edit podmenu Find. Hashline ho skládá sám (`PreviewCommands`) a akce jdou do `FindController` přes `FocusedValue` `editorSession`.
- UI testy sdílí UserDefaults s aplikací uživatele. Co test přepne klikem (např. záložka panelu), zůstane uložené. Když je potřeba pevný stav, předej klíč jako argument.
- Lokalizace: String Catalog `Sources/Hashline/Resources/Localizable.xcstrings` (a `Sources/HashlineQuickLook/`). Po změně textů v UI spusť `scripts/sync-strings.sh`, doplň češtinu do `scripts/translations-cs.py` a spusť `scripts/apply-translations.py`. V AppKitu používej `String(localized:)`, v pomocných funkcích parametry typu `LocalizedStringResource`/`LocalizedStringKey` (String by se nelokalizoval). Texty nespojuj přes `+` (dlouhé texty piš jako víceřádkový literál s `\`).
- Mac uživatele běží česky: UI testy s anglickými popisky musí předat `-AppleLanguages (en)`.
- HashlineCore je dynamický framework (sdílený s Quick Look). Lokální buildy jsou podepsané ad-hoc bez hardened runtime (jinak dyld framework odmítne kvůli library validation); F11 podepíše Developer ID a hardened runtime zapne.
- Vydání: `scripts/release.sh <verze> <build> "poznámka" …`. Nejdřív zvedni `CFBundleShortVersionString` a `CFBundleVersion` v `Support/Info.plist` a doplň CHANGELOG. Skript sestaví Release, vyrobí DMG, podepíše ho klíčem Sparkle (soukromý klíč je v Klíčence, záloha přes `generate_keys -x`), zapíše appcast, pushne a vytvoří GitHub Release. Web `WEB/` se nasazuje zvlášť.
- Bezpečnost: `swift test --filter XSSCorpus` (korpus a nepřátelské vstupy) a `scripts/verify-security.sh` (zkouška v prohlížeči s kontrolním vzorkem, otevření `Fixtures/hostile/*`). Nový vektor přidej do `XSSCorpusTests.vectors` i do `Fixtures/xss-corpus.md`.
- Rekurzivní průchody stromem (renderer, highlighter) drž s malými rámci: velký `switch` s těly větví v jedné funkci přetekl 512KB zásobník vlákna na pozadí už při pár úrovních.
- Práce na pozadí na hlavním vlákně (dávky) plánuj časovačem nebo přes `DispatchQueue.main`, ne `RunLoop.main.perform`: bloky `perform` drží run loop v pollingu, nepřijde `beforeWaiting` a okno se nepřekreslí.
- Témata: `Sources/Hashline/Resources/Themes/*.hashlinetheme` jsou v bundlu jako složka (`type: folder` v `project.yml`). Nové téma = složka s `theme.json` + `theme.css`; `ThemeTests` hlídá vestavěná témata.
- Export ověřuje `scripts/verify-export.sh` (háček `-HashlineExportTest <složka>`). Pandoc v sandboxu: spustí se jen soubor, který aplikace smí číst, tedy vybraný uživatelem v Nastavení. Kopie v kontejneru nejde, protože má `com.apple.provenance`. Pro test Pandocu: `scripts/verify-export.sh <cesta>` s dočasnou výjimkou `temporary-exception.files.absolute-path.read-only` v entitlements (nikdy necommitovat).
- `-HashlineTypingBenchmarkKeepOpen YES` nechá dokument po psaní otevřený (zkoušky konfliktu se souborem na disku).
- Asistent AI (ADR 0019): `-HashlineAssistantFake YES` nahradí poskytovatele skriptem bez sítě a klíče, `-HashlineAssistantSelfTest YES` (spolu s ním) projde úpravu, Undo a Stop v aplikaci bez fokusu a zapíše `Assistant self-test: …` do logu. Klíče jsou v Klíčence; po novém ad-hoc buildu se macOS zeptá na přístup při první zprávě.
- Přepnutí režimů měří `-HashlineModeBenchmark YES`. Klíče režimů (`focusMode`, `readingMode`…) nepředávej jako argumenty, doména argumentů přebije zápis do UserDefaults.

- `ReferenceFileDocument.snapshot` volá NSDocument na vlákně na pozadí (async save a autosave), main thread je přitom blokovaný. Proto je `snapshot` `nonisolated`. Nikdy ho neoznačuj `@MainActor`, jinak aplikace při ukládání spadne.
- Save panel v sandboxu běží mimo proces a XCUITest ho neovládne. UI testy proto otevírají soubor přes DEBUG argument `-HashlineUITestDocument <jméno>` (`App/UITestSupport.swift`).
