# ADR 0002: Xcode projekt z XcodeGen

**Stav:** přijato (F0)

## Kontext
Ručně udržovaný `project.pbxproj` je nečitelný a při slučování změn konfliktní.

## Rozhodnutí
Projekt se generuje z `project.yml` nástrojem XcodeGen (vývojový nástroj, do aplikace nic nepřidává). `Hashline.xcodeproj` není v gitu. Testovatelné jádro `HashlineCore` je Swift Package, takže běží i přes `swift test`.

## Důsledky
Po přidání souborů nebo změně nastavení je potřeba spustit `xcodegen generate`.
