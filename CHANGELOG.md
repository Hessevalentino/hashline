# Změny

## 0.3.0 – 2026-09-26

- Asistent AI umí lokální modely přes Ollamu a LM Studio: text dokumentu neopustí Mac a není potřeba klíč API. V Nastavení ▸ Obecné ▸ Pokročilé stačí u Ollamy nebo LM Studia kliknout na Připojit (výchozí adresa localhost, jde změnit). Model se vybírá v chatu jako dosud.
- Claude, OpenAI a DeepSeek fungují beze změny.

## 0.2.0 – 2026-09-26

- Asistent AI u dokumentu (volitelný, ve výchozím stavu vypnutý): zapíná se v Nastavení ▸ Obecné ▸ Pokročilé, kde zadáte vlastní klíč API pro Claude, OpenAI nebo DeepSeek. Klíče jsou jen v Klíčence. Ikona robota v liště (⌥⌘A) se objeví až po zapnutí a zadání klíče.
- Chat vpravo vedle náhledu, pro každý dokument vlastní. Model se volí přímo v chatu. Asistent vidí jen svůj dokument, konverzace se neukládá.
- Pokyny jako „přepiš úvod čtivěji“ nebo „zkrať výběr“ asistent provede rovnou v textu. Během práce je dokument jen pro čtení, změněná místa se zvýrazní a celý pokyn vrátí jedno ⌘Z. Tlačítko Stop práci přeruší.
- Volitelná rešerše na webu (Claude, OpenAI) se zdroji jako odkazy. U velkých dokumentů se před odesláním zobrazí odhad tokenů a nabídka poslat jen výběr.
- Nová ikona aplikace

## 0.1.6 – 2026-09-25

- Fix visual problems UI

## 0.1.5 – 2026-09-25

- Dělicí čáry mezi knihovnou, editorem a náhledem končí pod lištou, už neprocházejí titulkovým pruhem
- Šířka knihovny a poměr editoru a náhledu se pamatují pro všechna okna a dokumenty i po restartu, dokud dělič znovu nepřetáhnete
- Tlačítko náhledu přepne z režimu čtení rovnou do rozdělení editor a náhled, není potřeba nejdřív vypnout čtení
- Dokument otevřený z knihovny v režimu čtení už krátce neprobliká v rozdělení

## 0.1.4 – 2026-09-24

- Knihovna ukazuje název souboru (jako Finder), ne první nadpis; přejmenování souboru se v ní hned projeví. Nadpis je vidět v náhledu textu pod názvem.

## 0.1.3 – 2026-09-24

- Přejmenování dokumentu přímo v knihovně: pravé tlačítko ▸ Přejmenovat… (v seznamu i ve stromu složek), otevřené okno se přesune s ním
- Dělicí čára mezi editorem a náhledem si pamatuje polohu: platí pro všechna okna i po restartu, dokud ji znovu nepřetáhnete
- Sdílení vždy posílá soubor .md s aktuálním textem (i neuloženým), taky u dokumentu bez názvu
- Soubor ▸ Poslat přes AirDrop… a Soubor ▸ Sdílet…, v knihovně Sdílet a AirDrop v kontextové nabídce
- Soubor ▸ Exportovat jako Markdown… (⌥⌘E): kopie .md do libovolné složky přímo v nabídce Soubor

## 0.1.2 – 2026-09-24

- Mazání dokumentů v knihovně: pravé tlačítko ▸ Přesunout do koše (nebo ⌘⌫), v seznamu i ve stromu složek
- Čtecí režim v liště (tlačítko s knížkou, ⌘/): jen vykreslený dokument jako čitelná stránka se sloupcem uprostřed
- Export ▸ Markdown…: kopie dokumentu kamkoli v systémovém okně pro uložení
- Oprava: okno otevřené ve čtecím režimu zůstávalo prázdné
- Čeština pro položky aktualizací

## 0.1.1 – 2026-09-24

- Úkolové položky v náhledu, exportu a Quick Looku už nemají vedle zaškrtávátka navíc odrážku
- Copyright a odkaz na zdrojový kód v okně O aplikaci
- Hashline je open source pod licencí MIT

## 0.1.0 – 2026-09-24

První veřejné vydání.

- Editor Markdownu se zvýrazněnou syntaxí a živým HTML náhledem (rozvržení podle MacDownu)
- Formátovací lišta, přepínač světlého a tmavého vzhledu, režimy čtení, soustředění a psacího stroje
- Knihovna dokumentů, osnova, hledání v knihovně, rychlé otevření, najít a nahradit s regexem
- Tabulky, poznámky pod čarou, obsah, emoji, matematika, diagramy Mermaid, obrázky
- Export do HTML, PDF, PNG a přes Pandoc; import přes Pandoc
- Témata, čeština a angličtina, Quick Look, Služby, přístupnost
- Bezpečnost: sandbox, sanitizace HTML, ochrana proti nepřátelským dokumentům
- Aktualizace přes Sparkle (jednou týdně, po souhlasu)
