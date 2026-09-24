# ADR 0011: Obrázky v sandboxu (F4)

**Stav:** přijato (2026-09-24)

## Kontext
Sandboxovaná aplikace smí číst jen dokument, který uživatel otevřel, a ne soubory vedle něj (`./assets/obrazek.png`). WebKit náhledu běží v dalších procesech a k souborům aplikace přístup nemá.

## Rozhodnutí
- Náhled načítá lokální obrázky přes vlastní schéma `hashline-asset:///cesta`. Obsluhuje ho aplikace (`AssetSchemeHandler`) a soubor vydá, jen když leží ve složce, ke které má přístup: knihovna, složky povolené uživatelem (security-scoped bookmark, pamatují se) a vlastní kontejner. Jinak odpoví 403 a náhled nabídne lištu „Povolit přístup…“ s dialogem otevřeným přímo v dané složce.
- Vložení obrázku (přetažením nebo ze schránky) ho zkopíruje do `assets/` nebo `<název>.assets/` vedle dokumentu. Zápis do této složky potřebuje stejné povolení, o které se aplikace jednou zeptá.
- Nahrávání na server spouští příkaz nastavený uživatelem, s argumenty jako polem (nikdy přes shell) a jen když je v Nastavení výslovně zapnuté (F10).

## Důsledky a dluhy
- Externí příkaz běží v sandboxu aplikace, takže nástroje, které potřebují přístup mimo něj, nemusí fungovat. Stejná otázka přijde u Pandocu (F7). Pro distribuci mimo Mac App Store lze sandbox zvážit znovu.
- Nový dokument musí být před vložením obrázku uložený (obrázky se ukládají vedle něj).
