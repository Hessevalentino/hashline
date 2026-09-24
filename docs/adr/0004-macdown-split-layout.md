# ADR 0004: Rozvržení jako MacDown (zdroj + HTML náhled)

**Stav:** přijato (2026-09-23, rozhodnutí uživatele). Nahrazuje inline náhled ve stylu Typory z původního zadání.

## Kontext
Uživatel požaduje design jako open source editor MacDown (https://github.com/MacDownApp/macdown, MIT, © 2014 Tzu-ping Chung). MacDown má vlevo editor zdroje se zvýrazněnou syntaxí a vpravo HTML náhled.

## Rozhodnutí
- Okno má dvě části: vlevo nativní editor zdroje (`NSTextView`, TextKit 2, neproporcionální písmo, zvýraznění syntaxe, značky zůstávají vidět), vpravo náhled ve `WKWebView`. Náhled jde skrýt zkratkou a ve výchozím stavu je zapnutý.
- Skrývání značek v textu (Typora) se neimplementuje.
- Náhled používá stejný HTML renderer jako export (rozhodnutí 5 implementačního promptu), takže náhled a export vypadají stejně.
- Z MacDownu přebíráme formát a obsah témat editoru (`.style`) a CSS náhledu, s uvedením licence v `Resources/Licenses/`. Kód (Objective-C, Hoedown) nepřebíráme, logiku píšeme ve Swiftu nad swift-markdown.

## Důsledky
- F1 je jednodušší a méně riziková: odpadá skrývání značek a řízení layoutu podle pozice kurzoru.
- WebKit se načte při každém otevření okna s náhledem. Naměřeno na prototypu: +80–95 ms do vykreslení náhledu, +~39 MB ve 3 procesech WebKitu (WebContent 20, GPU 14, Networking 4,5). Rozpočet se proto rozšiřuje, viz CLAUDE.md.
- Rozhodnutí 2 (izolovaný renderer pro Mermaid a matematiku) platí jen pro export a pro skrytý náhled. V zobrazeném náhledu se Mermaid a KaTeX vykreslují přímo ve WebView. Kritérium F3 „bez Mermaidu se nenačte WebKit“ se mění na „se skrytým náhledem se nenačte WebKit“.
- Rozhodnutí 1 (webové technologie nikdy nerenderují psaný text) platí dál. Editor je nativní a WebView jen zobrazuje výsledek.
