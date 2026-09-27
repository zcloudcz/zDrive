# Zadání 12: Retence verzí podle stáří

> Pracuješ v repozitáři zDrive (.NET 8). Nejdřív si přečti `CLAUDE.md`
> (sekce Blob versioning) a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, komunikace česky, kód anglicky.

## Cíl

Kromě limitu počtu verzí půjde nastavit i minimální dobu, po kterou se verze
drží. Konkurence komunikuje retenci ve dnech (Proton až 365, Dropbox
30–365), my dnes jen „10 verzí". Konkrétní hodnoty pro tarify rozhodne
člověk. Implementace musí jen umět obojí.

## Současný stav

- `VersioningOptions` (`FileService.Application/Options/VersioningOptions.cs:8`),
  `"Versioning": { "MaxVersionsPerFile": 10 }` v `src/services/Api/appsettings.json:30`.
- Mazání verzí je jen v `CreateFileVersionCommandHandler.cs`:
  `SelectVersionsToPruneAsync` (ř. 90-104) nechá nejnovějších N-1 a zbytek
  smaže (ř. 76-77). Uvolněné bajty odečte v kontrole kvóty (ř. 42-49).
  Hodnota ≤ 0 mazání vypne. Obnova verze aplikuje stejnou retenci
  (`docs/mvp-completion.md`).
- Kvóta (`StorageQuota.cs:21-33`) = součet `file_versions.SizeBytes`
  uživatele. **Verze i koš se počítají.**

## Rozsah

1. Nová volba `Versioning:MinRetentionDays` (výchozí `0` = dnešní
   chování, beze změny).
2. Pravidlo: verze je kandidát na smazání, jen když je **mimo** posledních
   `MaxVersionsPerFile` **a zároveň** starší než `MinRetentionDays`.
   Aktuální verze se nikdy nesmaže. Zvaž, zda má `MaxVersionsPerFile`
   zůstat tvrdým stropem. Popiš sémantiku v PR a v `CLAUDE.md` a zeptej se,
   pokud si nejsi jistý.
3. Protože se dnes maže jen při vložení nové verze, bez nové verze by staré
   verze nikdy nevypršely. Pro `MinRetentionDays` to nevadí, protože jde o
   minimum, ne maximum. **Nepřidávej periodický job**, pokud ho zadání
   nepotřebuje.
4. Hodnoty per tarif: zatím jedna globální hodnota. Připrav to tak, aby šla
   později nahradit hodnotou z claimu (vzor `quota_bytes` v
   `StorageQuota`), ale abstrakci nepřidávej.

## Akceptační kritéria

- [ ] `MinRetentionDays = 0` → chování identické s dneškem (existující
      testy beze změny).
- [ ] Unit testy výběru kandidátů: mladé verze nad limitem se nemažou,
      staré ano, aktuální nikdy.
- [ ] Integrační test: kvóta s nesmazanými mladými verzemi se počítá
      správně.
- [ ] `CLAUDE.md` sekce Blob versioning aktualizovaná o nový klíč.

## Výstup

Jeden malý PR.
