# ADR 0014: Export a import (F7)

**Stav:** přijato (2026-09-24)

## Kontext
F7 vyžaduje HTML, PDF se záložkami a kotvami, PNG a formáty přes Pandoc včetně importu, se srozumitelnou hláškou, když Pandoc chybí.

## Rozhodnutí
- **Jeden renderer:** export používá `HTMLRenderer` jako náhled (volby `.export`: úkoly jako neaktivní checkboxy, obrázky s cestou ze zdroje). `ExportDocument` v jádru skládá samostatnou stránku: styly GitHub2 + highlight.js inline, KaTeX CSS jen při matematice, CSP bez skriptů, titulek z front matter nebo z prvního nadpisu. Front matter do exportu nepatří.
- **Diagramy:** Mermaid potřebuje prohlížeč. `ExportPage` je skrytý WKWebView (světlý vzhled, JavaScript stránky vypnutý), ve kterém Mermaid běží v izolovaném světě jako v náhledu. SVG se pak vloží do HTML (volba `diagrams`).
- **PDF:** tisk skryté stránky přes `NSPrintOperation` do souboru (velikost papíru podle systému, `break-inside: avoid` pro kód, tabulky a obrázky) a potom PDFKit: záložky podle nadpisů. Nadpis se hledá jedním průchodem textem stránek jako celý řádek, který není odkazem (položky `[toc]` opakují titulky). Odkazy na nadpisy s diakritikou (`about:blank#…` od WebKitu) se přesměrují na záložky. Kvůli tiskovému systému má aplikace entitlement `com.apple.security.print`.
- **PNG:** snímek celé výšky stránky (max. 8 000 bodů) v rozlišení obrazovky.
- **Pandoc:** externí program, žádná závislost v balíku. Uživatel ho vybere v Nastavení ▸ Export (security-scoped bookmark). Sandbox pak smí soubor číst i spustit, což je ověřeno s výjimkou pro čtení `/opt/homebrew`. Argumenty se předávají jako pole, vstup i výstup jdou přes dočasné soubory (velký výstup nezablokuje rouru). Import převádí do `gfm-tex_math_gfm+tex_math_dollars`, aby matematika zůstala ve tvaru `$…$`. Bez Pandocu se ukáže hláška s volbou „Choose Pandoc…“ a odkazem na pandoc.org.
- **⇧⌘E** otevře dialog uložení s nabídkou formátu (pamatuje si poslední formát). Menu Export má položku pro každý formát. Tisk je dál ⇧⌘P.

## Důsledky a dluhy
- PDF 1MB dokumentu (1 371 stran) trvá přes minutu, hlavně kvůli tisku ve WebKitu. Běžné dokumenty trvají pod sekundu. Export nejde zrušit.
- Import přes Pandoc nerozbaluje obrázky z DOCX/ODT (`--extract-media` by potřeboval zápis vedle cíle).
- Pandoc dostává `--resource-path` složky dokumentu, ale v sandboxu k ní nemusí mít přístup. Obrázky v DOCX pak mohou chybět.
- Automatický test Pandocu vyžaduje dočasnou výjimku v entitlements, protože výběr souboru v Powerboxu XCUITest neovládne.
