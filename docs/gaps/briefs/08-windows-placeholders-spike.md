# Zadání 08: Spike: placeholdery ve Windows přes Cloud Files API

> Pracuješ v repozitáři zDrive (Flutter klient v `src/client/zdrive_app`).
> Nejdřív si přečti `CLAUDE.md` a `docs/adr/*` (formát ADR). Komunikace
> česky, kód anglicky. **Tohle je spike: výstupem je ADR + prototyp,
> ne produkční změna.** Potřebuješ Windows 10 1809+ nebo Windows 11
> s Visual Studiem (C++ desktop workload).

## Otázka

Dokážeme v zDrive udělat Files On-Demand jako OneDrive? V Průzkumníku by
byly vidět všechny soubory, cloud-only jako placeholder s ikonou mráčku, a
otevření by soubor transparentně stáhlo (hydratace). Kolik to bude stát a
jaká jsou rizika?

## Současný stav

- Cloud-only položka nemá na disku **nic** (`lib/features/sync/data/pull_sync_service.dart:63-69`).
  Pin/hydrate/free-up řeší aplikace (`sync_coordinator.dart:321-345`).
  Stav je v sqflite mirroru (`mirror_files.downloaded`, `pinned_items`).
- Nativní kód: jen tray a kanál `zdrive/windows_lifecycle`
  (`windows/runner/*`). Žádné FFI, runner linkuje jen `dwmapi` a `shell32`.
- **Instalátor je IExpress** (`packaging/windows/`): per-user bez admin
  práv do `%LOCALAPPDATA%\Programs\zDrive\releases\<version>`. Nemá identitu
  balíčku (MSIX), takže manifest extension `cloudfiles` nejde. Cesta k exe
  se mění s každou verzí.
- Stahování chunků s ověřením hashe: `lib/features/files/data/file_upload_data_source.dart`.

## Co zjistit a doložit

1. **Registrace sync root bez MSIX:** `StorageProviderSyncRootManager.Register`
   (WinRT) vs. `CfRegisterSyncRoot`. Co vyžaduje (identita balíčku? admin?),
   jak se chová při změně cesty k exe po updatu, odregistrace při
   odinstalaci. Dá se to vyřešit stabilním shimem
   (`%LOCALAPPDATA%\Programs\zDrive\zDrive.exe`, který spouští aktuální
   verzi)?
2. **Architektura:** `CfConnectSyncRoot` callbacky (`FETCH_DATA`,
   `FETCH_PLACEHOLDERS`, …) musí běžet, i když Flutter UI neběží? Možnosti:
   (a) C++ plugin uvnitř Flutter procesu (aplikace stejně běží v tray),
   (b) samostatný malý nativní proces. Jak předávat data: FFI vs.
   MethodChannel vs. pojmenovaná roura. Kdo stahuje chunky: Dart
   (znovupoužití ověřování hashů), nebo nativně?
3. **Mapování na dnešní model:** placeholder ↔ mirror řádek s
   `downloaded=false`, pin ↔ `CF_PIN_STATE_PINNED`, free-up ↔
   `CfDehydratePlaceholder`. Co se stane s dnešní logikou „nic na disku"
   (scanner, karanténa kolizí v `local_change_scanner.dart:320-349`)?
4. **Migrace existujících instalací** (navazuje na #64 migrační dialog).
5. **Prototyp:** minimální C++ kód, který zaregistruje sync root nad testovací
   složkou, vytvoří 2–3 placeholdery s pevnými daty a obslouží
   `FETCH_DATA` z paměti. Stačí samostatný konzolový projekt v
   `spikes/windows-cfapi/` nebo větev. Nemá být napojený na Flutter.
6. **Odhad** implementace v člověkodnech po částech a seznam rizik
   (antiviry, OneDrive koexistence, Windows verze, testovatelnost v CI).

## Výstup

- `docs/adr/0004-windows-cloud-files-placeholders.md` ve formátu stávajících
  ADR, se stavem **Proposed**, doporučením (ano / ne / až po X) a
  odhadem.
- Prototyp (pokud se povede) + přesný postup, jak ho spustit.
- PR jen s ADR a spike složkou. **Žádné změny produkčního kódu.**
