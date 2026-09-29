# zDrive

Cloud storage platform (OneDrive alternative) with Google Photos-level photo
management. Azure Blob Storage backend, Flutter clients on all platforms.

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | .NET 8+ microservices (C#) |
| Clients | Flutter (Web, Android, iOS, Windows, macOS) |
| Database | PostgreSQL (metadata) |
| Object storage | Azure Blob Storage (versioning enabled) |
| Message bus | Azure Service Bus |
| Real-time | Azure SignalR Service |
| AI | Azure AI Vision + Face API |
| Cache | Redis |
| Orchestration | AKS (Kubernetes) |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus + Grafana + Seq |

## Architecture

Microservices behind an API Gateway (YARP):

| Service | Responsibility |
|---------|---------------|
| `api-gateway` | Routing, rate limiting, JWT validation, request aggregation |
| `auth-service` | Registration, login, custom JWT + refresh tokens, user/role mgmt |
| `file-service` | File/folder CRUD, metadata, sharing, permissions, trash |
| `storage-service` | Azure Blob abstraction, chunked upload/download, versioning, dedup |
| `sync-service` | Delta sync engine, change tracking, conflict resolution, device registry |
| `photo-service` | Photo processing pipeline, AI tagging, face clustering, albums, memories |
| `notification-service` | Real-time events (SignalR), push (FCM/APNs), email |

`auth-service`, `file-service`, `storage-service`, `sync-service` and
`photo-service` run in one process, `src/services/Api` (`ZDrive.Api`), to cut
App Service count on the shared hosting plan — each still owns its
Domain/Application/Infrastructure layers and its own PostgreSQL schema, only
the API host is merged. `notification-service` remains separate (and
undeployed). The Api host needs `ConnectionStrings:PhotoDb` (schema `photos`)
in addition to the Auth/File/Storage/Sync ones.

Inter-service communication: Azure Service Bus (async events), gRPC (sync calls).

## Repository structure

```
zDrive/
├── src/
│   ├── services/
│   │   ├── ApiGateway/
│   │   ├── Api/                    # merged host: Auth + File + Storage + Sync + Photo
│   │   ├── AuthService/            # Domain/Application/Infrastructure only
│   │   ├── FileService/            # Domain/Application/Infrastructure only
│   │   ├── StorageService/         # Domain/Application/Infrastructure only
│   │   ├── SyncService/            # Domain/Application/Infrastructure only
│   │   ├── PhotoService/           # Domain/Application/Infrastructure only
│   │   └── NotificationService/
│   ├── shared/                    # shared .NET libs (DTOs, contracts, utils)
│   └── client/                    # Flutter app
│       └── zdrive_app/
├── infra/                         # Terraform / Bicep, Helm charts
├── docker-compose.yml             # local dev
├── docs/
│   └── superpowers/specs/         # design documents
└── CLAUDE.md
```

## Build & run

### Backend (each service)

```bash
dotnet build src/services/{ServiceName}
dotnet test src/services/{ServiceName}.Tests
dotnet run --project src/services/{ServiceName}
```

Auth/File/Storage/Sync/Photo run as one host, `src/services/Api`
(`dotnet run --project src/services/Api`), but each still owns its
Infrastructure project's EF migrations. `src/services/Api` is now the only
startup project for `dotnet ef`, for every one of those five contexts:

```bash
dotnet ef migrations add <Name> \
  --project src/services/FileService/ZDrive.FileService.Infrastructure \
  --startup-project src/services/Api
```

### Full backend (Docker Compose)

```bash
docker-compose up -d
```

### Flutter client

```bash
cd src/client/zdrive_app
flutter pub get
flutter run -d chrome          # web
flutter run -d windows          # desktop
flutter run                     # connected mobile device
flutter test
flutter build web
flutter build apk
flutter build ipa
```

#### Build-time defines

All are `const` in the client (`String.fromEnvironment` /
`bool.fromEnvironment`), so they are baked in at compile time and cannot be
changed at runtime. Their defaults describe the **deployed** setup, not the
docker-compose one:

| Define | Default | Pass it when |
|--------|---------|--------------|
| `API_BASE_URL` | `http://localhost:5100/api/v1` | Building for a deployed gateway — CI does this for the Pages build (`.github/workflows/deploy-web.yml`) |
| `PHOTOS_ENABLED` | `false` | Running the photo backend locally or against a gateway whose Api host has the photo module deployed. PhotoService is part of the merged Api host, so once that build is deployed the photo routes are served by it (no separate photo service). NotificationService is still **not deployed** (MVP scope) and answers 502 through the gateway; the Photos tab and its route are hidden by default until the backend is rolled out |
| `ENTRA_CLIENT_ID` | `` (empty) | Enabling Entra sign-in via Drive's own Entra app registration — web (ADR `docs/adr/0002-shared-zcloud-login-entra-sso.md`) and, on the same registration, iOS/Android/Windows (ADR `docs/adr/0003-native-entra-sign-in.md`; macOS/Linux stay password-only). Empty is the safety gate: with no client id the "Sign in with your ZCLOUD account" button on the login page does not render at all, on any platform. No production registration exists yet — see ADR 0002's Migration order step 1 for what a human needs to create in the Entra admin portal first |
| `ENTRA_API_SCOPE` | `` (empty) | Same feature, same safety gate as `ENTRA_CLIENT_ID` — the sign-in button needs BOTH set to show, since a client id with no scope would still redirect through the whole Entra flow only to fail far from the cause. The scope requested alongside `openid`, e.g. `api://<drive-api-app-id>/access_as_user`; depends on how Drive's API app registration exposes its scope |

`docker-compose up` only starts infrastructure; the photo backend runs inside
the Api host (`dotnet run --project src/services/Api`), so local work on photos
needs the Api running and the flag, or the tab will not be there:

```bash
flutter run -d windows --dart-define=PHOTOS_ENABLED=true
```

## Conventions

### .NET services

- Clean Architecture per service: Domain → Application → Infrastructure → API.
- Each service has its own PostgreSQL schema (logical separation, shared server).
- EF Core for data access. Migrations per service.
- MediatR for CQRS (commands/queries separated).
- FluentValidation for input validation.
- Serilog for structured logging. Every log includes `CorrelationId`.
- Health checks on `/health/live` and `/health/ready`.
- API versioning via URL path (`/api/v1/...`).

### Flutter client

- Feature-first structure: `features/{name}/data|domain|presentation`.
- State management: Bloc/Cubit.
- Dependency injection: get_it + injectable.
- Local storage: SQLite (metadata mirror), Hive (KV store).
- HTTP: Dio with interceptors (auth, retry, logging).
- Platform-specific code isolated in `platform/{os}/`.

### General

- Code and comments in English.
- Communication in Czech.
- No speculative features. Build what's specified.
- Every service has unit + integration tests.
- PR must pass CI before merge.

## Key design decisions

### Delta sync (block-level)

Files are split into ~4MB chunks using rolling hash. Only changed chunks are
uploaded. Server maintains a chunk manifest per file. Conflict resolution:
last-write-wins auto + fork-and-prompt for manual cases.

### Blob versioning

Implemented with content-addressed snapshots instead of Azure Blob Versioning
(Azurite does not support the versioning API, and the chunk+manifest model
gives us versioning for free):

- Chunks are stored under their SHA-256 content hash
  (`{base}/chunks/{hash}.blk`) — a re-upload never overwrites data an older
  version still references, and identical chunks dedupe automatically.
- Every completed upload writes the manifest twice: `manifest.json` (latest)
  and an immutable snapshot `manifests/{manifestHash}.json`. The manifest
  hash is the version identifier (`FileVersion.BlobVersionId`).
- Version metadata (number, size, author, comment) lives in PostgreSQL
  `file_versions` (FileService). Restore = FileService
  `POST /files/{id}/versions/{versionId}/restore` (metadata, records the
  restore as a NEW version) followed by StorageService
  `POST /storage/files/{id}/manifests/{hash}/restore` (blob flip). The client
  orchestrates both calls — there is no service-to-service messaging yet.
- Retention: `Versioning:MaxVersionsPerFile` (FileService appsettings,
  default 10) prunes the oldest metadata rows on insert. Orphaned blob
  snapshots/chunks are garbage, not data loss; GC is future work.

### File change log (server-side sync events)

FileService writes an append-only `file_changes` row for every `FileNode`
mutation, in the same transaction as the mutation (a `SaveChangesInterceptor`,
not a second write), and serves it as a cursor-paged feed
(`GET /api/v1/files/changes`). This will replace client-pushed sync events
once clients actually read the feed (the client-side PR that wires desktop,
web, mobile and `ZDrive.BackupCli` onto it) — until then, SyncService's push
path is still what clients use. See
`docs/adr/0001-server-side-file-change-log.md` for the full reasoning,
alternatives rejected, and the known 5-second commit-order hold-back.

### Photo processing pipeline

**Ingest is implemented in-process, without a broker.** `PhotoIngestWorker`
(a `BackgroundService` in `ZDrive.Api`) has two independent loops. *Reconcile*
reads FileService's *global* change log through the MediatR query
`GetFileChangeBatchQuery` (same SHARE-lock + 5 s hold-back semantics as the
per-user feed, one shared implementation: `FileChangeFeedReader`) and keeps a
durable cursor in `photos.ingest_cursors`; it runs every
`Photos:Ingest:PollIntervalSeconds`, or again at once while it reports more
work, never per processed photo (the read takes a table-level lock).
*Processing* runs `MaxConcurrentProcessing` workers that each claim one photo
at a time.

The change log starts empty (ADR 0001), so files uploaded before it existed
never appear in it. On a fresh cursor the worker therefore **bootstraps**
first: it captures the safe feed head, scans all live file nodes
(`GetFileNodeBatchQuery`, keyset-paged by id, resumable through
`BootstrapLastNodeId`), applies them exactly like feed changes, then moves the
cursor to the captured head and follows the feed. Everything is state-based:
for each file it looks at the file's *current* state and creates/queues
(image, new `ManifestHash`), hides (trashed, renamed to a non-image; both
restorable), un-hides, or deletes the `Photo` row and its thumbnails (node no
longer exists; note `EmptyTrash` writes no change row, so full garbage
collection of purged files and superseded thumbnail versions is future work).
The `photos` table doubles as the work queue (lease + `FOR UPDATE SKIP
LOCKED`); a photo needs work while `SourceManifestHash != ProcessedManifestHash`,
and one that already has a processed version stays `Processed` and visible
(current thumbnails included) while a newer version is queued or failing.
Processing reads the original through Storage's manifest/chunk queries (chunk
hashes verified), extracts EXIF with MetadataExtractor and writes 256/1024
WebP thumbnails with SkiaSharp to
`{tenant}/{user}/thumbnails/{photoId}/{manifestHash[..16]}/{size}.webp` (the
version in the key means a slow worker for an old version can never overwrite
a newer one; not counted against the quota, which sums `file_versions`).
Originals declaring more than `MaxDecodedPixels` are rejected before any
decode buffer exists. HEIC/HEIF/AVIF cannot be decoded by Skia on Linux: those
photos get metadata but no thumbnails (`ThumbnailsReady = false`).
Undecodable data fails at once (`Failed`); transient errors retry with
backoff, max 3 attempts. Settings: `Photos:Ingest:*` (`Enabled`,
`PollIntervalSeconds`, `BatchSize`, `MaxConcurrentProcessing`,
`MaxSourceBytes`, `LeaseMinutes`, `MaxAttempts`, `MaxDecodedPixels`) and
`Photos:Thumbnails:CacheMaxAgeSeconds`. Thumbnails are served by
`GET /api/v1/photos/{id}/thumbnail/{256|1024}` (private cache + ETag); the
gateway gives that one route its own `thumbnail` rate-limit budget.

The Service Bus design below is the target for the AI stages, not what runs today:
1. **Ingest** — EXIF extraction, thumbnail generation (256/1024/2048 WebP)
2. **AI Analysis** — Azure AI Vision (tags), Face API (detection + embeddings), OCR
3. **Clustering** — face→person assignment (cosine similarity), geo+time trip detection
4. **Memory generation** — daily cron: "this day", trips, monthly collages

Photo editor is client-side only. Non-destructive (JSON edit operations, original untouched).

### Auth

Custom JWT implementation. Access token (short-lived, 15min) + refresh token
(long-lived, 30 days, rotated on use). Roles: owner, admin, member, viewer.
Tenant-scoped for B2B.

### Multi-tenant isolation

- Blob storage: `{tenantId}/{userId}/` path prefix.
- PostgreSQL: `tenant_id` column on all tenant-scoped tables. Row-level filtering via EF Core global query filters.
- Personal users get an implicit single-user tenant.

## Environment

| Variable | Purpose |
|----------|---------|
| `AZURE_STORAGE_CONNECTION_STRING` | Blob Storage connection |
| `DATABASE_CONNECTION_STRING` | PostgreSQL connection |
| `SERVICE_BUS_CONNECTION_STRING` | Azure Service Bus |
| `SIGNALR_CONNECTION_STRING` | Azure SignalR |
| `AZURE_AI_ENDPOINT` | AI Vision + Face endpoint |
| `AZURE_AI_KEY` | AI Services key |
| `JWT_SECRET` | Token signing key |
| `JWT_ISSUER` | Token issuer |
| `REDIS_CONNECTION_STRING` | Redis cache |

Never commit secrets. Use Azure Key Vault in deployed environments,
`dotnet user-secrets` or `.env` locally (`.env` is in `.gitignore`).
CI runs a gitleaks scan (`.github/workflows/secret-scan.yml`) over the
working tree on every push.

### JWT dev keys

JWT signing keys are never stored in the repository. Locally, the first
service that starts generates an RSA key pair into `~/.zdrive/dev-keys/`
(override with `ZDRIVE_DEV_KEY_DIR`) via `DevJwtKeyProvider` in
`ZDrive.Shared`. All services read the same files, so tokens issued by
AuthService validate everywhere. Outside Development a missing
`Jwt:RsaPrivateKeyPem` / `Jwt:RsaPublicKeyPem` is a hard startup failure.

### Recovering a database from before EF migrations existed

Every service migrates its own schema on startup via `MigrateWithBaselineAsync`
(`ZDrive.Shared/Persistence/DatabaseMigrationExtensions.cs`). If a schema has
tables but no `__EFMigrationsHistory` table, it refuses to guess whether
that's an install from the old `EnsureCreated`-based workaround, a
partially-created schema, or something unrelated, and aborts the service
with an `InvalidOperationException` instead of silently marking migrations
as applied against a schema that might not actually match them — an earlier
version tried to baseline automatically from matching table names and could
mark a migration as applied when the schema was actually missing one of its
columns, which is unrecoverable (EF never revisits a migration it believes
already ran).

If a service fails to start with that error:

- **Throwaway dev database** (docker-compose): drop the Postgres volume and
  restart — `MigrateAsync()` recreates the schema from scratch. Compose
  prefixes volume names with the project, so it is `zdrive_postgres-data`,
  not `postgres-data`:

  ```bash
  docker compose down && docker volume rm zdrive_postgres-data
  ```

  `docker compose down -v` also works but removes **every** volume in the
  file, `azurite-data` included — that is every uploaded blob.

- **Real database**: reconcile the schema against the current EF model by
  hand (`dotnet ef migrations script` for that service shows what the model
  expects), then record the migration as applied. Both statements are
  required, in one transaction — creating the table without inserting the
  row leaves the guard passing and the next start replaying the DDL:

  ```sql
  BEGIN;
  CREATE TABLE IF NOT EXISTS "<schema>"."__EFMigrationsHistory" (
      "MigrationId"    character varying(150) NOT NULL,
      "ProductVersion" character varying(32)  NOT NULL,
      CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId")
  );
  INSERT INTO "<schema>"."__EFMigrationsHistory" ("MigrationId", "ProductVersion")
  VALUES ('<migration id>', '8.0.11');
  COMMIT;
  ```

  `ProductVersion` is `NOT NULL` with no default, so inserting only the id
  fails with `23502`. `<migration id>` is the **timestamped** name, not
  `InitialCreate` — it differs per service, and is the file name under that
  service's `Migrations/` folder (e.g. `20260908185942_InitialCreate` for
  AuthService). Take `ProductVersion` from the
  `Microsoft.EntityFrameworkCore.Design` version in that service's
  `.csproj`.

  Nothing in the codebase automates this, and it is per migration: if more
  than `InitialCreate` is already reflected in the schema, insert a row for
  each.

### Local substitutes for Azure services

The production design targets Azure managed services; local development
(docker-compose) runs open-source equivalents:

| Production (design) | Local (docker-compose) | Notes |
|---------------------|------------------------|-------|
| Azure Service Bus | RabbitMQ (`localhost:5672`, mgmt UI `:15672`) | Same async-event role; abstraction layer hides the transport |
| Azure SignalR Service | Self-hosted SignalR in NotificationService | Same hub code; Azure SignalR is a scale-out proxy only |
| Azure Blob Storage | Azurite emulator (`localhost:10000`) | `UseDevelopmentStorage=true` connection string |
| Azure AI Vision / Face | not emulated | Photo AI features (Phase 5) need a real Azure endpoint |
| Application Insights / managed monitoring | Seq (`localhost:5341`, UI `:8081`) | Serilog sink |

## Coding rules

These rules prefer caution over speed. Use common sense for trivial tasks.

### 1. Think first, code second

Don't assume. Don't hide confusion. Name tradeoffs.

Before implementing:
- State assumptions out loud. If unsure, ask.
- If multiple interpretations exist, show them — don't pick silently.
- If a simpler path exists, say so. Push back when it makes sense.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first

Minimum code that solves the given problem. Nothing speculative.

- No features beyond what was requested.
- No abstractions for code used only once.
- No "flexibility" or "configurability" nobody asked for.
- No error handling for scenarios that can't happen.
- If you wrote 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is over-engineered?" If yes, simplify.

### 3. Minimal, surgical changes

Touch only what you must. Clean up only after yourself.

When modifying existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Follow existing style, even if you'd do it differently.
- If you spot unrelated dead code, mention it — don't delete it.

When your changes create orphaned code:
- Delete imports / variables / functions YOUR changes made unused.
- Don't delete dead code that was there before unless asked.

Test: every changed line should trace directly to the user's request.

### 4. Goal-driven execution

Define success criteria. Verify in a loop until they hold.

Turn tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them green."
- "Fix the bug" → "Write a test reproducing the bug, then make it green."
- "Refactor X" → "Verify tests pass before AND after."

For multi-step tasks, write a short plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you work autonomously in a loop.
Weak criteria ("make it work") require constant back-and-forth.

## Implementation phases

| Phase | Scope | Est. |
|-------|-------|------|
| 0 | Foundation: repo, CI/CD, Docker Compose, Auth Service, Flutter shell | 2-3w |
| 1 | File Storage: blob upload/download, file browser, sharing | 4-5w |
| 2 | Sync Engine: delta sync, desktop agents, real-time push, offline | 4-6w |
| 3 | Versioning: blob versions, history UI, retention | 2-3w |
| 4 | Photos Basic: ingest pipeline, timeline, albums, mobile backup | 3-4w |
| 5 | Photos AI: auto-tagging, faces, search, memories | 4-5w |
| 6 | Photos Social: shared albums, editor, collages | 3-4w |
| 7 | B2B: tenant admin, roles, audit log, quotas | 3-4w |
| 8 | Production: perf, security audit, GDPR, store submissions | 3-4w |

## Parallelization plan (multi-agent)

Microservices architecture enables heavy parallelization. Below is the
agent assignment per phase. Agents work in isolated git worktrees and merge
via PR.

### Phase 0 — Foundation (3 agents)

```
Agent A: .NET solution          Agent B: Flutter shell           Agent C: Infrastructure
─────────────────────────       ─────────────────────────        ─────────────────────────
• Solution + project scaffold   • Flutter project init           • Docker Compose (PG, Redis,
• Shared library (DTOs,         • go_router setup                  Service Bus emulator)
  contracts, middleware)        • Auth UI (login, register)      • CI/CD pipeline (GitHub
• Auth Service (full)           • Dio client + JWT interceptor     Actions for .NET + Flutter)
• API Gateway (YARP config)     • Theme + localization setup     • Terraform/Bicep skeleton
                                                                 • .gitignore, .editorconfig
```
**Sync point:** All merge → verify Docker Compose boots all services + Flutter connects.

### Phase 1 — File Storage (3 agents)

```
Agent A: Storage Service        Agent B: File Service            Agent C: Flutter file UI
─────────────────────────       ─────────────────────────        ─────────────────────────
• Blob upload (simple +         • File/folder CRUD               • File browser (grid/list)
  chunked)                      • Folder tree + metadata         • Breadcrumb navigation
• Blob download (stream +       • Soft delete + trash            • Upload flow + progress
  range)                        • Sharing (link + direct)        • Download + open/save
• SAS token generation          • Search (tsvector)              • Trash view + restore
• CDN integration               • Permission enforcement         • Share dialog
```
**Sync point:** Merge → E2E test: upload file via Flutter → verify in blob storage → download.

### Phase 2 — Sync Engine (3 agents, partially parallel with Phase 3)

```
Agent A: Sync Service           Agent B: Flutter sync            Agent C: Notification Service
─────────────────────────       ─────────────────────────        ─────────────────────────
• Sync protocol (pull/push)     • Rabin chunking in Dart         • SignalR hub setup
• Device registry               • File watcher (platform         • Real-time file change
• Change tracking + cursors       channels → native)               events
• Conflict detection            • Offline queue (Hive)           • Push notification
• Server-side merge logic       • Conflict resolution UI           integration (FCM/APNs)
                                • Background sync per OS         • Email transactional
```

### Phase 3 — Versioning (2 agents, START DURING Phase 2)

```
Agent A: Backend versioning     Agent B: Flutter version UI
─────────────────────────       ─────────────────────────
• Azure Blob Versioning         • Version history list
  integration                   • Version preview + restore
• file_versions table +         • Text diff viewer
  API endpoints                 • Version comment input
• Retention policy engine
• Quota impact calculation
```

### Phase 4-6 — Photos (4 agents, START Phase 4 DURING Phase 2)

Photo track is **independent from sync track** after Phase 1.

```
Phase 4:
Agent A: Ingest Worker          Agent B: Flutter photo UI
─────────────────────────       ─────────────────────────
• EXIF extraction               • Timeline view (grid)
• Thumbnail gen (WebP)          • Full-screen viewer + swipe
• Photo DB schema + API         • Manual albums
• CDN thumbnail serving         • Mobile auto-backup
                                  (Android + iOS)

Phase 5 (after Phase 4 merges):
Agent A: AI Workers             Agent B: Search + Memories       Agent C: Flutter AI UI
─────────────────────────       ─────────────────────────        ─────────────────────────
• AI Vision integration         • Search query parser            • Search page
• Face API + embeddings         • Tag + date + geo matching      • People gallery
• Face clustering (pgvector)    • Memory generator (cron)        • Memory viewer cards
• OCR worker                    • Trip detection (DBSCAN)        • Push notification UI

Phase 6 (after Phase 5 merges):
Agent A: Shared albums backend  Agent B: Flutter social + editor
─────────────────────────       ─────────────────────────
• Album sharing API             • Shared album UI + invites
• Activity feed                 • Photo editor (crop, filters)
• Comments + reactions API      • Collage templates + renderer
```

### Phase 7 — B2B (2 agents, parallel with Phase 6)

```
Agent A: Backend B2B            Agent B: Flutter admin UI
─────────────────────────       ─────────────────────────
• Tenant management API         • Admin dashboard
• Role + permission engine      • Member management UI
• Audit log                     • Quota visualization
• Bulk provisioning (CSV)       • Branding settings
• Sharing policy enforcement    • Audit log viewer
```

### Phase 8 — Production (3 agents)

```
Agent A: Performance            Agent B: Security               Agent C: Release
─────────────────────────       ─────────────────────────       ─────────────────────────
• Query optimization            • OWASP top 10 audit            • App store submissions
• CDN tuning                    • Dependency scan               • Landing page
• Redis caching strategy        • Penetration test              • User documentation
• k6 load test scripts          • GDPR compliance               • Monitoring dashboards
• Grafana boards                  (export, deletion)            • Alerting rules + runbook
```

### Timeline with parallelism

```
Week:  1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22
       ├───────┤
       Phase 0 (3 agents)
               ├───────────────┤
               Phase 1 — Files (3 agents)
                               ├───────────────────────┤
                               Phase 2 — Sync (3 agents)
                               ├───────────────┤
                               Phase 4 — Photos Basic (2 agents)    ← PARALLEL with Sync
                                       ├───────────┤
                                       Phase 3 — Versioning (2 agents) ← PARALLEL with Sync
                                               ├───────────────────────┤
                                               Phase 5 — Photos AI (3 agents)
                                                               ├───────────────┤
                                                               Phase 6 — Photos Social (2 agents)
                                                               ├───────────────┤
                                                               Phase 7 — B2B (2 agents) ← PARALLEL
                                                                               ├───────────────┤
                                                                               Phase 8 — Production (3 agents)
```

**Sequential estimate:** ~28-38 weeks
**Parallel estimate (max agents):** ~20-22 weeks
**Peak agent count:** 6 (during weeks 5-8 when Sync + Photos + Versioning overlap)

### Agent coordination rules

- Each agent works in a **git worktree** (isolated branch).
- PRs reviewed before merge to `main`. CI must pass.
- **Code review: Hydra agent.** Every PR is reviewed by the `hydra` subagent
  before merge. Hydra delegates code review to the Codex plugin and filters
  feedback with its own judgement. No PR merges without Hydra approval.
- **Shared library changes** (DTOs, contracts) require coordination — one agent
  owns `src/shared/` at a time, others consume via NuGet-like project reference.
- **Database migrations** are sequential per schema. Agent must pull latest
  `main` before adding a migration.
- **API contracts** (proto files, OpenAPI specs) defined upfront in Phase 0's
  shared library. Breaking changes require cross-team agreement.
- **Flutter feature modules** are isolated by design — merge conflicts rare.

## Testing requirements

Every phase must meet these criteria before merge to `main`:

### Integration tests (mandatory)

Every service and every feature module must have integration tests covering
real infrastructure interactions. No mocks for things that can run locally.

**Backend (.NET):**
- Use `WebApplicationFactory<T>` for HTTP integration tests.
- Real PostgreSQL (Docker via Testcontainers).
- Real Azure Blob Storage (Azurite emulator via Testcontainers).
- Real Redis (Docker via Testcontainers).
- Real Service Bus (emulator or in-memory transport for tests).
- Test inter-service communication (gRPC + Service Bus event handlers).
- Every API endpoint has at least one happy-path + one error-path integration test.

**Flutter:**
- Integration tests via `integration_test` package.
- Test against real running backend (Docker Compose in CI).
- Cover: login → upload → browse → download → delete flow.
- Cover: photo upload → timeline → album → search flow.
- Platform-specific sync tests on CI runners where feasible (Windows, Linux).

**Per-phase integration test requirements:**

| Phase | Required integration test coverage |
|-------|-----------------------------------|
| 0 | Register → login → JWT refresh → protected endpoint. Auth edge cases (expired token, invalid credentials, duplicate email). |
| 1 | Chunked upload → metadata created → download matches original. Folder CRUD. Share link → access → permission denied for wrong role. Trash → restore. Search returns results. |
| 2 | File change on device A → sync event → device B receives change. Delta upload (modify large file → only changed chunks uploaded). Offline queue → reconnect → replay. Conflict detection + resolution. |
| 3 | File update → version created in blob storage → version list API. Restore old version. Retention policy deletes old versions. |
| 4 | Photo upload → EXIF extracted → thumbnails generated → timeline API returns photo. Album CRUD. Mobile backup simulation. |
| 5 | Photo upload → AI tags assigned → search by tag. Face detection → person created → second photo of same person → clustered. Memory generated for "this day". |
| 6 | Shared album created → invite → member adds photo → activity feed updated. Editor: apply crop → save → non-destructive (original intact). |
| 7 | Tenant created → admin invites member → member sees tenant files. Role change → permission enforced. Quota exceeded → upload blocked. Audit log records admin actions. |
| 8 | Load test baselines established. GDPR export produces valid zip. Account deletion removes all user data from PG + blob storage. |

### Test infrastructure

```bash
# Run all integration tests locally
docker-compose -f docker-compose.test.yml up -d   # PG, Redis, Azurite, Service Bus emulator
dotnet test --filter Category=Integration
cd src/client/zdrive_app && flutter test integration_test/

# CI runs the same via GitHub Actions with Testcontainers
```

### Test naming convention

```
{MethodOrFeature}_{Scenario}_{ExpectedResult}
```

Example: `ChunkedUpload_LargeFile_OnlyChangedChunksUploaded`

### No phase exits without green integration tests

A phase sync point (merge to `main`) is blocked until:
1. All integration tests for that phase pass in CI.
2. Hydra agent has reviewed and approved the PR.
3. No regression in existing integration tests from previous phases.
