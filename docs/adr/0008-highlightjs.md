# ADR 0008: Zvýraznění kódu přes highlight.js v JavaScriptCore

**Stav:** přijato (2026-09-24, rozhodnutí uživatele). Nahrazuje rozhodnutí 4 (tree-sitter).

## Kontext
Tree-sitter gramatiky jsou velké. Změřeno po kompilaci (arm64): Swift 3,7 MB, Ruby 2,1 MB, PHP 2,0 MB, TypeScript 1,4 MB, Bash 1,4 MB, Rust 1,1 MB atd., 15 jazyků celkem ~15 MB. To je nad rozpočtem aplikace (15 MB) a Universal build by velikost zdvojnásobil.

## Rozhodnutí
- highlight.js 11.12.0 (BSD 3-Clause, sestavení „common“ se 36 jazyky, 126 KB) běží v `JSContext` v JavaScriptCore na vlastní sériové frontě (`CodeHighlighter`). Nepoužívá WebView ani stránku, jen dělí text na tokeny. Načte se až u prvního bloku kódu (~23 ms).
- Editor dostává tokeny (UTF-16 rozsahy a scope) asynchronně. Výsledek se zahodí, pokud se blok mezitím změnil (jiné `MarkdownBlock.id`). Náhled a export dostávají HTML z téhož nástroje, takže barvy v editoru i náhledu odpovídají. Paleta je Tomorrow Night (tmavé téma) a GitHub (světlé).
- Bloky nad 60 000 znaků zůstávají bez barev (~0,15 ms na řádek).

## Důsledky
- Aplikace má 6,5 MB (Universal) a podporuje 36 jazyků místo 11–15.
- Méně přesné než tree-sitter (regulární výrazy, ne gramatiky) a bez inkrementality. U bloků kódu v Markdownu to nevadí.
- Chybějící jazyky lze přidat jednotlivými soubory `languages/*.min.js` z téhož balíčku.
- Bloky kódu vnořené v seznamech a citacích se v editoru zatím nezvýrazňují (jejich kód má odsazení odebrané). V náhledu zvýrazněné jsou.
