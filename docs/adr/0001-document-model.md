# ADR 0001: Dokumentový model

**Stav:** přijato (F0)

## Kontext
Potřebujeme autosave, verze, „Otevřít nedávné“ a iCloud Drive bez vlastního kódu. Psaní v 1MB souboru přitom nesmí kopírovat celý text.

## Rozhodnutí
- `DocumentGroup` + `ReferenceFileDocument`. Třída `MarkdownDocument` vlastní `NSTextStorage` a editor ji zobrazuje přímo, takže úhoz nekopíruje text.
- Soubor se čte mimo main actor jako `String`. `NSTextStorage` vzniká líně na main actoru, protože není `Sendable`.
- `snapshot(contentType:)` je `nonisolated`. NSDocument ho volá na vlákně na pozadí (asynchronní uložení a autosave) a main thread přitom blokuje v `_waitForUserInteractionUnblocking`. Čtení storage tedy nekoliduje s editací. Převod `NSTextStorage.string` na `String` vytvoří nezávislou kopii (ověřeno testem).
- `TextFileCodec` zachová kódování, BOM a konce řádků. Obsah se nikdy nenormalizuje. Nově psané konce řádků kopírují styl dokumentu (`LineEnding`).
- Úpravy jdou přes undo manager dokumentu (`NSTextViewDelegate.undoManager(for:)`), jinak by se dokument neoznačil jako upravený a nefungoval by autosave.

## Důsledky
- Označení `snapshot` jako `@MainActor` shodí aplikaci při ukládání (zachyceno crash reportem 2026-09-23).
- Snapshot 10MB souboru trvá kolem 20 ms na vlákně na pozadí, UI po tu dobu stojí. Při velmi velkých souborech zvážit jiný přístup.
