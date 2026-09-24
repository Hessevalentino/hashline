# ADR 0012: Režimy zobrazení (F5)

**Stav:** přijato (2026-09-24)

## Kontext
F5 přidává čtecí režim, focus a typewriter mode, stavový řádek a šířku textu. Přepnutí musí být pod 50 ms i u 1MB dokumentu a nesmí zpomalit psaní, když je režim vypnutý.

## Rozhodnutí
- **Nastavení v UserDefaults** (menu View), platí pro všechna okna. Editor je čte v jednom pozorovateli a mění jen to, co se změnilo.
- **Šířka textu** se dělá horizontálním `textContainerInset`: sloupec o N znacích písma editoru uprostřed. Platí stejně v celé obrazovce.
- **Focus mode** nemění atributy textu (to by spustilo nový styling a `fixAttributes` na 1 MB). Místo toho `NSTextLayoutManagerDelegate` vrací `FocusLayoutFragment`, který mimo blok s kurzorem kreslí s alfou 0,28. Při pohybu kurzoru se zneplatní jen starý a nový blok. Blokem je blok z BlockMap (odstavec, celý seznam, kód), případně front matter.
- **Typewriter mode:** vložky scroll view o polovinu výšky a vystředění kurzoru po změně výběru.
- **Čtecí režim** vyjme editor z HSplitView. Jeho NSScrollView drží relace a při návratu ho vrátí, takže kurzor, scroll a undo přežijí, a dělič se vrátí na původní pozici. Náhled zůstává na stejném místě ve stromu. Přesun WKWebView mezi dvěma reprezentacemi SwiftUI ho odpojil a náhled zůstal prázdný. Zúžení editoru na nulu HSplitView ignoruje.
- **Stavový řádek** počítá statistiky mimo main thread po stejné pauze jako náhled (a jen když je zobrazený). Výběr se počítá synchronně do 500 000 znaků.

## Důsledky a dluhy
- Focus mode ztlumí jen fragmenty v zobrazené oblasti. Po zapnutí se zneplatní viewport, zbytek se vykreslí správně při scrollu.
- Latence bez náhledu je při měření přes `open -g` vyšší kvůli E-jádrům (viz perf ¹¹). Pro srovnání s aktivní aplikací by byl potřeba běh v popředí, který ale bere fokus.
