# ADR 0003: UI testy bez save panelu

**Stav:** přijato (F0)

## Kontext
V sandboxu běží otevírací a ukládací panel mimo proces aplikace (Powerbox) a XCUITest ho spolehlivě neovládne. Runner UI testů je navíc sám v sandboxu a nepřečte soubory aplikace.

## Rozhodnutí
Debug build přijímá argument `-HashlineUITestDocument <jméno>`, který otevře soubor v `tmp` kontejneru aplikace a případně ho vytvoří (`App/UITestSupport.swift`). Kontrolu bajtů po uložení dělá `scripts/verify-f0.sh` mimo runner.

## Důsledky
Ukládací panel pro nový soubor se automaticky netestuje, ověřuje se ručně. Háček v Release buildu není.
