# Zadání 09: Fotky backend (modul v Api, ingest z change feedu, EXIF, miniatury)

> Pracuješ v repozitáři zDrive (.NET 8). Nejdřív si přečti `CLAUDE.md`,
> `docs/adr/0001-server-side-file-change-log.md` a
> `docs/plans/2026-09-22-merge-backend-services.md` (jak se slučovaly
> služby do `ZDrive.Api`). Dodržuj Clean Architecture per služba, MediatR,
> testy `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers (Postgres, Azurite), migrace
> přes `--startup-project src/services/Api`, komunikace česky, kód
> anglicky.
>
> **Než začneš psát kód, pošli krátký návrh (≤ 1 strana) bodů 2 a 3 a
> počkej na schválení.** Jde o nové cross-module závislosti.

## Cíl

Nahraná fotka se sama objeví v timeline se správným datem pořízení a s
miniaturami. Hlavní slib produktu je „Google Photos-level", dnes v něm
chybí všechno kromě DB modelu.

## Současný stav

- `src/services/PhotoService/*` (samostatný host, **nenasazený**):
  - `IngestPhotoCommandHandler.cs` jen vloží řádek `Photo` se stavem
    `Ingested`. `TakenAt` odhaduje regexem z názvu souboru. Pole
    lat/lng, fotoaparát a kvalita (`Domain/Entities/Photo.cs:11-19`) nikdo
    neplní.
  - Nemá blob, EXIF, miniatury ani worker. Memories se jen čtou.
  - Závislosti: jen `ConnectionStrings:PhotoDb` (schéma `photos`,
    `MigrateWithBaselineAsync("photos")`) a JWT klíč.
  - Ingest volají jen testy (`POST /api/v1/photos/ingest`).
- `ZDrive.Api` hostuje Auth, File, Storage a Sync. PhotoService v něm není
  (`Api.csproj`). Gateway posílá `/photos`, `/albums`, `/memories` na
  `photoCluster` = `localhost:5105` (`ApiGateway/appsettings.json:132-198`),
  nasazené tedy vrací 502. Produkce = dvě App Service nasazované ručně ZIPem.
- `storage/thumbnail/{photoId}` (`StorageController.cs:144-154`,
  `GetThumbnailUrlQueryHandler.cs`) vrací URL na neexistující
  `https://cdn.zdrive.io`.
- Change log: `FileChange` (`FileService.Domain/Entities/FileChange.cs`)
  se píše v téže transakci jako změna (`FileChangeInterceptor`). Feed
  `GET /files/changes` je **per user** (`FilesController.cs:245`), s SHARE
  lockem a 5s hold-backem (viz ADR 0001, `docs/mvp-completion.md`).

## Rozsah

1. **PhotoService jako modul `ZDrive.Api`** stejným postupem jako ostatní
   čtyři služby: controllery do `src/services/Api/Controllers/Photos/`,
   registrace DI a migrace `photos` ve startupu Api. Gateway route na
   `apiCluster`. Samostatný `ZDrive.PhotoService.Api` host a jeho testy
   zachovej nebo odstraň stejně, jak se to udělalo u ostatních služeb
   (podle plánu výše).
2. **Ingest worker** (`BackgroundService` v Api): čte `file_changes` přes
   **globální** kurzor napříč uživateli. Kurzor je uložený ve schématu
   `photos` a respektuje stejný hold-back a lock jako feed (ADR 0001),
   aby nepřeskočil pozdní commity. Pro vytvořený soubor nebo novou
   verzi typu obrázek (MIME, jinak přípona jpg, jpeg, png, heic, heif,
   webp) zařadí zpracování. Pro smazání nebo přesun do koše fotku skryje,
   pro obnovu ji vrátí. Idempotence: klíč je `(FileId, manifestHash)`.
   V návrhu vysvětli, jak worker čte data FileService a StorageService,
   aniž by porušil hranice modulů. Preferuj existující Application
   query přes MediatR před přímým přístupem k cizímu DbContextu.
3. **Zpracování:** stáhne obsah (manifest + chunky přes Storage application
   vrstvu, s ověřením hashe), přečte EXIF přes **MetadataExtractor**
   (Apache-2.0): datum pořízení, GPS, fotoaparát, orientace. Vygeneruje
   miniatury 256/1024 px WebP přes **SkiaSharp** (MIT) se správnou
   orientací. **Nepoužívej ImageSharp** (Split License). Miniatury
   ukládej do blobu `{tenantId}/{userId}/thumbnails/{photoId}/{size}.webp`.
   Stav `Photo` postupně: `Ingested` → `Processed` / `Failed` (s důvodem
   a počtem pokusů, max 3). HEIC: zjisti, jestli ho SkiaSharp na Linuxu
   (App Service) dekóduje. Pokud ne, ulož metadata bez miniatury a uveď to
   v PR.
4. **Thumbnail endpoint:** nahradit CDN URL skutečným
   `GET /api/v1/photos/{id}/thumbnail/{size}`, autorizovaně, se streamem
   `image/webp` a `Cache-Control: private, max-age=...` + ETag.
5. **Backfill:** worker začíná kurzorem 0, takže projde i existující
   fotky. Ověř, že to je bezpečné pro výkon (dávky, limit souběhu).
6. **Kvóta:** miniatury se do kvóty uživatele nepočítají.

## Mimo rozsah

AI (tagy, tváře, OCR), memories generátor, alba (už existují), Service
Bus, CDN, klient (zadání 10), nasazení do produkce. Nasazení udělá člověk
podle runbooku, ale v PR popiš, co se mění (žádná nová App Service, nová
gateway route, případné nové app settings).

## Akceptační kritéria

- [ ] Integrační test (Postgres + Azurite): upload JPEG s EXIF přes File +
      Storage API → worker → `GET /photos/timeline` vrátí fotku s EXIF datem
      a GPS → thumbnail endpoint vrátí WebP správných rozměrů.
- [ ] Soubor v koši zmizí z timeline, po obnovení se vrátí.
- [ ] Nová verze souboru přegeneruje miniatury.
- [ ] Pozdní commit (test podle vzoru z ADR 0001) worker nepřeskočí.
- [ ] Poškozený obrázek → `Failed`, worker pokračuje dál.
- [ ] Všechny existující testy zelené. Gateway routing testy upravené.

## Výstup

Jeden PR (případně dva: 1 = sloučení do Api, 2 = worker + zpracování).
