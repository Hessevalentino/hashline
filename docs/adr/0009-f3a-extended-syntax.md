# ADR 0009: Rozšířená syntaxe bez změny parseru (F3a)

**Stav:** přijato (2026-09-24)

## Kontext
swift-markdown (cmark-gfm) nezná poznámky pod čarou, front matter, `[toc]`, emoji, `==x==` ani `^x^`. Front matter čte jako vodorovnou čáru a Setext nadpis.

## Rozhodnutí
- Parser se nemění. Rozšíření se rozpoznávají nad výsledkem: v textových uzlech (`InlineExtensions`), na úrovni odstavců (definice poznámek, `[toc]`) a na začátku dokumentu (`FrontMatter`). Zdroj je pořád pravda a jiný nástroj ho přečte stejně.
- Údaje za celý dokument (seznam nadpisů pro `[toc]`, texty poznámek pro tooltipy) počítá `PreviewRenderer` při aktualizaci náhledu. Změny se promítají do ID položek, takže se překreslí jen to, co na nich závisí.
- Surové HTML prochází allow-list sanitizérem (`HTMLSanitizer`). Povolené značky a atributy jsou pevně dané, URL se kontrolují (bez `javascript:` a SVG `data:`), styl jen pro velikosti. Ostatní se zobrazí jako text. Stránka náhledu navíc nesmí spouštět skripty a má přísnou CSP.
- Emoji: tabulka zkratek z GitHub gemoji (MIT, 42 KB). Našeptávač používá systémové doplňování `NSTextView` a do textu vkládá samotný znak emoji.
- Počáteční vykreslení velkého náhledu běží mimo main thread (strom swift-markdown je neměnný). Main thread do WebView jen posílá hotové HTML po částech.

## Důsledky a dluhy
- Jednoslovná definice poznámky (`[^1]: slovo`) je pro cmark definice odkazu. Odkaz se vykreslí správně, ale samotná definice v náhledu chybí.
- `==x==` a `^x^` se v editoru zatím nezvýrazňují, jen v náhledu.
- Poznámky se vykreslují tam, kde jsou definované (ne sebrané na konec dokumentu), s návratovým odkazem.
