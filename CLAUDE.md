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

Inter-service communication: Azure Service Bus (async events), gRPC (sync calls).

## Repository structure

```
zDrive/
├── src/
│   ├── services/
│   │   ├── ApiGateway/
│   │   ├── AuthService/
│   │   ├── FileService/
│   │   ├── StorageService/
│   │   ├── SyncService/
│   │   ├── PhotoService/
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

### Photo processing pipeline

Async, event-driven via Service Bus:
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
