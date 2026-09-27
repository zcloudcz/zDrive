# Zadání 06: macOS desktop (entitlements, bookmarky, menu bar)

> Pracuješ v repozitáři zDrive (Flutter klient v `src/client/zdrive_app`).
> Nejdřív si přečti `CLAUDE.md` a dodržuj ho: minimální změny, platformní
> kód izolovaný, Bloc/Cubit, komunikace česky, kód anglicky. Potřebuješ
> macOS s Xcode. Pokud ho nemáš, napiš to hned na začátku a omez se na
> změny ověřitelné bez něj (a označ je v PR jako neověřené).

## Cíl

Release build pro macOS se přihlásí, synchronizuje zvolenou složku i po
restartu a chová se jako desktopový sync klient (běží v menu baru). Na
Windows už to funguje.

## Současný stav

- `macos/Runner/Release.entitlements` má jen `app-sandbox` a
  `files.user-selected.read-write`. **Chybí
  `com.apple.security.network.client`**, takže sandboxovaný release nemůže
  volat API. `DebugProfile.entitlements` má navíc `network.server` a JIT.
- **Chybí security-scoped bookmarky.** Sync root je jen string v Hive
  (`lib/core/storage/app_preferences.dart:10,43-53`), vybraný přes
  `FilePicker.platform.getDirectoryPath()` (`sync_page.dart:250`). Po
  restartu sandbox přístup nepovolí, `SyncCoordinator._syncOnce` hodí
  `SyncFolderMissingException` (`sync_coordinator.dart:178`) a watcher
  (`sync_bloc.dart:309`) selže.
- `flutter_secure_storage` na macOS typicky potřebuje keychain sharing
  entitlement. Ověř, zda release build ukládá tokeny.
- `AppDelegate.swift:6-8` ukončí aplikaci po zavření posledního okna.
  Aplikace nemá menu bar ikonu ani spuštění po přihlášení.
- Windows referenční chování: tray (`windows/runner/tray_window.cpp`),
  `--start-hidden` (`main.cpp:26-35`), kanál `zdrive/windows_lifecycle`
  (`flutter_window.cpp:35-52`).
- `lib/features/sync/sync_support.dart:14` povoluje desktop sync na Windows
  a macOS.

## Rozsah

1. Entitlements (Release i DebugProfile): `network.client`,
   `files.bookmarks.app-scope`, keychain dle potřeby `flutter_secure_storage`.
2. **Bookmarky:** MethodChannel `zdrive/macos_bookmarks` v Swiftu (`macos/Runner/`)
   s metodami `create(path) -> base64`, `resolve(base64) -> {path, stale}`
   (volá `startAccessingSecurityScopedResource`) a `release(path)`. V Dartu
   tenká služba s no-op implementací pro jiné platformy. Při výběru složky
   ulož bookmark vedle cesty. Při startu ho resolvuj ještě před prvním
   `syncOnce`. Stale bookmark obnov. Nevalidní bookmark → stav „složka
   nedostupná, vyber znovu", ne pád.
3. **Menu bar:** `NSStatusItem` s položkami Otevřít zDrive, Otevřít složku,
   Synchronizovat, Ukončit. Stejné texty jako Windows tray; lokalizaci
   převezmi z Dartu přes kanál, pokud to tak dělá Windows. Zavření okna
   aplikaci neukončí.
4. **Spuštění po přihlášení:** `SMAppService.mainApp` (macOS 13+). Ověř
   `LSMinimumSystemVersion` (dnes 10.15) a na starších systémech funkci
   skryj. Skryté spuštění analogicky k `--start-hidden`.
5. Nic neměň na Windows chování.

## Mimo rozsah

Podpis a notarizace v CI (zadání 07), File Provider / placeholdery, Finder
extension.

## Akceptační kritéria

- [ ] `flutter build macos --release` → přihlášení funguje, tokeny přežijí
      restart aplikace.
- [ ] Zvolená složka se synchronizuje i po restartu aplikace a po restartu
      počítače.
- [ ] Zavření okna nechá aplikaci v menu baru. Ukončit ji ukončí.
- [ ] Dart testy služby bookmarků (fake kanálu) a integrace do sync flow
      (resolve před prvním sync, chyba → správný stav UI).
- [ ] Existující testy zelené (`flutter test`).

## Výstup

Jeden PR s postupem ručního ověření na macOS v popisu.
