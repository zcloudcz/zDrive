# Zadání 04: Náhledy obrázků, textu a PDF

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, Bloc/Cubit, feature-first struktura,
> komunikace česky, kód anglicky. Pokud je něco v zadání nejasné nebo
> neodpovídá kódu, zastav se a zeptej se.

## Cíl

Klepnutí na soubor v prohlížeči souborů (a na veřejné stránce sdílení)
otevře náhled místo okamžitého stažení. Náhled je jen na klientovi,
**bez změn backendu** kromě bodu 1. Platí pro web, Windows, macOS, Android
a iOS. Video je mimo rozsah (zadání 05).

## Současný stav

- `lib/features/files/presentation/pages/file_browser_page.dart:494-500`:
  `_onFileTap` → `_downloadFile` → `saveFileStream(...)`.
- Stahování: `file_repository_impl.dart:326-333` (`downloadFileStream`)
  → `file_upload_data_source.dart` (manifest + chunky
  `GET .../chunk/{hash}/bytes`, ověření SHA-256 v `assembleVerifiedFileStream`,
  ř. 367-410). Existuje i `downloadFile()` vracející `Uint8List`
  (`file_repository_impl.dart:317-323`).
- Veřejné sdílení: `lib/features/share_link/`. Stahuje stejným vzorem přes
  `X-Share-Grant` (`share_link_data_source.dart:99-103`,
  `share_link_cubit.dart:247`). Řádek souboru dnes na klepnutí nereaguje
  (`share_link_page.dart:802`).
- MIME: `FileItem.mimeType` existuje (`features/files/domain/file_item.dart:8`),
  ale **klient ho při uploadu neposílá** (`file_repository_impl.dart:278-284`,
  přestože `file_remote_data_source.dart:65,80` to umí). V DB je většinou
  `null`.
- `pubspec.yaml`: žádné image, PDF ani video balíčky. Web používá `package:web`
  + `dart:js_interop`. Podmíněné importy mají vzor `file_saver.dart`.
- Popup menu položky: `widgets/file_list_item.dart:57-84`,
  `widgets/file_grid_item.dart:72-113`. Položka „Stáhnout" tam není.

## Rozsah

1. **MIME při uploadu:** odvoď typ z přípony (balíček `mime`, BSD-3) a pošli
   ho při vytváření uzlu. Platí i pro upload přes sdílený odkaz, pokud
   to jde v klientovi. Backend nech, jak je.
2. **Detekce typu náhledu** podle `mimeType`, jinak podle přípony: image
   (jpg, png, gif, webp, bmp; HEIC jen tam, kde ho umí platforma, jinak
   „náhled nedostupný"), text (txt, md, json, csv, log, xml, yaml, kód;
   max 1 MB, UTF-8 s náhradou neplatných znaků), pdf.
3. **Limit velikosti** pro náhled (výchozí 50 MB, konstanta). Nad limitem a
   u nepodporovaných typů se zobrazí dialog s ikonou, velikostí a tlačítkem
   Stáhnout.
4. **Preview stránka nebo dialog** (nový widget ve `features/files/presentation/`,
   vlastní Cubit): načte bajty přes existující ověřené stahování a zobrazí:
   - image: `Image.memory` + `InteractiveViewer` (zoom),
   - text: `SelectableText`, monospace,
   - pdf: balíček **`pdfrx`** (MIT, podporuje web i všechny cílové platformy);
     před použitím ověř licenci a velikost webového bundle (pdfium wasm).
     Pokud je bundle neúměrný, navrhni alternativu a zeptej se.
   - Akce v liště: Stáhnout (dnešní flow), Sdílet (existující dialog),
     Zavřít. Šipky ←/→ mezi soubory v aktuální složce jsou volitelné; udělej
     je, jen pokud jsou levné.
   - Stav načítání s progresem (chunky) a chyba s „Zkusit znovu".
5. **Tap chování:** soubor → náhled. Do popup menu přidej položku „Stáhnout".
   Na desktopu dvojklik = náhled, pokud je dnes klik = výběr. Ověř dnešní
   chování a nic jiného neměň.
6. **Share page:** stejný widget s datovým zdrojem přes share grant.
   Abstrahuj jen to, co se liší: `Stream<Uint8List> Function()`.
7. Lokalizace nových textů do `.arb`.

## Mimo rozsah

Video a audio, Office dokumenty (docx/xlsx), miniatury v seznamu souborů,
streamování, změny backendu.

## Akceptační kritéria

- [ ] Klepnutí na jpg/png/pdf/txt otevře náhled na webu i desktopu (ověř
      aspoň `flutter run -d chrome` a `flutter build windows` / web build).
- [ ] Soubor nad limitem nebo nepodporovaného typu nabídne stažení.
- [ ] Nový upload ukládá `mimeType` (ověř přes API odpověď v testu data
      source).
- [ ] Unit testy: detekce typu (MIME i přípona), Cubit stavy (loading,
      loaded, error, tooLarge, unsupported).
- [ ] Widget testy: image a text náhled; tap na soubor otevře náhled.
- [ ] `flutter analyze` bez chyb, `flutter test` zelené.

## Výstup

Jeden PR se screenshoty (web + jedna nativní platforma) v popisu.
