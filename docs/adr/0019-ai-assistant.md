# ADR 0019: Asistent AI u dokumentu

**Stav:** přijato (2026-09-26), implementace A1–A6 hotová (2026-09-26)

## Průběh implementace
- **A1 + A2 (2026-09-26):** Nastavení ▸ Obecné ▸ Pokročilé (přepínač, klíče tří poskytovatelů v Klíčence, ověření přes seznam modelů). Panel chatu jako poslední sloupec splitu (výchozí šířka 340 bodů, šířka se pamatuje), View ▸ Zobrazit asistenta ⌥⌘A. `AssistantSession` patří k `EditorSession` a vzniká líně. Streaming Anthropic Messages pro Claude a DeepSeek: překreslení nejvýš 30× za sekundu, Stop, citace a hledání se zobrazují, spotřeba tokenů je u odpovědi. Jádro je v `HashlineCore/Assistant` (JSON, parser SSE, kodek, dekodér streamu včetně bloků `thinking` a `tool_use` pro další kroky) a testy běží nad nahranými streamy v `Tests/HashlineCoreTests/Resources/*.sse`. U Opus 5 je zapnutý `fallbacks: "default"`, takže odmítnutý požadavek zkusí server znovu na doporučeném modelu.
- **A4 (2026-09-26):** nástroje `edit_document` (přesný úsek, musí být v textu právě jednou) a `rewrite_document` (celý text). Aplikace úpravu zúží na skutečně změněné znaky (nikdy nerozdělí složený znak), provede ji přes `NSTextView` a všechny úpravy jednoho pokynu uzavře do jedné skupiny Undo („Úprava asistentem“). Během práce je editor jen pro čtení. Stop přeruší práci a nedokončená volání nástrojů se neprovedou. Změněná místa se zvýrazní barvou akcentu do první úpravy uživatelem a chat ukáže jejich počet s tlačítkem Zobrazit. Neplatný nebo nejednoznačný vstup se vrátí modelu jako chyba nástroje, aby to zkusil znovu (nejvýš 25 kol na jeden pokyn).
- **A3 (2026-09-26):** OpenAI Responses bez stavu na serveru (`store: false`, šifrované uvažování přes `include: ["reasoning.encrypted_content"]`, výstupní položky se po volání nástrojů posílají zpět). Tvary událostí jsou převzaté z typů oficiálního SDK. Nástroje mají `strict: true`. Klient i sezení volí protokol přes `AssistantProtocol` (žádné větvení podle poskytovatele).
- **A5 (2026-09-26):** přepínač rešerše (glóbus) u pole pro zprávu, ve výchozím stavu vypnutý a jen u modelů, které hledání umí: Claude `web_search_20260209` (Haiku 4.5 `web_search_20250305`), OpenAI `web_search`. U DeepSeeku zůstává skrytý. Hledané dotazy a citace (jen http a https, klikatelné) jsou u odpovědi.
- **A6 (2026-09-26):** nad zhruba 100 000 tokeny (odhad 3 znaky UTF-16 na token) se odeslání jednou za konverzaci potvrzuje: „Přesto odeslat“, „Odeslat jen výběr“ (pak bez `rewrite_document`), „Zrušit“. Falešný poskytovatel `-HashlineAssistantFake YES` a kontrola v aplikaci `-HashlineAssistantSelfTest YES` (úprava v zámku, počet změn, jedno Undo, Stop) prošla. UI test `AssistantUITests` je napsaný, ale XCUITest se v této relaci nespustil (časový limit při zapínání automatizace). Latence psaní s otevřeným panelem je stejná jako bez asistenta (viz `docs/perf.md`).
- **Klíčenka:** zjištění, jestli je klíč uložený, čte jen atributy položky. Samotný klíč se čte nejvýš jednou za spuštění, až ho potřebuje první zpráva (nebo Ověřit), a pak zůstává v paměti (zrušený dotaz se nepamatuje). Ad-hoc podepsaná aplikace je pro Klíčenku po každém buildu a každé aktualizaci nová aplikace, takže se macOS zeptá na heslo znovu (dva dialogy: povolení a zápis oprávnění ke klíči). Trvale to vyřeší až podpis Developer ID (F11), protože pak Klíčenka pozná aplikaci podle týmu, ne podle otisku buildu.
- **Pole pro zprávu:** výchozí výška 5 řádků, úchyt nad polem mění výšku na 2–24 řádků (pamatuje se). Return odesílá, ⌥Return vloží nový řádek.
- **Dluhy:** DeepSeek: limit výstupu 32 000 a podpora nástrojů ve formátu Anthropic jsou ověřené jen dokumentací (klíč sám ověřený je). OpenAI nebylo vyzkoušené se skutečným klíčem. `AssistantUITests` spustit ručně. Počet tokenů na vstupu se u Claude a OpenAI počítá jinak (Claude bez tokenů z cache, OpenAI včetně nich).

## Kontext
Hashline měla AI mimo rozsah. Uživatel 2026-09-26 povolil výjimku. Asistent nejdřív vznikal v samostatné kopii projektu (Hashline AI) a týž den se rozhodlo, že se vydá jako běžná aktualizace Hashline (0.2.0), se stejnou identitou, aby se stará aplikace aktualizovala přes Sparkle. Podklady: `docs/research-ai-asistent.md`.

## Rozhodnutí
- **Skrytá volba:** asistent je ve výchozím stavu vypnutý. Zapíná se v Nastavení ▸ Obecné ▸ Pokročilé, kde se zadávají klíče API. Klíče jsou jen v Klíčence.
- **Poskytovatelé:** Claude, OpenAI a DeepSeek. DeepSeek se nabízí záměrně, volba poskytovatele je na uživateli. Upozornění uvádí, kam data odcházejí.
- **Protokoly:** Anthropic Messages (Claude, DeepSeek přes `/anthropic`) a OpenAI Responses. Přímé HTTP přes `URLSession`, žádná závislost.
- **Výběr modelu v chatu:** uživatel volí model přímo v okně chatu podle toho, co zrovna dělá. Nabízí se modely poskytovatelů, pro které je zadaný klíč.
- **Umístění:** chat je panel vpravo, další sloupec splitu (pamatuje si šířku jako ostatní sloupce).
- **Asistent upravuje dokument přímo:** pokyny typu „přepiš čtivěji“ nebo „ověř fakta a přepiš“ se provedou rovnou v textu. Každý pokyn je jeden krok Undo, upravená místa se zvýrazní a chat shrne, co se změnilo (u ověření faktů i se zdroji).
- **Zámek:** během práce asistenta je dokument jen pro čtení. Tlačítko Stop práci přeruší, provedené změny jdou vrátit.
- **Izolace:** každý dokument má vlastní konverzaci. Asistent vidí a mění jen svůj dokument, žádné jiné soubory, knihovnu ani nastavení.
- **Konverzace se po zavření dokumentu zahazuje**, na disk se neukládá.

## Identita
Vydává se jako Hashline: bundle ID `cz.hashline.Hashline`, repozitář github.com/Hessevalentino/hashline, feed Sparkle a klíč EdDSA beze změny. Klíče API jsou v Klíčence pod službou `cz.hashline.Hashline.assistant`.
