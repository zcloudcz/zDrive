# zDrive — analýza (FABLE)

## Co to je
Cloud storage platforma (alternativa OneDrive + Google Photos): .NET 8 mikroservisy (ApiGateway/YARP, Auth, File, Storage, Sync, Photo, Notification) s Clean Architecture, PostgreSQL (schéma per service), Azure Blob (lokálně Azurite), Flutter klient pro všechny platformy. Detailní design a multi-agent plán v `CLAUDE.md` a `docs/superpowers/specs/2026-06-04-zdrive-platform-design.md`.

## Stav (aktualizováno 11. 6. 2026)
- **Hotové fáze:** 0 (foundation + Auth), 1 (file storage), části 2+4 (sync, notification, photo services + Flutter timeline/alba/sync status). Fáze 3 (versioning), 5–8 nezačaty.
- **Stabilizační větev `fix/stabilization` zmergována do `master` (81ad7ab).** Všechny nálezy z analýzy 4. 6. vyřešeny + objevené navíc:
  - RSA klíče pryč z repa (commitnutý klíč byl navíc poškozený — auth s ním nikdy nemohl fungovat); `DevJwtKeyProvider` generuje per-machine pár do `~/.zdrive/dev-keys/`, atomický zápis, fail-fast mimo Development. Gitleaks scan v CI.
  - `MapInboundClaims=false` všude — default mapping přejmenovával `sub` a rozbíjel každý autorizovaný endpoint.
  - DB hesla sjednocena (`zdrive_dev`), init-db.sql má všech 6 schémat, StorageService `Search Path=storage`, PhotoService `Database`→`PhotoDb` (DI četl `PhotoDb` → connection string byl null).
  - launchSettings.json pro všech 7 hostů (porty dle YARP; bez nich `dotnet run` běžel jako Production).
  - `EnsureCreatedAsync` při startu v Development (migrace v repu nejsou).
  - FileService `UseSnakeCaseNamingConvention` — raw SQL a index filtry používají snake_case, model mapoval PascalCase.
  - SyncService měl jiný public key než Auth (nikdy nemohl validovat tokeny); integrační testy podepisovaly poškozenými hardcoded klíči / závodily na process-wide env var — vše přes per-factory RSA + `PostConfigure<JwtBearerOptions>`.
  - Flutter testy pro photos bloc + sync data source (18 nových).
- **Ověřeno:** build čistý, 183 .NET testů zelených (unit + integrace přes Testcontainers), Flutter 58/58, `docker-compose up` + AuthService smoke test (health/register/login) proti čerstvé DB.

## Odložený tech-dluh (z hydra review)
- Dev klíče bez owner-only file permissions (low, dev-only).
- `EnsureCreated` vs. budoucí EF migrace — při zavedení migrací bude potřeba dev DB zahodit nebo ošetřit přechod (vědomý kompromis, komentář v Program.cs).

## Fáze 3 (Versioning) — hotovo (11. 6. 2026, větev feature/phase3-versioning)
- **StorageService:** chunky content-addressed (SHA-256) — re-upload už nepřepisuje data starších verzí (původní `chunk-{index}` pojmenování je destruktivně přepisovalo); manifest snapshoty `manifests/{hash}.json`; `POST /storage/files/{id}/manifests/{hash}/restore`.
- **FileService:** `POST /files/{id}/versions` (zápis verze po uploadu), `POST /files/{id}/versions/{vid}/restore` (restore-as-new-version), retention `Versioning:MaxVersionsPerFile` (default 10, prune při insertu), ownership checks.
- **Flutter:** version history dialog (list/restore/komentáře), `FileRepository.getVersions/restoreVersion` — klient orchestruje FileService→StorageService.
- Pozn.: nepoužíváme Azure Blob Versioning (Azurite ho nepodporuje) — vlastní content-addressed snapshoty, viz CLAUDE.md.

## Odloženo z fáze 3
- Text diff viewer, quota impact calculation.
- GC osiřelých chunků/manifest snapshotů po retention prune.
- **Vědomé kompromisy (hydra review 11. 6.):** (a) dvoufázová orchestrace restore (FileService → StorageService) nemá kompenzaci — když blob flip selže, metadata a blob divergují do dalšího restore/uploadu; (b) `POST /files/{id}/versions` nevaliduje `blobVersionId` proti StorageService (klient může zapsat verzi na neexistující snapshot — restore pak vrátí 404); (c) souběžné zápisy verzí téhož souboru řeší unique index `(FileId, VersionNumber)` — druhý request spadne na constraint, žádný retry. Vše řešitelné až se zavede service-to-service komunikace (event bus).
- Codex review nedostupný (ChatGPT účet nepodporuje Codex API modely) — review provedla hydra vlastním čtením; až bude Codex funkční, zvážit zpětný audit fáze 3.
- Flutter upload/files data source míjí reálný backend kontrakt (bez ApiResponse envelope, jiné cesty — `/files/uploads` vs. `/storage/upload`, PATCH vs. PUT) — klient z fáze 1 psaný proti předpokládanému API; nový versions kód už cílí na skutečný kontrakt. Zaslouží vlastní alignment task.

## Návrhy — další krok
- **Alignment Flutter klienta na reálné API** (viz výše) — bez něj upload z klienta nefunguje proti skutečnému backendu.
- Pak fáze 2 dokončení (sync engine) nebo fáze 5 (Photos AI) dle priority.
- Při zavádění dalších fází zvážit EF migrace místo `EnsureCreated`.
