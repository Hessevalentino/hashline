# Výkon

Každá fáze přidá řádek. Měří se Release build na MacBook Pro M4 (16 GB), macOS 26.6. Hodnoty jsou rozsahem ze 3 spuštění.

- **Start:** od startu procesu (kernel) do editovatelného okna
- **Otevření:** od čtení souboru do editovatelného okna
- **Latence psaní:** od stisku klávesy do odeslání snímku (Core Animation commit), 100 úhozů v 1MB souboru
- **Paměť:** `phys_footprint`

| Fáze | Datum | Start prázdné | Start 1 MB | Otevření 1 MB | Otevření 10 MB | Psaní 1 MB (p50 / p95 / max) | Paměť prázdné / 1 MB / 10 MB | Uložení 1 MB / 10 MB | .app |
|---|---|---|---|---|---|---|---|---|---|
| Rozpočet | | < 400 ms | < 400 ms | < 200 ms | – | < 16 ms | < 60 / < 150 MB / – | – | < 15 MB |
| AI A1–A6 | 2026-09-26 | – | 476 ms⁽ᵃ⁾ | – | – | vypnuto 3.8–4.2 / 11.2–14.3 / 30 ms; panel 4.0–5.0 / 6.6–14.4 / 24 ms | – | – | 14 MB |
| F10 | 2026-09-24 | – | – | 187–202 ms¹⁶ | – | 6.0–6.2 / 6.8–7.1 / 10 ms | – | – | 9.9 MB |
| F9 | 2026-09-24 | – | – | 179–193 ms | – | 5.9–6.6 / 8.5–10.2 / 34 ms | – | – | 9.9 MB¹⁵ |
| F8 | 2026-09-24 | – | – | 170–190 ms¹⁴ | – | 6.5–6.9 / 9.1–10.0 / 32 ms | – | – | 12 MB |
| F7 | 2026-09-24 | – | – | – | – | – | – | – | 12 MB¹³ |
| F6 | 2026-09-24 | – | – | – | – | 4.2–11.6 / 6.0–16.1 / 43 ms¹² | – | – | – |
| F5 | 2026-09-24 | – | – | – | – | 4.2–6.3 / 8.2–13.5 / 20 ms¹¹ | – | – | – |
| F4 | 2026-09-24 | – | – | 141–171 ms (100 obrázků) | – | 4.9–5.8 / 11.6–12.7 / 19 ms | 52 MB (100 obrázků) | – | 9.7 MB¹⁰ |
| F3b | 2026-09-24 | – | – | 96 ms (math-mermaid) | – | 4.2–4.7 / 13 / 18 ms | – | – | 9.1 MB⁹ |
| F3a | 2026-09-24 | – | 308–414 ms | 99–114 ms | – | 4.3 / 11.2 / 20 ms⁸ | app 50 (ext.) / 110 MB (1 MB) | – | 6.9 MB |
| F1b | 2026-09-24 | – | 268–573 ms | 97–156 ms | – | 4.5 / 7.6 / 19 ms⁷ | app 55–58 (kód) / 100–102 MB (1 MB) | – | 6.5 MB |
| Knihovna | 2026-09-24 | – | 283–434 ms | 87–108 ms⁶ | – | – | app 100–124 MB (1 MB) | – | 5.5 MB |
| F2b | 2026-09-24 | – | 309–525 ms | 87–142 ms | – | 5.9–12.3 / 18.7–26.6 / 40 ms⁵ | – | – | 5.5 MB |
| F2a | 2026-09-24 | 325–336 ms | 403–435 ms | 83–133 ms | – | 6.8 / 17.0 / 29 ms³ | app 41–60 / 99–101 MB / – | – | 5.3 MB |
| F1a | 2026-09-23 | 222–362 ms | 279–315 ms | 79–89 ms | 101–112 ms | 9.1–9.5 / 13.5 / 29 ms³ | app 32–55 / 97–111 / 493–637 MB⁴ | – | 4.1 MB |
| F0 | 2026-09-23 | 203–221 ms | 312–326 ms | 76–91 ms | 99–123 ms | 10.5 / 13.6 / 30.0 ms¹ | 23–36 / 43–45 / 71 MB | 2.2 / 21.6 ms² | 460 KB |

³ Konfigurace Profile (Release optimalizace + testové háčky) s náhledem. Samotné zvýraznění stojí p50 0,4 ms na úhoz. Maxima jsou částečně způsobená samotným XCUITestem, který během psaní čte přístupnostní strom.
⁴ Plus procesy WebKitu (náhled): prázdné a malé 34–40 MB, 1 MB ~200 MB, 10 MB ~230 MB po 10 s (stále se plní). Náhled první obrazovky: malý 423–473 ms, 1 MB 454–488 ms, 10 MB 1,9 s (parsování na pozadí).

¹⁶ Na hraně rozpočtu 200 ms (dva ze čtyř běhů těsně nad). Rozbor viz ¹⁴: první vykreslení okna (layout lišty, SwiftUI). `NestingGuard` projde text parsovaného úseku dvakrát (u 1 MB mimo hlavní vlákno). Dluh: zrychlit první snímek okna. Quick Look na nepřátelských souborech 3–65 ms, bez pádu.

¹⁵ HashlineCore je teď dynamický framework, který sdílí aplikace i rozšíření Quick Look. Staticky by rozšíření neslo vlastní 4MB kopii a .app by měla 18 MB. Release je jen pro arm64 (dřív univerzální binárka). Složení: aplikace 2,4 MB, framework 3,1 MB, Quick Look 1 MB, zbytek zdroje (Mermaid 1,5 MB). Quick Look (Release): malý soubor 61 ms, 1 MB (prvních 200 000 znaků) 259 ms.

¹⁴ Release, `open` s cestou k souboru. Oproti F3a (99–114 ms) je to asi o 80 ms víc. Rozbor: první vykreslení okna po zařazení editoru stojí ~97 ms (layout lišty ~48 ms, zbytek SwiftUI). Hned po zeditovatelnění blokuje hlavní vlákno ~180 ms instalace formátovací lišty (~94 ms) a start WebKitu (`registerUserInstalledFonts` ~54 ms). Dluh na F10/F11: lištu a náhled rozložit do více běhů run loopu. Témata se načtou za 2–3 ms. Přepnutí tématu nebo písma na 1 MB 10–70 ms (synchronní část ~10 ms: jen viewport + 2 000 znaků). Stylování na pozadí se teď plánuje časovačem v default módu: `RunLoop.perform` nechal run loop točit bez spánku a okno se až do konce průchodu (~1,5 s u 1 MB) nepřekreslilo. Proto je p95 psaní nižší než dřív.

¹³ Export (Profile build, `-HashlineExportTest`): malý dokument s diagramy a matematikou HTML 550 ms, PDF 690–830 ms (3 strany), PNG 670 ms. 1 MB: HTML 650 ms, PNG 2,0 s, PDF 63 s (1 371 stran, z toho tisk WebKitu ~48 s a 4 932 záložek 15 s). Od 0,4 s se ukazuje list s průběhem. Binárka Release 8,7 MB, .app 12 MB (rozpočet 15 MB).

¹² Rozptyl mezi běhy dělá plánovač: v profilu byla hlavní vlákna střídavě na P- a E-jádrech (569 : 296 vzorků). Kód F6 (osnova, hledání, hlídání souboru) se v úhozu téměř neobjevuje. Osnova se počítá jen při zobrazené záložce Osnova (běh s ní: p50 4,2 ms). Hledání v 5 000 souborech 132 ms (release, `HASHLINE_PERF=1 swift test -c release --filter folderSearchOf5000`), rozpočet 300 ms.

¹¹ Přepnutí režimu na 1 MB (akce → další snímek, `-HashlineModeBenchmark YES`): čtecí režim 6–33 ms, focus 2–3 ms, typewriter 6–7 ms, stavový řádek 1–14 ms, šířka textu 1–3 ms (rozpočet 50 ms). Statistiky 1 MB 6,8 ms mimo main thread. Latence bez náhledu (p50 ~12,5 ms) **není vlastnost editoru**: Time Profiler ukázal, že aplikace spuštěná přes `open -g` bez viditelného WebKitu běží celá na úsporných E-jádrech (100 % vzorků), s náhledem na P-jádrech. Rozložení práce je v obou případech stejné. Šířka textu na tom nic nemění. Uživatel píše do aktivní aplikace, takže jde o artefakt měření; srovnávej jen běhy se stejným nastavením.

¹⁰ Dokument se 100 lokálními obrázky: náhled za 568–709 ms po startu procesu, obrázky přes `hashline-asset:` s `loading="lazy"` (načítají se jen viditelné).

⁹ KaTeX 0.18.9 (JS 272 KB, CSS s fonty 369 KB) a Mermaid 12.0.0 (LZFSE 1,55 MB místo 5,4 MB). Náhled dokumentu se 3 diagramy: 622 ms po startu procesu, 2 diagramy vykresleny, 1 z cache. Se skrytým náhledem se nespustí žádný proces WebKitu.

⁸ Nový způsob měření: `scripts/bench-typing.sh`. Aplikace sama píše do 1MB dokumentu přes `NSWindow.sendEvent`, bez XCTestu, bez fokusu a bez mrtvých kláves. Samotné zpracování úhozu je p50 2,5 ms. Se skrytým náhledem p50 12,5 ms a p95 16,5 ms, vysvětlení viz ¹¹ (E-jádra, ne layout).

⁷ Aplikace spuštěná bez aktivace (`open -g`), takže ji nerušil fokus. highlight.js: zavedení 23 ms (jednou), 50 / 200 / 500 řádků 7,6 / 30 / 75 ms mimo main thread.

⁶ S knihovnou skrytou i zobrazenou bez rozdílu. Skenování 5 000 souborů 205 ms (cíl 300 ms), prohledání jejich obsahu 112 ms, obojí mimo main thread (`HASHLINE_PERF=1 swift test -c release --filter LibraryIndexTests`).

⁵ Tři běhy. Rozptyl dělá hlavně samotný XCUITest (během psaní čte přístupnostní strom 1MB dokumentu) a zátěž systému (Time Machine). Dluh: měřit úhozy bez XCTestu (CGEvent z pomocného nástroje).

¹ Měřeno v Debug buildu (UI test potřebuje DEBUG háček), Release bude rychlejší. Maximum 30 ms je jeden úhoz, nejspíš první po otevření. Viz dluhy F0.
² Od snapshotu po zakódování dat, bez samotného zápisu na disk.

## Jak měřit

```sh
scripts/verify-f0.sh                       # round-trip fixtures + latence psaní (Debug)
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "cz.hashline.Hashline"'
```

Signposty (Instruments → Points of Interest): `Launch`, `ReadFile`, `Snapshot`, `WriteFile`, `Keystroke`, `Parse`, `Highlight`, `PreviewLoad`, `PreviewUpdate`.

```sh
scripts/bench-typing.sh 3                     # latence psaní bez XCTestu (Profile build)
scripts/bench-typing.sh 2 -showsPreview NO    # totéž bez náhledu
HASHLINE_PERF=1 swift test -c release --filter PerformanceProbeTests   # cena úhozu v jádru na 1 MB
xcrun xctrace record --template 'Time Profiler' --attach <pid> --time-limit 6s --output typing.trace
```

⁽ᵃ⁾ Asistent AI (ADR 0019): Profile build, 2 běhy po 100 úhozech v 1MB souboru, ručně (měřeno ve vývojové kopii pod názvem Hashline AI). Asistent vypnutý nemá v cestě žádný kód; otevřený panel s falešným poskytovatelem latenci nemění. Start 1 MB je z běhu s panelem. Velikost .app zahrnuje Sparkle (F11), podíl asistenta zvlášť změřený není.
