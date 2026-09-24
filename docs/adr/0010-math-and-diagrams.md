# ADR 0010: Matematika a diagramy (F3b)

**Stav:** přijato (2026-09-24)

## Rozhodnutí
- **KaTeX v JavaScriptCore** (`MathRenderer`), ne ve WebView. `renderToString` DOM nepotřebuje, takže matematika funguje stejně pro náhled i export a bez WebKitu. Výstup je HTML + MathML (MathML čte VoiceOver). `trust: false`, takže `\href` a podobné příkazy nevytvoří odkaz ani skript. Výsledky jsou v cache.
- **CSS KaTeX** s fonty vloženými jako `data:` URL (stránka náhledu jiné zdroje nesmí načítat) se do stránky vkládá až u první rovnice.
- **Mermaid** potřebuje DOM, a proto běží ve WebView náhledu, ale jen v izolovaném světě skriptů aplikace (`.defaultClient`). Stránka dál žádné skripty nespouští. Knihovna je přibalená jako LZFSE (1,55 MB) a rozbalí se až u prvního diagramu. `securityLevel: 'strict'` (DOMPurify pro popisky, bez klikacích akcí). SVG jsou v cache podle zdroje diagramu.
- **Syntaxe:** `$…$` (otevírací `$` bez mezery za sebou, zavírací bez mezery před sebou a bez číslice za sebou, takže „$5 a $10“ zůstane textem), odstavec `$$…$$` (TeX se bere ze zdroje, ne z textu po zpracování Markdownem) a bloky ```` ```math ```` a ```` ```mermaid ````.
- Verze knihoven jsou zafixované ve `scripts/vendor.sh`, licence jsou v `Resources/Licenses/`.

## Důsledky a dluhy
- Inline `$…$` se čte z textu po zpracování Markdownem, takže escapování Markdownu uvnitř (např. `\{` → `{`) se projeví. V inline matematice je potřeba zdvojit zpětné lomítko, blokové `$$` a ```` ```math ```` tím netrpí.
- Téma diagramů se volí při načtení (světlé/tmavé) a po přepnutí vzhledu se diagramy zatím nepřekreslí.
- Export (F7) bude pro Mermaid potřebovat izolovaný renderer (rozhodnutí 2 v roadmapě).
