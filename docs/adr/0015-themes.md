# ADR 0015: Témata (F8)

**Stav:** přijato (2026-09-24)

## Kontext
F8: 2–3 světlá a tmavá témata z MacDownu, formát `theme.json` + `theme.css`, načtení bez restartu, volba písma, výšky řádku a šířky textu. Kritérium: přepnutí bez nového parsování.

## Rozhodnutí
- **Formát:** téma je složka `Název.hashlinetheme`. `theme.json` popisuje editor: pozadí, text, kurzor, výběr, styly značek podle názvů highlighteru (`H1`…`REFERENCE`, velikosti pro 14 pt, škálují se s písmem) a paletu tříd highlight.js pro kód. `theme.css` je celé CSS náhledu a exportu včetně barev highlight.js. `ThemeDefinition.decode` hlásí neznámé značky a špatné barvy, takže překlep se neztratí. Chyby uživatelských témat ukazuje Nastavení.
- **Vestavěná:** Paper (dřív Mou Paper+ a GitHub2) a Tomorrow Night (Tomorrow+ a Clearness Dark), obě převedená z MacDownu (MIT). K nim Solarized Light a Dark s paletou Ethana Schoonovera (MIT) na layoutu GitHub2. Formát `.style` z MacDownu už aplikace nenačítá (parser `StyleTheme` zůstává jako vnitřní model).
- **Volba:** zvlášť téma pro světlý a pro tmavý vzhled systému. Náhled má obě CSS s `prefers-color-scheme`, takže systém přepíná bez zásahu aplikace. Export používá vždy světlé téma.
- **Bez restartu:** `ThemeStore` sleduje uživatelskou složku přes FSEvents. Změna tématu, výběru nebo písma pošle `hashlineThemeChanged`. Editor přestyluje z existujícího parsování (`restyleAll`, žádné parsování) a náhled vymění obsah dvou `<style>` přes JavaScript v izolovaném světě (bez nového načtení a bez ztráty scrollu).
- **Rychlost přepnutí:** synchronně se přestyluje jen viewport TextKitu 2 s rezervou 2 000 znaků. Zbytek resetuje a obarví průchod na pozadí po 4ms dávkách, včetně prázdných řádků mezi bloky a bez front matter. Dřív reset celého dokumentu stál ~350 ms na 1 MB.

## Důsledky a dluhy
- Při rychlém scrollu hned po přepnutí může chvíli být vidět text ve starém tématu (průchod na pozadí na 1 MB trvá ~1,5–2,5 s).
- Písmo náhledu určuje CSS tématu. Volba písma v Nastavení platí jen pro editor.
- Delegát focus mode je nastavený jen při zapnutém režimu (jinak by nahrazoval každý fragment layoutu).

## Dodatek 2026-09-24: přepínač vzhledu v liště
Na přání uživatele je v liště přepínač ☀︎ [ ] ☾. Nastavuje `NSApp.appearance` (světlý nebo tmavý), takže se přepne editor, náhled (`prefers-color-scheme`) i volba tématu pro daný vzhled. Režim „Podle systému“ (výchozí, `appearance = nil`) vrací View ▸ Appearance a Nastavení ▸ Vzhled. Přepínač sleduje `NSApp.effectiveAppearance`, takže se pohne i při změně systému. Identifikátor lišty se změnil na `cz.hashline.format.2`, jinak by uložené přizpůsobení lišty novou položku skrylo.
