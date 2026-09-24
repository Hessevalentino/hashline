# ADR 0016: Systémová integrace a lokalizace (F9)

**Stav:** přijato (2026-09-24)

## Kontext
F9: cs a en, Quick Look, Services a Share, přístupnost, nastavení Obecné, Editor, Obrázky, Export a Vzhled. Kritérium: Accessibility Inspector bez chyb a úplná lokalizace.

## Rozhodnutí
- **Lokalizace:** String Catalog. Kompilátor texty vypíše (`SWIFT_EMIT_LOC_STRINGS`), `xcstringstool sync` je doplní do katalogu (`scripts/sync-strings.sh`) a češtinu drží `scripts/translations-cs.py`, odkud je zapíše `apply-translations.py`, včetně českých tvarů množného čísla. AppKit texty jdou přes `String(localized:)` a pomocné funkce berou `LocalizedStringResource`. Info.plist (typ dokumentu) a menu Služby mají `InfoPlist.strings` a `ServicesMenu.strings`. Jádro (HashlineCore) zůstává bez lokalizace; jediný text, který se z něj zobrazuje („Front matter“), dostává od aplikace (`frontMatterLabel`).
- **Quick Look:** rozšíření `HashlineQuickLook.appex` (data-based preview, `QLPreviewReply` s HTML). Používá stejný renderer i export stránky, vestavěná témata Paper a Tomorrow Night přes `prefers-color-scheme` a bez JavaScriptu (Mermaid zůstane jako kód). Delší soubory ukazuje do 200 000 znaků. Sandbox bez dalších práv.
- **Sdílený framework:** HashlineCore je dynamická knihovna vložená do aplikace, rozšíření ji načítá přes rpath. Statické linkování by rozšíření nafouklo o 4 MB a .app by překročila rozpočet 15 MB. Release je jen pro arm64.
- **Hardened runtime:** lokálně vypnutý. S ad-hoc podpisem by library validation framework odmítla (binárky nemají Team ID). Při distribuci (F11) se aplikace, framework i rozšíření podepíšou Developer ID a hardened runtime se zapne, což notarizace vyžaduje.
- **Služby:** „New Hashline Document Containing Selection“. HTML výběr se převede na Markdown (`HTMLToMarkdown`), text se vloží jako jedna úprava s undo, takže dokument je upravený a autosave funguje. **Sdílení:** `NSSharingServicePickerToolbarItem` v liště sdílí uložený soubor, u neuloženého dokumentu jeho text.
- **Přístupnost:** UI test `AccessibilityUITests` spouští `performAccessibilityAudit` na okno dokumentu (panel, lišta hledání, náhled, stavový řádek) a na všech pět záložek Nastavení. Opravy: popisky panelů, editoru a polí hledání, neprůhledné pozadí textů (na průsvitném materiálu kontrast neprošel), prázdná osnova místo seznamu, ne jako překryv. Vyjmuté jsou jen prvky, které aplikace neovlivní: Touch Bar, titulek okna, vnitřní skupiny `HSplitView`, AXPress u menu Pickerů ze SwiftUI (klik, klávesnice i VoiceOver fungují) a ztlumené popisky zakázaných prvků (WCAG 1.4.3).

## Důsledky a dluhy
- Quick Look neukazuje lokální obrázky (rozšíření k nim v sandboxu nemá přístup).
- Náhledy formátů v Quick Looku (miniatury) nejsou. Finder používá obecnou ikonu dokumentu.
- Vlastní `HSplitView` z AppKitu by umožnil popsat i vnitřní kontejnery. Zatím to nestojí za náhradu.
