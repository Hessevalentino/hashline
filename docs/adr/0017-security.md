# ADR 0017: Bezpečnost (F10)

**Stav:** přijato (2026-09-24)

## Kontext
F10: sandbox a security-scoped bookmarks, sanitizace HTML, CSP, renderer bez sítě, externí příkazy jen po výslovném nastavení a bez shellu, žádná telemetrie. Kritérium: korpus XSS vektorů nespustí žádný skript.

## Vrstvy
1. **Sanitizace:** raw HTML prochází allow-listem (`HTMLSanitizer`). Nově i odkazy a obrázky z Markdownu (`[x](javascript:…)`, `<javascript:…>` i referenční definice) ztratí cíl, když schéma není http, https, mailto, file nebo relativní cesta. U obrázků jsou povolená data jen `data:image/*` bez SVG. Platí pro náhled, export i Quick Look, ne pro výstup testovaný specifikací CommonMark.
2. **CSP:** náhled i export mají `default-src 'none'`, žádné skripty, obrázky z `data:`, `hashline-asset:` a volitelně http(s).
3. **Náhled bez JavaScriptu stránky:** skripty aplikace (patch DOM, Mermaid) běží v izolovaném světě. Navigovat smí jen `about:blank`, odkazy http, https a mailto jdou do prohlížeče a ostatní se zruší.
4. **KaTeX** `trust: false` (žádné `\href`), **Mermaid** `securityLevel: 'strict'`.

## Ověření
- `XSSCorpusTests`: 77 vektorů (OWASP filter evasion a vektory pro Markdown: odkazy, obrázky, definice, poznámky, tabulky, front matter, Mermaid, matematika) ve třech konfiguracích rendereru. Kontrola čte atributy jako prohlížeč: entity dekóduje jednou a hodnotu v uvozovkách bere jako celek. Má vlastní test, že nebezpečný výstup pozná.
- `scripts/verify-security.sh`: korpus vykreslený jako export a jako stránka náhledu se načte do WKWebView **se zapnutým JavaScriptem**, jednou i bez CSP. Každý vektor se snaží změnit titulek na „PWNED“. Výsledek: titulek beze změny, žádné obsluhy událostí, skripty ani `javascript:` URL. Kontrolní nesanitizovaný vektor titulek změní, takže zkouška útok pozná.

## Odolnost
- Hluboké vnoření (1 000 citací, 20 000 hvězdiček, 1 000 úrovní seznamu) shodilo aplikaci i Quick Look (přetečení zásobníku při rekurzivním převodu stromu). `NestingGuard` před parsováním nahradí značky nad 32 úrovní mezerami. Jde o ASCII za ASCII, takže se žádná pozice v textu neposune. Běžné dokumenty se nezmění (test na fixtures).
- `Renderer.render` jen rozděluje typy uzlů do samostatných funkcí. Jeden velký `switch` měl tak velký rámec, že pár úrovní seznamu přeteklo 512KB zásobník vlákna na pozadí.
- Matematické „bomby“ (`\def\a{\a\a}`) KaTeX zastaví limitem expanze. Test hlídá čas pod 2 s.

## Soubory a síť
- `hashline-asset:` vydává jen obrázky (podle přípony) a jen ze složek s přístupem. Cesta se před kontrolou normalizuje včetně `..` a symbolických odkazů, takže odkaz v knihovně nepovede ven. Hranicí zůstává sandbox.
- Síť: vzdálené obrázky v náhledu (lze vypnout: „Načítat v náhledu vzdálené obrázky“, vypnutí změní CSP), stažení vzdálených obrázků a otevření pandoc.org, obojí jen na pokyn uživatele. Žádná telemetrie, žádná kontrola aktualizací mimo Sparkle (F11).
- Externí programy (Pandoc, nahrávač obrázků) vybere uživatel v dialogu (security-scoped bookmark). Nahrávač se spustí jen při zapnuté volbě, argumenty jdou jako pole, nikdy přes shell.
- Oprávnění: aplikace má sandbox, soubory vybrané uživatelem, bookmarks, network.client (vzdálené obrázky) a print. Quick Look má jen sandbox.

## Dluhy
- Hardened runtime je kvůli ad-hoc podpisu vypnutý (ADR 0016, rozhodnutí o distribuci 2026-09-24).
