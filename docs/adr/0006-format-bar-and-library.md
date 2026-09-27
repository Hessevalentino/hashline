# ADR 0006: Lišta pro formátování a knihovna

**Stav:** přijato (2026-09-23, rozhodnutí uživatele)

## Kontext
Uživatel chce, aby šlo psát i bez znalosti Markdownu, a chce spravovat dokumenty v jedné složce.

## Rozhodnutí
- **Lišta pro formátování:** tenká lišta v titulku okna. Obsahuje Knihovnu, B / I / U, nadpis, typ seznamu (odrážky, číslovaný, úkoly) a další tlačítka (citace, kód, blok kódu, odkaz, obrázek, tabulka, čára). Tlačítka vkládají Markdown kolem výběru a mají stejné zkratky jako menu Formát. Podtržení se vkládá jako HTML `<u>…</u>`, protože Markdown podtržení nemá. Lištu jde skrýt.
- **Knihovna:** postranní panel vlevo v okně dokumentu. Uživatel vybere složku, nové dokumenty se ukládají do ní a soubory do ní jde nahrát. Panel ukazuje seznam dokumentů a hledání podle názvu i obsahu. Přístup ke složce drží security-scoped bookmark. Panel se skrývá přes ⇧⌘L.
- **Pořadí:** F2 (včetně lišty) → knihovna (přesunuto z F6) → F1b → F3…

## Důsledky
Výjimka ze zásady „rozhraní je skryté, dokud není potřeba“: lišta je ve výchozím stavu zapnutá. Obojí jde skrýt.

## Doplněk (2026-09-24)
Dokument vybraný v knihovně se otevírá jako nativní záložka okna (`NSWindow.tabbingMode = .preferred`, `addTabbedWindow`). Už otevřený dokument se jen přepne. Autosave i verze fungují beze změny, protože každá záložka je vlastní `NSDocument`.

## Doplněk (2026-09-27): složky
Seznam Dokumenty prochází knihovnu po složkách. Podsložky jsou nahoře, klik složku otevře a šipka Zpět vede o úroveň výš. Hledání dál prochází celou knihovnu. Nové a přidané dokumenty se ukládají do otevřené složky.

Zobrazují se všechny podsložky včetně prázdných, jinak by do nové složky nešlo nic vytvořit. Výjimkou jsou složky obrázků (`assets`, `<dokument>.assets`), které se ukážou jen tehdy, když obsahují dokumenty. Symbolické odkazy, balíčky a skryté složky se nezobrazují.

Složku jde vytvořit (tlačítko ve spodní liště, pravé tlačítko na prázdném místě) a přesunout do koše (pravé tlačítko na složce). Mazání je bezpečné:
- složka jde jen do koše, nikdy se nemaže natrvalo,
- vždy se potvrzuje a potvrzení uvádí počet dokumentů; Return mazání zruší,
- smazat nejde kořen knihovny, nic mimo ni ani symbolický odkaz,
- otevřené dokumenty ze složky se nejdřív uloží (čeká se na dokončení) a zavřou; když uložení selže, nic se nepřesune.

Přejmenování a přesouvání složek zatím Hashline nedělá, na to je Finder.
