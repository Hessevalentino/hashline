# Průzkum: asistent AI pro dokument (Claude, OpenAI, DeepSeek)

**Stav:** průzkum, nic není rozhodnuté ani implementované (2026-09-26)

## Zadání

- Funkce je skrytá. Kdo projde nastavení, najde volbu „Povolit asistenta AI“ a pole pro klíč API.
- Teprve potom má každý otevřený dokument vlastní chat, kterým se dá s dokumentem pracovat: rešerše, přepracování obsahu, otázky.
- Okno je minimalistické, ale funkční.
- Každý dokument má izolované prostředí. Po přepnutí na jiný dokument se ukáže jeho chat a asistent nezasahuje nikam jinam.

## Střet s pravidly projektu

CLAUDE.md má AI v seznamu **mimo rozsah** a výchozí odpověď na nový nápad je „ne“. Implementace proto potřebuje tvoje výslovné rozhodnutí a nové ADR, které tuto výjimku zdůvodní. Návrh níže drží principy, které platí dál:

- Při vypnutí neexistuje žádný kód v cestě, žádné UI, žádná síť a žádná paměť navíc.
- Žádná závislost třetí strany: HTTP a SSE zvládne `URLSession`.
- Soubor zůstává pravdou: asistent jen navrhuje a změnu provede uživatel jedním krokem, který jde vrátit přes Undo.

## Poskytovatelé (ověřeno v dokumentaci 2026-09-26)

| | Claude (Anthropic) | OpenAI | DeepSeek |
|---|---|---|---|
| Endpoint | `POST https://api.anthropic.com/v1/messages` | `POST https://api.openai.com/v1/responses` | `https://api.deepseek.com/anthropic` (formát Anthropic) nebo `https://api.deepseek.com` (formát OpenAI, i Responses) |
| Klíč | hlavička `x-api-key` + `anthropic-version: 2023-06-01` | `Authorization: Bearer …` | `x-api-key` (formát Anthropic) nebo `Authorization: Bearer` |
| Streaming | SSE: `content_block_delta` / `text_delta`, `message_stop` | SSE se sémantickými událostmi (`stream: true`) | stejné jako zvolený formát |
| Modely | `claude-opus-5` (výchozí, $5/$25 za 1M tokenů), `claude-sonnet-5` ($2/$10), `claude-haiku-4-5` ($1/$5) | `gpt-6-astra` ($10/$50), `gpt-6-sol` ($2/$10), `gpt-6-luna` ($0,1/$0,5) | `deepseek-v4-pro` ($1,32/$3,96), `deepseek-flash` ($0,30/$1,20). Mimo špičku je poloviční cena. |
| Kontext | 1M (Haiku 200K) | 1,05M | 1M |
| Rešerše na webu | serverový nástroj `web_search_20260209` (Opus 5, Sonnet 5), citace ve výsledku | nástroj `{"type": "web_search"}`, citace jako anotace `url_citation` | vlastní vyhledávání v dokumentaci není. Ve formátu Anthropic jsou bloky `server_tool_use` / `web_search_tool_result` uvedené jako podporované, ale **neověřeno**, jestli DeepSeek hledání skutečně provede. |
| Úpravy přes nástroje | `tools` + `tool_use` / `tool_result` | function calling v Responses | `tool_use` / `tool_result` v obou formátech |
| Cache promptu | `cache_control` (ruční) | automatická | automatická (sleva za cache hit), `cache_control` ignoruje |
| Poznámky | Může přijít `stop_reason: "refusal"`, stav je potřeba zobrazit. Pro Opus 5 jsou serverové záložní modely (`fallbacks`). | Citace musí být v UI viditelné a klikatelné (podmínka OpenAI). | Staré aliasy `deepseek-chat` / `deepseek-reasoner` skončily 24. 7. 2026. Data se zpracovávají v Číně, to musí stát v upozornění. |

Swift nemá oficiální SDK od Anthropicu ani OpenAI, proto přímé HTTP. Ceny se mění často, a proto je v aplikaci pevně nedržet: stačí uvést odkaz na ceník poskytovatele.

### Doporučení: dva protokoly místo tří

DeepSeek nabízí formát Anthropic Messages. Stačí proto implementovat:

1. **Anthropic Messages** pro Claude a DeepSeek (liší se jen základní URL, modely a pár ignorovaných polí),
2. **OpenAI Responses** pro OpenAI.

Každý protokol je jeden `struct` s kodekem požadavku a parserem SSE nad `URLSession.bytes(for:)`, odhadem 250–400 řádků. Společné rozhraní:

```swift
protocol AssistantProvider: Sendable {
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error>
}
// AssistantEvent: .text(String), .citation(URL, title), .editProposal(EditProposal), .finished(StopReason), .usage(…)
```

## Nastavení (skryté)

- Nová záložka se nepřidává. V Nastavení ▸ Obecné je dole sbalená sekce **Pokročilé** a v ní přepínač „Povolit asistenta AI“ (ve výchozím stavu vypnutý).
- Po zapnutí se rozbalí: poskytovatel (Claude, OpenAI, DeepSeek), `SecureField` pro klíč, model a tlačítko **Ověřit klíč** (`GET /v1/models`; všichni tři ho mají). Pod tím je jednou větou popsané, co odchází: „Text dokumentu a vaše zprávy se posílají poskytovateli <X>. Platíte podle jeho ceníku.“ U DeepSeek je navíc uvedené zpracování v Číně.
- **Klíč jen v Klíčence:** `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, bez synchronizace. Nikdy v UserDefaults, v logu ani v exportu. V sandboxu funguje Klíčenka pro vlastní položky bez dalšího oprávnění.
- `com.apple.security.network.client` už aplikace má kvůli vzdáleným obrázkům a Sparkle, takže entitlements se nemění.

## Chat u dokumentu

### Umístění (produktové rozhodnutí, nutný tvůj výběr)

| Varianta | Plus | Mínus |
|---|---|---|
| **A. Panel vpravo jako další sloupec splitu** (doporučeno) | Využije hotové pamatování šířek (`EditorSession+Split`), nativní vzhled, nezakrývá text. | Na malém displeji ubírá místo náhledu. |
| B. Pruh dole pod editorem a náhledem | Plná šířka pro odpovědi, pole pro zadání je vždy po ruce. | Ubírá výšku textu. |
| C. SwiftUI `.inspector` | Nativní animace. | Koliduje s vlastním NSSplitView a úpravou titulku, hůř se ladí. |

Minimalistická podoba (varianta A):

```
┌ Asistent ───────────── Claude Opus 5 ▾ ┐
│ ▸ Ty: Zkrať úvod na tři věty.          │
│ ▸ Asistent: Návrh úpravy (odstavec 1)  │
│   [Zobrazit rozdíl] [Použít] [Zahodit] │
│   Zdroj: example.com ↗                 │
├────────────────────────────────────────┤
│ Zeptej se na dokument…     [Rešerše ⌥] │
└────────────────────────────────────────┘
```

- Tlačítko v liště a zkratka (např. ⌥⌘A) existují jen při zapnutém asistentovi.
- Odpovědi se kreslí nativně přes `AttributedString(markdown:)`, bez WKWebView. Rozpočet paměti WebKitu zůstane pro náhled. Odkazy se otevírají v prohlížeči jen po kliknutí, jen http(s).
- Streamovaný text se překresluje nejvýš 30× za sekundu. Síť běží mimo hlavní vlákno, takže latence psaní se nezmění.

### Izolace

- `AssistantSession` patří k `EditorSession` stejně jako `find` a `navigation`. Každé okno nebo záložka má vlastní konverzaci. Přepnutí dokumentu tak zobrazí chat toho dokumentu bez dalšího kódu.
- **Kontext tvoří jen text tohoto dokumentu** (a výběr, pokud je). Asistent nevidí knihovnu, jiné soubory ani disk. Obrázky a přílohy se v první verzi neposílají.
- Konverzace žije v paměti, dokud je dokument otevřený. Na disk se neukládá, protože soubor je pravda a databáze není. Uložení konverzace by bylo samostatné rozhodnutí.
- **Úpravy jen jako návrh:** model dostane jediný nástroj, třeba `propose_edit {original, replacement, reason}`. Aplikace najde `original` v aktuálním textu a ukáže rozdíl. Změna proběhne až po kliknutí na **Použít**, jako jedna úprava přes `shouldChangeText`/`replaceCharacters`, takže ji ⌘Z vrátí. Když se text mezitím změnil a `original` už v něm není, návrh zešedne.
- **Prompt injection:** dokument ani výsledky hledání nemůžou nic spustit, protože jediná akce je návrh úpravy téhož dokumentu, který potvrzuje uživatel. Systémový prompt obsah dokumentu výslovně označí jako data, ne jako pokyny.

### Rešerše

- **Claude:** `web_search_20260209` v `tools`, s volitelným `max_uses`. Výsledky a citace přijdou v jedné odpovědi a chyby hledání chodí jako blok s `error_code`, ne jako výjimka.
- **OpenAI:** `{"type": "web_search"}`. Citace jsou anotace `url_citation` a musí být viditelné a klikatelné.
- **DeepSeek:** rešerše skrýt, dokud se pokusem s klíčem neověří, že hledání skutečně funguje.
- Rešerše je přepínač u pole pro zadání, ve výchozím stavu vypnutý, protože každé hledání stojí peníze navíc.

## Velké dokumenty a cena

- 1MB dokument má zhruba 250–300 tisíc tokenů. Vejde se všude, ale jedna otázka nad ním u Opus 5 stojí kolem $1,5. Nad zhruba 100 tisíc tokenů zobrazit před odesláním odhad a nabídnout poslání jen výběru.
- **Cache:** dokument jde na začátek konverzace jako první blok. U Claude s `cache_control`, u OpenAI a DeepSeek se cachuje automaticky. Po úpravě dokumentu se pošle nová verze a cache se jednou minou. V první verzi jednoduše, bez diffů.
- Po každé odpovědi se zobrazí spotřebované tokeny (z `usage`). Odhad v měně nechat na uživateli, protože ceníky se mění.

## Výkonnostní rozpočet

| Metrika | Dopad |
|---|---|
| Studený start, otevření souboru | žádný: asistent se vytváří líně až při prvním otevření panelu |
| Latence psaní | žádná: síť a parsování SSE běží mimo hlavní vlákno, UI se překresluje nejvýš 30×/s |
| Paměť | vypnuto 0 MB, otevřený panel odhadem 2–5 MB (text konverzace + SwiftUI) |
| Velikost .app | desítky až nízké stovky KB, žádná závislost |
| CPU v klidu | 0 % (žádné dotazování ani časovače, spojení jen během odpovědi) |

## Plán po krocích

| Krok | Obsah | Odhad |
|---|---|---|
| A0 | Rozhodnutí o rozsahu + ADR 0019 | — |
| A1 | Nastavení, Klíčenka, ověření klíče pro tři poskytovatele | 1 den |
| A2 | Panel chatu, `AssistantSession` na dokument, streaming Anthropic Messages (Claude, DeepSeek) | 2 dny |
| A3 | OpenAI Responses | 1 den |
| A4 | Návrhy úprav: nástroj, rozdíl, Použít/Zahodit, Undo | 2 dny |
| A5 | Rešerše: web search a citace (Claude, OpenAI), ověření u DeepSeek | 1 den |
| A6 | Lokalizace, UI test kritického toku (s falešným poskytovatelem přes DEBUG háček), měření | 1 den |

Testy: kodeky a parser SSE jsou čisté funkce (Swift Testing, nahrané ukázky streamů), UI test s falešným poskytovatelem bez sítě. Skutečná volání stojí peníze, pouštět je jen ručně.

## Otevřené otázky

1. Povolit výjimku z pravidla „AI mimo rozsah“?
2. Umístění panelu: A (vpravo), B (dole) nebo C?
3. Má se konverzace po zavření dokumentu zahodit (návrh), nebo ukládat vedle souboru?
4. DeepSeek i přes zpracování dat v Číně?
5. Výchozí modely: Claude Opus 5, GPT-6 Sol a DeepSeek V4 Pro (návrh), nebo levnější varianty?
6. Pošle se vždy celý dokument, nebo ve výchozím stavu jen výběr, když nějaký je?

## Zdroje

- Anthropic Messages API, streaming, nástroje a web search: dokumentace Claude API (bundled referenční skill, 2026-06).
- DeepSeek: [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing), [Your First API Call](https://api-docs.deepseek.com/), [Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api)
- OpenAI: [Models](https://developers.openai.com/api/docs/models), [Web search](https://developers.openai.com/api/docs/guides/tools-web-search), [Streaming](https://developers.openai.com/api/docs/guides/streaming-responses)
