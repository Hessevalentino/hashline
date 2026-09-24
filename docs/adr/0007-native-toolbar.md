# ADR 0007: Lišta pro formátování v AppKitu

**Stav:** přijato (2026-09-24)

## Kontext
První verze lišty byla ve SwiftUI (`.toolbar` s 13 položkami, menu a ControlGroup). A/B měření na 1MB souboru ukázalo, že prodlužuje otevření z ~80 na ~220 ms (rozpočet 200 ms) a zhoršuje latenci psaní.

## Rozhodnutí
- Lišta je `NSToolbar` s položkami `NSToolbarItem` a `NSMenuToolbarItem`. Akce jdou s cílem nil do responder chain, takže je dostane aktivní editor, který je i validuje (`validateUserInterfaceItem`).
- Před prvním vykreslením se nainstaluje prázdná lišta stejného stylu (`.unifiedCompact`), aby titulek okna neměnil výšku. Skutečná lišta nahradí prázdnou, až je editor editovatelný. Samotné vytvoření položek stojí ~45–75 ms.
- Lištu lze přizpůsobit (`allowsUserCustomization`, `autosavesConfiguration`) a skrýt přes ⌥⌘T.
- Menu Format: položky nahrazují systémovou skupinu `.textFormatting` (Font, Text). Samostatné `CommandMenu("Format")` by vytvořilo druhé menu Format.

## Důsledky
- Otevření 1MB souboru je 83–133 ms a latence psaní p50 6,8 ms / p95 17 ms (Profile).
- Formátovací akce na `EditorTextView` jsou jediný vstupní bod pro menu, lištu i zkratky.
- ⌘1–⌘6 na české klávesnici: číslice jsou na horní řadě se Shiftem. Zda zkratka reaguje na klávesu „+/1“, je nutné ověřit ručně.
