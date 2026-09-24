# ADR 0013: Navigace, hledání a změny na disku (F6)

**Stav:** přijato (2026-09-24)

## Kontext
F6 přidává osnovu, strom knihovny, hledání ve složce, hledání a nahrazování s regexem, Quick Open a reakci na změny souboru jinou aplikací.

## Rozhodnutí
- **Postranní panel** (⇧⌘L) má čtyři záložky: Dokumenty (dosavadní seznam knihovny), Složky, Osnova a Hledání v knihovně. Osnova se počítá z BlockMap po pauze v psaní a jen při zobrazené záložce.
- **Najít a nahradit** je vlastní lišta nad editorem (`FindController`), ne NSTextFinder: ten neumí regex ani skupiny v nahrazení. Hledání běží mimo main thread nad kopií textu, výskyty se zvýrazní rendering atributy TextKitu 2 (max. 2 000, text se nemění). Nahradit vše je jedna úprava od prvního do posledního výskytu, tedy jeden krok undo a jedna změna text storage. Menu Find skládá aplikace sama, protože ho SwiftUI s DocumentGroup nevytvoří.
- **Hledání v knihovně** prochází soubory mimo main thread, je přerušitelné a vrací až 50 řádků na soubor. Doslovné hledání ignoruje diakritiku jako hledání v knihovně, regex je přesný.
- **Quick Open ⌘P** nabízí dokumenty knihovny a nedávné soubory s fuzzy řazením. Tisk (náhledu) se přesunul na ⇧⌘P.
- **Změny na disku:** vnode události na otevřeném souboru (po atomickém nahrazení se hlídání obnoví). Dokument si pamatuje otisk (hash) textu naposledy načteného nebo uloženého. Když se text editoru s otiskem shoduje, editor se tiše načte znovu (bez undo historie a dokument zůstane neupravený). Jinak se ukáže lišta Reload / Keep Mine. Stav „upraveno“ z NSDocumentu se nepoužívá: u dokumentů SwiftUI bývá hned po psaní ještě `false`.

## Důsledky a dluhy
- Zvýraznění výskytů se po úpravě textu obnoví až po pauze v psaní.
- Smazání nebo přesun otevřeného souboru jinou aplikací zatím nemá vlastní hlášku (NSDocument sleduje přesun sám).
- Tisk je jen tisk náhledu. PDF s osnovou přijde v F7.
