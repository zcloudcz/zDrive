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

## Client API alignment — hotovo (15. 6. 2026, větev feature/client-api-alignment)
- **Envelope:** helper `unwrapMap/unwrapMapList/ensureSuccess` + `ApiException` (`core/network/api_envelope.dart`). Backend balí vše do `{success,data,error}`; klient (auth/files/upload/sync) četl `response.data` přímo → vše rozbité. Helper se volá na call-site (robustnější než global interceptor proti stávajícím auth-refresh/retry interceptorům, které re-issue requesty přes bare Dio). Auth-refresh interceptor rozbaluje envelope ručně. **PhotoService envelope NEpoužívá** (`Ok(result)` přímo) — photo DS ponechán beze změny.
- **Cesty/metody:** port `5000→5100` (gateway). rename `PUT /files/{id}/rename`, move `PUT /files/{id}/move`, createFolder `POST /files {isFolder:true}`, root listing `GET /files/root/children` (nová backend routa — `{id:guid}/children` neumí null parent). Shares `/api/v1/shares` + **nová gateway routa** (předtím gateway shares vůbec neroutoval).
- **Upload přepsán** — klient orchestruje: `POST /files` (node) → `POST /storage/upload/init {fileId}` → `PUT /storage/upload/{s}/chunk/{i}` (raw body, `X-Chunk-Hash`=SHA-256) → `complete` → `POST /files/{id}/versions`. DTOs opraveny (`UploadSessionDto{sessionId,sasUploadUrl}`, `UploadCompleteDto{blobPath,manifestHash,totalSize}`, nový `DownloadUrlDto`). Download `GET /storage/download/{id}`. Přidána závislost `crypto`.
- **Auth:** `AuthTokenDto` nevrací user → `AuthResponseDto` jen tokeny, login/register po uložení tokenů volá `getCurrentUser()` (`GET /users/me`).
- **FileService** `JsonStringEnumConverter` (Permission lze poslat jménem; čte i číslo, takže stávající testy drží).
- **Ověřeno:** flutter analyze čistý, Flutter 63/63 (29 nových data-source/envelope testů), .NET 191/191.

### Odloženo (samostatný photos task)
- PhotoService routuje gateway jen `/photos`; `/api/v1/albums` a `/api/v1/memories` controllery **gateway neroutuje** → alba/memories z klienta nedostupné. Navíc photo DS čte `response.data['items']` u album-photos, ale controller vrací holý list (paging kontrakt nesedí). Photos feature potřebuje vlastní alignment (gateway routy + paging).

## Návrhy — další krok
- **Photos alignment** (gateway albums/memories routy + paging kontrakt) — viz výše.
- Pak fáze 2 dokončení (sync engine) nebo fáze 5 (Photos AI) dle priority.
- Při zavádění dalších fází zvážit EF migrace místo `EnsureCreated`.
