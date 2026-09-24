# ADR 0018: Distribuce a aktualizace (F11)

**Stav:** přijato (2026-09-24)

## Kontext
Uživatel nemá účet Apple Developer, takže podpis Developer ID ani notarizace nejsou možné (rozhodnutí 2026-09-24). Aktualizace mají chodit z veřejného GitHub repozitáře (rozhodnutí 2026-09-24).

## Rozhodnutí
- **Podpis:** ad-hoc (`codesign -s -`), hardened runtime vypnutý (ADR 0016). Gatekeeper aplikaci stáhnutou z internetu napoprvé zablokuje. README a web popisují povolení výjimky v Nastavení systému ▸ Soukromí a zabezpečení ▸ Přesto otevřít (na macOS 15+ už pravý klik ▸ Otevřít nestačí) a alternativu `xattr -dr com.apple.quarantine`.
- **DMG:** `hdiutil` (UDZO), aplikace a odkaz na /Applications, bez další závislosti (`create-dmg` není potřeba).
- **Sparkle 2** (předem schválená závislost; vlastní aktualizátor by byl řádově víc kódu a bez ověřeného instalátoru): appcast `appcast.xml` v kořeni repa (`SUFeedURL` = raw URL), DMG v GitHub Release. Aktualizace ověřuje podpis EdDSA (`SUPublicEDKey`), který ad-hoc podpisu nevadí. Sandbox: `SUEnableInstallerLauncherService` a výjimky mach-lookup `…-spks` a `…-spki`. Síť už aplikace má (`network.client`), takže službu pro stahování Sparkle nepotřebuje. Kontrola jednou týdně (`SUScheduledCheckInterval`). Sparkle se na automatickou kontrolu zeptá při druhém spuštění a do té doby nic neposílá. Profil systému se neposílá. Debug a Profile buildy aktualizace nehledají.
- **Soukromý klíč** Sparkle je v přihlašovací Klíčence uživatele. Kdo ho ztratí, nemůže vydat aktualizaci, kterou stávající instalace přijmou. Záloha: `generate_keys -x soubor` na bezpečné místo.
- **Repozitář** obsahuje zdroje aplikace, testy, fixtures (bez generovaných velkých souborů), dokumentaci a web (`WEB/`, nasazovaný zvlášť na hashline.hesse.works).

## Důsledky
- Velikost .app 13 MB (Sparkle ~3 MB), v rozpočtu 15 MB.
- Každé vydání: zvednout verzi v Info.plist, doplnit CHANGELOG, spustit `scripts/release.sh`.
- Kdyby později vznikl účet Apple Developer: podepsat Developer ID, zapnout hardened runtime, notarizovat. Sparkle i appcast zůstávají.
