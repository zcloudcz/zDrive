# Zadání 11: Mobilní auto-backup fotek (Android + iOS)

> Pracuješ v repozitáři zDrive (Flutter klient v `src/client/zdrive_app`).
> Nejdřív si přečti `CLAUDE.md` a dodržuj ho (platformní kód izolovaný,
> Bloc/Cubit, testy, komunikace česky, kód anglicky). Potřebuješ Android
> zařízení nebo emulátor a pro iOS Mac s Xcode a fyzické zařízení (background
> tasky se v simulátoru chovají jinak). **Nejdřív pošli krátký návrh
> (balíčky, cílová složka, deduplikace, chování na pozadí per OS) a počkej
> na schválení.**

> **Předpoklad:** zadání 09 mergnuté. Fotky nahrané do disku se zpracují
> serverem, klient je jen nahrává.

## Cíl

Po zapnutí v nastavení aplikace nahrává nové fotky a videa z galerie
telefonu do složky „Fotky z telefonu/<název zařízení>". Na popředí
okamžitě, na pozadí „best effort" podle možností OS.

## Současný stav

- Žádný background ani galerijní kód (workmanager, photo_manager, BGTask) v
  `lib/`, `android/`, `ios/` ani `pubspec.yaml`.
- iOS už má photo permission kvůli pickeru (commit `ee4dbdf`). Zkontroluj
  `Info.plist` texty.
- Upload: `lib/features/files/data/file_upload_data_source.dart`
  (chunkovaný, obsahově adresovaný, takže duplicitní chunky se neposílají).
- Registrace zařízení: `lib/features/sync/data/device_registration_service.dart`.

## Rozsah (k potvrzení v návrhu)

1. Balíčky: `photo_manager` (výčet assetů, změny galerie) a `workmanager`
   (Android periodický task, iOS `BGAppRefreshTask` / `BGProcessingTask`).
   Ověř licence a údržbu.
2. Stav zálohy v lokální DB (sqflite/Hive): které assety jsou nahrané
   (asset id + hash), kvůli deduplikaci a obnovitelnosti po přeinstalaci
   (hash lze porovnat se serverem).
3. Nastavení: zapnout/vypnout, jen Wi-Fi (výchozí ano), jen při nabíjení
   (výchozí ne), zahrnout videa (výchozí ne), výběr alb (volitelně).
4. Popředí: fronta s progresem v UI. Pozadí: dávky v rámci limitu OS, bez
   pádů při přerušení. Upload musí být obnovitelný (chunky).
5. Oprávnění: limited access na iOS 14+ a Android 13+/14+ (READ_MEDIA_*,
   partial access). Srozumitelné vysvětlení při odmítnutí.
6. Live Photos / HEIC / edited assets: nahraj originál. Live Photo video
   část v této verzi nenahrávej a uveď to v PR.

## Akceptační kritéria

- [ ] Unit testy: výběr assetů k nahrání (dedup, filtry Wi-Fi/video),
      perzistence stavu, obnovení po přerušení.
- [ ] Ručně ověřeno na Androidu i iOS: nová fotka se nahraje na popředí i
      po uspání aplikace (v rámci limitů OS). Popis v PR.
- [ ] Vypnutí zálohy zastaví práci na pozadí.
- [ ] Release buildy Android i iOS projdou (`release-clients.yml`).

## Výstup

PR (případně více menších: stav + popředí → pozadí → nastavení).
