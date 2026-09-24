# ADR 0005: Výkon editoru a náhledu (F1a)

**Stav:** přijato (2026-09-23)

## Zjištění a rozhodnutí
1. **Touch Bar v NSTextView.** Po každém úhozu AppKit prochází atributy textu kvůli formátovacím položkám Touch Baru, i na Macu bez Touch Baru. Se zvýrazněním to bylo 88 % času main threadu a latence psaní v 1 MB byla 55 ms. `EditorTextView` přepisuje `updateTextTouchBarItems()` a `makeTouchBar()`. Latence klesla na p50 9 ms.
2. **Parsování na pozadí.** Dokumenty nad 100 000 znaků se parsují mimo main thread (1 MB ≈ 136 ms). Text je mezitím editovatelný, jen zatím bez barev. Menší dokumenty se parsují synchronně, aby nikdy neproblikly bez barev.
3. **WebKit až po editoru.** `WKWebView` vzniká, až je editor editovatelný. Synchronní vytvoření posouvalo otevření souboru z 80 na 150–220 ms.
4. **Náhled posílá rozdíly a plní se po dávkách.** Úprava nahradí souvislý úsek bloků, takže se posílá jen tento úsek (kotva, odebrané ID, nové HTML). Velké dokumenty se do DOM plní po dávkách (300, pak po 3 000 blocích), aby se první obrazovka objevila hned. Bloky mimo obrazovku mají `content-visibility: auto`.
5. **Aktualizace náhledu až po pauze v psaní** (60 ms). Kontrola definic referenčních odkazů přes celý dokument běží ve stejném kroku.

## Chyby a omezení cmark-gfm, které BlockMap obchází
- Pozice vnořených prvků v odstavci, který začíná definicí odkazu, jsou o počet definic řádků výš. `MarkdownBlock.range(of:)` je posouvá.
- Vnořený důraz, který začíná nebo končí společně s rodičem (`***a***`), má rozsah přes oddělovače rodiče. `Highlighter` ho omezuje.
- Blokové rozsahy mohou obsahovat koncový znak nového řádku a rozsah seznamu zahrnuje prázdné řádky za ním.

## Důsledky a dluhy
- DOM náhledu u 1 MB drží všech ~22 000 bloků (WebKit ~200 MB). Řešením je virtualizace náhledu (v DOM jen bloky kolem viditelné oblasti).
- Definice odkazů uvnitř seznamů a citací se do částečných parsování nepřenáší. Referenční odkaz jinde může zůstat nevyřešený do dalšího úplného parsování (vzácné, nalezeno fuzz testem: 2 případy z 60 000 editací).
