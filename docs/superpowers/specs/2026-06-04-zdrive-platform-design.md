# zDrive Platform — Design Specification

**Date:** 2026-06-04
**Status:** Approved
**Author:** Martin + Claude

## 1. Vision

Cloud storage platform combining OneDrive-level file sync with Google
Photos-level photo management. Cross-platform (Windows, macOS, Android, iOS,
Web). Azure Blob Storage as the storage backbone. B2C + B2B target market.

## 2. Technology decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend | .NET 8+ microservices | Native Azure SDK, strong typing, performance |
| Clients | Flutter | Single codebase for all 5 platforms |
| Architecture | Microservices (from start) | Independent scaling and deployment per domain |
| Database | PostgreSQL | Open-source, JSON support, full-text search, Azure managed |
| Object storage | Azure Blob Storage | Native versioning, tiering, CDN integration |
| Auth | Custom JWT | Full control, no per-auth cost, tailored to multi-tenant model |
| Sync | Delta (block-level) | Bandwidth efficient, production-grade, rsync-like |
| Photo AI | Azure AI Vision + Face API | Managed, scalable, no ML infra to maintain |
| Messaging | Azure Service Bus | Reliable async inter-service events |
| Real-time | Azure SignalR Service | Managed WebSocket at scale |

## 3. Microservices

### 3.1 API Gateway

- Technology: YARP (Yet Another Reverse Proxy)
- Responsibilities: routing, rate limiting, JWT validation, request aggregation
- Exposes unified REST API to all clients
- No business logic

### 3.2 Auth Service

- Custom JWT (access 15min + refresh 30 days, rotation on use)
- Registration (email + password), login, password reset
- User profile management
- Role management: owner, admin, member, viewer
- Tenant-scoped permissions for B2B
- Endpoints:
  - `POST /api/v1/auth/register`
  - `POST /api/v1/auth/login`
  - `POST /api/v1/auth/refresh`
  - `POST /api/v1/auth/forgot-password`
  - `GET/PUT /api/v1/users/me`
  - `GET/PUT/DELETE /api/v1/tenants/{id}/members`

### 3.3 File Service

- File and folder CRUD with tree structure
- Metadata: name, size, mime type, timestamps, parent, permissions
- Sharing: link-based (token + expiry) and direct (user-to-user)
- Permissions: read, write, admin (per file/folder, inheritable)
- Soft delete with 30-day trash retention
- Search: full-text on file names + metadata (PostgreSQL tsvector)
- Endpoints:
  - `GET /api/v1/files/{id}`
  - `GET /api/v1/files/{id}/children`
  - `POST /api/v1/files` (create/mkdir)
  - `PUT /api/v1/files/{id}` (rename, move)
  - `DELETE /api/v1/files/{id}`
  - `POST /api/v1/files/{id}/share`
  - `GET /api/v1/files/{id}/versions`
  - `POST /api/v1/files/{id}/restore` (from trash or version)
  - `GET /api/v1/search?q=...`

### 3.4 Storage Service

- Abstraction over Azure Blob Storage
- Chunked upload: client splits file → uploads chunks → server assembles manifest
- Chunked download: client requests manifest → downloads only needed chunks
- Block deduplication: identical chunks (by hash) stored once
- Version management: maps Azure blob version IDs to semantic file versions
- Thumbnail/preview serving via CDN
- Storage quota enforcement
- Endpoints:
  - `POST /api/v1/storage/upload/init` (get upload session ID)
  - `PUT /api/v1/storage/upload/{sessionId}/chunk/{index}`
  - `POST /api/v1/storage/upload/{sessionId}/complete`
  - `GET /api/v1/storage/download/{fileId}` (full or range)
  - `GET /api/v1/storage/download/{fileId}/chunk/{hash}`
  - `GET /api/v1/storage/thumbnail/{photoId}/{size}`

### 3.5 Sync Service

- Delta sync engine (block-level diffing with rolling hash)
- Device registry: tracks each client device and its sync cursor
- Change tracking: ordered sequence of sync events per user
- Sync protocol:
  1. Client sends current cursor + local changes
  2. Server returns remote changes since cursor
  3. Client applies remote, uploads local
  4. Server advances cursor
- Conflict resolution:
  - Auto: last-write-wins (based on timestamp + sequence number)
  - Manual: fork both versions, prompt user in UI
- Endpoints:
  - `POST /api/v1/sync/register-device`
  - `POST /api/v1/sync/pull` (get changes since cursor)
  - `POST /api/v1/sync/push` (upload local changes)
  - `POST /api/v1/sync/files/{id}/chunks` (delta upload)
  - `GET /api/v1/sync/conflicts`
  - `POST /api/v1/sync/conflicts/{id}/resolve`

### 3.6 Photo Service

- Processing pipeline (async, Service Bus triggered):
  1. **Ingest**: EXIF extraction, thumbnail generation (256/1024/2048 WebP)
  2. **AI Analysis**: Azure AI Vision (tags, categories), Face API (detection + 128d embeddings), OCR
  3. **Clustering**: face→person (cosine similarity threshold 0.85), geo+time→trip
  4. **Memory Generation**: daily cron job
- Albums: manual, auto-generated (by person, location, date), shared
- Memories:
  - "This day" — photos from same date in past years
  - "Trip" — geo+time cluster > 10 photos outside home radius
  - "Best of month" — top photos by AI quality score
- Editor: client-side, non-destructive (JSON edit ops, original untouched)
  - Crop, rotate, filters (preset + custom), brightness, contrast, saturation
- Collages: client-side template rendering, saved as new photo
- Search: text → tag matching + date parsing + geo lookup, ranked results
- Endpoints:
  - `GET /api/v1/photos/timeline?from=&to=&limit=`
  - `GET /api/v1/photos/{id}`
  - `GET /api/v1/photos/search?q=...`
  - `GET /api/v1/photos/faces` (all persons)
  - `PUT /api/v1/photos/faces/{personId}` (rename, merge)
  - `GET/POST/PUT/DELETE /api/v1/albums/{id}`
  - `POST /api/v1/albums/{id}/photos`
  - `GET /api/v1/memories`
  - `POST /api/v1/photos/{id}/edits` (save edit operations)

### 3.7 Notification Service

- Real-time sync events via SignalR (file changed, new photo, share invite)
- Push notifications: FCM (Android), APNs (iOS), WNS (Windows)
- Email: transactional (password reset, share invites, weekly digest)
- User preferences: per-channel opt-in/out
- Endpoints:
  - `GET /api/v1/notifications`
  - `PUT /api/v1/notifications/preferences`
  - SignalR hub: `/hubs/sync`

## 4. Data model

### 4.1 PostgreSQL schemas

Each service owns its schema. Cross-service data access via API calls only.

**auth schema:**
```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    display_name    VARCHAR(100) NOT NULL,
    avatar_url      VARCHAR(500),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    role            VARCHAR(20) NOT NULL DEFAULT 'member',
    quota_bytes     BIGINT NOT NULL DEFAULT 5368709120, -- 5GB
    used_bytes      BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    plan            VARCHAR(50) NOT NULL DEFAULT 'free',
    max_users       INT NOT NULL DEFAULT 1,
    max_storage     BIGINT NOT NULL DEFAULT 5368709120,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    token_hash      VARCHAR(255) NOT NULL,
    device_id       UUID,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**file schema:**
```sql
CREATE TABLE files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    parent_id       UUID REFERENCES files(id),
    name            VARCHAR(500) NOT NULL,
    is_folder       BOOLEAN NOT NULL DEFAULT false,
    size_bytes      BIGINT NOT NULL DEFAULT 0,
    mime_type       VARCHAR(100),
    blob_path       VARCHAR(1000),
    manifest_hash   VARCHAR(64),
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    name_tsv        TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', name)) STORED
);

CREATE TABLE file_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id),
    version_number  INT NOT NULL,
    blob_version_id VARCHAR(255) NOT NULL,
    size_bytes      BIGINT NOT NULL,
    manifest_hash   VARCHAR(64),
    created_by      UUID NOT NULL,
    comment         VARCHAR(500),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shares (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id),
    shared_by       UUID NOT NULL,
    shared_with     UUID,                    -- NULL for link shares
    permission      VARCHAR(20) NOT NULL,    -- read, write, admin
    link_token      VARCHAR(100) UNIQUE,
    password_hash   VARCHAR(255),
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**sync schema:**
```sql
CREATE TABLE devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    name            VARCHAR(200) NOT NULL,
    platform        VARCHAR(50) NOT NULL,
    sync_cursor     BIGINT NOT NULL DEFAULT 0,
    last_sync_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sync_events (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID NOT NULL,
    device_id       UUID NOT NULL REFERENCES devices(id),
    file_id         UUID NOT NULL,
    event_type      VARCHAR(20) NOT NULL,  -- create, update, delete, move, rename
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_events_user_cursor ON sync_events(user_id, id);
```

**photo schema:**
```sql
CREATE TABLE photos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL,
    user_id         UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    taken_at        TIMESTAMPTZ,
    lat             DOUBLE PRECISION,
    lng             DOUBLE PRECISION,
    camera_make     VARCHAR(100),
    camera_model    VARCHAR(100),
    width           INT,
    height          INT,
    orientation     SMALLINT,
    quality_score   REAL,
    processing_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE photo_tags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    photo_id        UUID NOT NULL REFERENCES photos(id),
    tag             VARCHAR(100) NOT NULL,
    confidence      REAL NOT NULL,
    source          VARCHAR(10) NOT NULL DEFAULT 'ai',  -- ai, manual
    tag_tsv         TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', tag)) STORED
);

CREATE TABLE faces (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    photo_id        UUID NOT NULL REFERENCES photos(id),
    person_id       UUID REFERENCES persons(id),
    bounding_box    JSONB NOT NULL,        -- {x, y, w, h}
    embedding       VECTOR(128) NOT NULL   -- pgvector for similarity search
);

CREATE TABLE persons (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    name            VARCHAR(200),
    representative_face_id UUID,
    photo_count     INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE albums (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    name            VARCHAR(300) NOT NULL,
    type            VARCHAR(20) NOT NULL DEFAULT 'manual',  -- manual, auto, shared
    cover_photo_id  UUID REFERENCES photos(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE album_photos (
    album_id        UUID NOT NULL REFERENCES albums(id),
    photo_id        UUID NOT NULL REFERENCES photos(id),
    sort_order      INT NOT NULL DEFAULT 0,
    added_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (album_id, photo_id)
);

CREATE TABLE memories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    type            VARCHAR(20) NOT NULL,   -- this_day, trip, best_of
    title           VARCHAR(300) NOT NULL,
    date_from       DATE,
    date_to         DATE,
    photo_ids       UUID[] NOT NULL,
    seen            BOOLEAN NOT NULL DEFAULT false,
    generated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 4.2 Azure Blob Storage layout

```
Container: zdrive-storage (versioning ON, soft delete 90 days)
  {tenantId}/{userId}/files/{fileId}/chunks/{chunkSHA256}.blk
  {tenantId}/{userId}/files/{fileId}/manifest.json

Container: zdrive-photos
  {tenantId}/{userId}/{photoId}/original.{ext}
  {tenantId}/{userId}/{photoId}/thumb_256.webp
  {tenantId}/{userId}/{photoId}/thumb_1024.webp
  {tenantId}/{userId}/{photoId}/preview_2048.webp

Container: zdrive-system (no versioning)
  temp-uploads/{sessionId}/{chunkIndex}
```

## 5. Delta sync protocol

### 5.1 Chunking algorithm

- Rolling hash (Rabin fingerprint) with target chunk size ~4MB
- Minimum chunk: 1MB, maximum chunk: 16MB
- Content-defined chunking ensures stable boundaries across edits
- Each chunk identified by SHA-256 hash

### 5.2 Sync flow

```
Client                          Server
  │                                │
  ├─ POST /sync/pull ────────────►│  "what changed since cursor 42?"
  │  {device_id, cursor: 42}      │
  │                                │
  │◄── [{event_id: 43, ...}, ...]─┤  "events 43-67"
  │                                │
  │  (apply remote changes)        │
  │                                │
  ├─ POST /sync/push ────────────►│  "here are my local changes"
  │  {events: [...]}               │
  │                                │
  │  (for each changed file:)      │
  ├─ PATCH /sync/files/{id}/chunks│  upload changed chunks only
  │  {added: [hash...],           │
  │   removed: [hash...],         │
  │   manifest: {...}}            │
  │                                │
  │◄── {new_cursor: 71} ─────────┤  "you're synced to 71"
  │                                │
```

### 5.3 Conflict resolution

| Scenario | Resolution |
|----------|-----------|
| Same file, different chunks modified | Auto-merge (non-overlapping changes) |
| Same file, same chunk modified | Fork: keep both as `file.txt` and `file (conflict).txt` |
| File deleted on A, modified on B | Keep modified version, notify A |
| Folder deleted on A, file added inside on B | Recreate folder path, keep new file |

## 6. Photo processing pipeline

### 6.1 Event flow

```
PhotoUploaded (Service Bus)
  → Ingest Worker
    → EXIF parsed, thumbnails generated
    → PhotoIngested event

PhotoIngested (Service Bus)
  → AI Analysis Worker
    → Azure AI Vision: tags[], categories[], description
    → Azure Face API: faces[{boundingBox, embedding[128]}]
    → Azure OCR: text (if detected)
    → PhotoAnalyzed event

PhotoAnalyzed (Service Bus)
  → Clustering Worker
    → For each face: find nearest person (pgvector <=> operator)
      → distance < 0.15 → assign to person
      → distance >= 0.15 → create new person
    → Geo+time clustering: DBSCAN on (lat, lng, timestamp)
      → cluster with >10 photos outside 50km of home → "trip"
    → ClusteringComplete event

Daily Cron (0 2 * * *)
  → Memory Generator
    → Query: photos WHERE taken_at::date = today - N years
    → Query: trip clusters from past month not yet memorized
    → Query: top 20 photos by quality_score from past month
    → Insert into memories table
    → Push notification to user
```

### 6.2 Performance targets

| Operation | Target |
|-----------|--------|
| Thumbnail generation | < 5s per photo |
| AI analysis | < 10s per photo |
| Face clustering | < 2s per photo |
| Timeline load (100 thumbs) | < 500ms |
| Search results | < 300ms |

## 7. Flutter client architecture

### 7.1 Project structure

```
lib/
├── core/
│   ├── auth/              # JWT storage (flutter_secure_storage), refresh interceptor
│   ├── sync/
│   │   ├── sync_engine.dart         # orchestration, queue management
│   │   ├── chunk_splitter.dart      # Rabin fingerprint, SHA-256
│   │   ├── conflict_resolver.dart   # detection + UI prompt
│   │   └── file_watcher.dart        # platform channel → native watchers
│   ├── network/           # Dio client, gRPC channels, retry policy
│   ├── storage/           # SQLite (drift), Hive KV
│   └── di/                # get_it + injectable setup
│
├── features/
│   ├── files/
│   │   ├── data/          # FileRepository impl, FileDto
│   │   ├── domain/        # FileEntity, use cases (UploadFile, MoveFile, ShareFile)
│   │   └── presentation/  # FileBrowserPage, FileDetailSheet, ShareDialog
│   ├── photos/
│   │   ├── data/          # PhotoRepository, AlbumRepository
│   │   ├── domain/        # Photo, Album, Memory, Person entities
│   │   └── presentation/  # TimelinePage, AlbumPage, MemoryViewer, PhotoEditor
│   ├── auth/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/  # LoginPage, RegisterPage, ProfilePage
│   ├── settings/
│   └── admin/             # B2B: TenantDashboard, MemberManagement, AuditLog
│
├── platform/
│   ├── windows/           # Win32 FileSystemWatcher via FFI, shell extension
│   ├── macos/             # FSEvents via FFI, Finder extension
│   ├── android/           # ContentObserver, WorkManager, SAF
│   └── ios/               # NSFileCoordinator, BGTaskScheduler, PHPhotoLibrary
│
└── shared/
    ├── widgets/           # reusable UI components
    ├── theme/             # light/dark theme, brand colors
    ├── l10n/              # localization (CS, EN minimum)
    └── router/            # go_router setup
```

### 7.2 Platform-specific sync

| Platform | File watching | Background sync | System integration |
|----------|-------------|----------------|-------------------|
| Windows | `ReadDirectoryChangesW` via FFI | Windows Service (separate exe) | Shell extension (context menu, overlay icons) |
| macOS | `FSEvents` via FFI | LaunchAgent (plist) | Finder Sync Extension (overlay badges) |
| Android | `ContentObserver` + `FileObserver` | `WorkManager` periodic + `ForegroundService` for active sync | SAF for external storage, `MediaStore` for photos |
| iOS | `NSFileCoordinator` | `BGAppRefreshTask` (limited, ~30s) + push-triggered background fetch | `PHPhotoLibrary` for photo backup, Files.app integration via `FileProvider` |
| Web | N/A (no local sync) | N/A | Drag & drop upload, clipboard paste |

### 7.3 Offline support

- SQLite mirrors file/photo metadata for offline browsing
- Operation queue: all mutations queued locally, replayed on reconnect
- Queue persisted in Hive (survives app restart)
- Conflict detection on replay (server version > local base version)
- Photos: thumbnails cached in app storage for offline viewing
- Configurable "available offline" flag per file/folder (pin for offline)

## 8. Infrastructure

### 8.1 Azure resources

```
Resource Group: rg-zdrive-{env}

Compute:
  AKS Cluster (Standard_D4s_v5 nodes, autoscale 2-10)
    Namespace: zdrive-services (7 service deployments)
    Namespace: zdrive-infra (Redis, Seq)

Storage:
  Storage Account: stzdrive{env}
    Container: zdrive-storage (Blob versioning ON, soft delete 90d, Hot tier)
    Container: zdrive-photos (Hot tier, CDN enabled)
    Container: zdrive-system (Hot tier, no versioning)

Data:
  Azure Database for PostgreSQL Flexible Server (Standard_D2ds_v4)
    Extensions: pgvector, pg_trgm
  Azure Cache for Redis (Standard C1)

Messaging:
  Azure Service Bus (Standard tier)
    Queues: photo-ingest, photo-analyze, photo-cluster
    Topics: file-events, sync-events, notification-events

Networking:
  Azure CDN (Standard Microsoft, zdrive-photos + web client)
  Azure SignalR Service (Standard tier)
  Azure Application Gateway (WAF v2) — optional, AKS Ingress alternative

Security:
  Azure Key Vault (secrets, certificates)
  Azure Container Registry

AI:
  Azure AI Services (S0 tier)
    Vision API
    Face API
```

### 8.2 Environments

| Environment | Purpose | AKS nodes | PG tier |
|-------------|---------|-----------|---------|
| dev | Local + shared dev | Docker Compose | Docker |
| staging | Pre-production testing | 2 nodes | Burstable B2s |
| production | Live | 3-10 autoscale | Standard D2ds_v4 |

### 8.3 CI/CD (GitHub Actions)

```yaml
# Per .NET service:
on push to main (path: src/services/{name}/**):
  → dotnet build → dotnet test → docker build → push ACR
  → helm upgrade staging

on release tag (v*):
  → helm upgrade production

# Flutter:
on push to main (path: src/client/**):
  → flutter test → flutter build web → deploy CDN (staging)

on release tag (v*):
  → flutter build web → deploy CDN (production)
  → flutter build apk → upload Play Store (internal)
  → flutter build ipa → upload TestFlight
  → flutter build windows → GitHub Release
  → flutter build macos → GitHub Release
```

## 9. Security considerations

- Passwords: Argon2id (not bcrypt — resistant to GPU attacks)
- JWT: RS256 (asymmetric) — public key distributable to services for validation
- Blob access: SAS tokens with short expiry for direct client↔blob transfers
- File sharing links: cryptographically random tokens, optional password + expiry
- Rate limiting: per-IP and per-user at API Gateway
- Input validation: FluentValidation on every endpoint
- SQL injection: parameterized queries only (EF Core)
- CORS: whitelist known client origins
- Tenant isolation: EF Core global query filters + middleware validation
- Audit log: all admin actions logged with actor, action, target, timestamp
- GDPR: data export endpoint, account deletion (hard delete after grace period)

## 10. Implementation phases (detailed)

### Phase 0 — Foundation (2-3 weeks)

**Goal:** Skeleton that builds, deploys, authenticates.

- [ ] Initialize repo structure (src/services, src/client, infra, docs)
- [ ] Docker Compose: PostgreSQL, Redis, Service Bus emulator
- [ ] API Gateway with YARP (routing config, health aggregation)
- [ ] Auth Service: register, login, JWT issue/refresh, user CRUD
- [ ] Shared library: common DTOs, error handling, correlation ID middleware
- [ ] Flutter shell: login/register, authenticated home screen, go_router
- [ ] CI pipeline: build + test for all services + Flutter
- [ ] PostgreSQL migrations (auth schema)

**Exit criteria:** User can register, login, see empty home screen. CI green.

### Phase 1 — File Storage (4-5 weeks)

**Goal:** Upload, browse, download, share files via web and mobile.

- [ ] Storage Service: blob upload (simple + chunked), download, SAS token generation
- [ ] File Service: CRUD, folder tree, metadata, soft delete, trash
- [ ] File sharing: link-based with token, direct user-to-user
- [ ] Flutter file browser: folder navigation, breadcrumbs, grid/list view
- [ ] Upload flow: pick file → chunked upload → progress → metadata
- [ ] Download flow: tap → stream download → open/save
- [ ] Trash view + restore
- [ ] Search (file name, full-text via tsvector)
- [ ] Deploy web client to CDN

**Exit criteria:** User can upload/download/organize/share files from web + mobile.

### Phase 2 — Sync Engine (4-6 weeks)

**Goal:** Desktop sync folder, real-time push, offline support.

- [ ] Rabin fingerprint chunking in Dart + server-side verification
- [ ] Sync protocol: pull/push with cursors
- [ ] Device registry + sync state tracking
- [ ] Windows sync agent (FileSystemWatcher, system tray, overlay icons)
- [ ] macOS sync agent (FSEvents, menu bar, Finder badges)
- [ ] SignalR hub for real-time file change notifications
- [ ] Conflict detection + resolution UI
- [ ] Offline operation queue (Hive) + replay on reconnect
- [ ] Mobile background sync (WorkManager / BGTaskScheduler)

**Exit criteria:** File change on device A appears on device B within 30s.
Desktop folder stays in sync. Offline edits sync on reconnect.

### Phase 3 — Versioning (2-3 weeks)

**Goal:** View file history, restore previous versions.

- [ ] Enable Azure Blob Versioning on storage containers
- [ ] file_versions table: semantic metadata per version
- [ ] Version history UI: list versions, preview, restore, compare (text files)
- [ ] Version comments (optional label on save)
- [ ] Retention policy: configurable per tenant (default: 30 versions or 90 days)
- [ ] Quota impact: versions count toward storage used

**Exit criteria:** User can view version history, restore any version, see diff for text.

### Phase 4 — Photos: Basics (3-4 weeks)

**Goal:** Photo timeline, albums, mobile auto-backup.

- [ ] Photo ingest worker: EXIF extraction, thumbnail generation (3 sizes, WebP)
- [ ] Timeline view: chronological grid, pinch-to-zoom (day/month/year)
- [ ] Full-screen photo viewer with swipe navigation
- [ ] Manual album creation + photo add/remove/reorder
- [ ] Auto-backup from mobile camera roll (Android + iOS)
- [ ] Backup settings: Wi-Fi only, original/compressed, specific folders
- [ ] CDN serving for thumbnails

**Exit criteria:** Photos auto-upload from phone, appear in timeline, organized in albums.

### Phase 5 — Photos: AI + Memories (4-5 weeks)

**Goal:** Smart search, face recognition, automated memories.

- [ ] AI Analysis Worker: Azure AI Vision tags, Face API embeddings
- [ ] Photo tags stored in PostgreSQL, searchable
- [ ] Face detection + pgvector storage
- [ ] Face clustering: cosine similarity matching, person management
- [ ] Person gallery: "People" tab, rename, merge, hide
- [ ] Search: natural text → tag + date + location query
- [ ] Memory Generator: "this day", trips (geo cluster), monthly best
- [ ] Memory viewer: card-style, swipeable, dismissable
- [ ] Push notification for new memories

**Exit criteria:** Search "beach 2024" returns relevant photos. Faces grouped by person.
Daily memory notifications working.

### Phase 6 — Photos: Social + Editor (3-4 weeks)

**Goal:** Shared albums, photo editor, collages.

- [ ] Shared albums: create, invite via link, member permissions
- [ ] Shared album activity feed: who added what
- [ ] Comments + reactions on photos in shared albums
- [ ] Photo editor: crop, rotate, brightness, contrast, saturation, filters
- [ ] Non-destructive edit model (JSON operations, original preserved)
- [ ] Collage templates (grid, freeform, timeline)
- [ ] Collage generator: select photos, pick template, render, save

**Exit criteria:** Multiple users contribute to shared album. Editor produces quality results.
Collages generated from templates.

### Phase 7 — B2B Features (3-4 weeks)

**Goal:** Multi-tenant admin, enterprise controls.

- [ ] Tenant admin dashboard: user count, storage usage, activity
- [ ] Member management: invite, remove, change role
- [ ] Bulk provisioning: CSV import of users
- [ ] Per-tenant storage quotas + per-user quotas
- [ ] Audit log: all admin actions queryable by date, actor, action
- [ ] Tenant branding: logo, primary color, custom login page
- [ ] Admin-level sharing controls (disable external sharing, etc.)

**Exit criteria:** Org admin can manage users, view usage, enforce policies.

### Phase 8 — Production Polish (3-4 weeks)

**Goal:** Production-ready, secure, compliant.

- [ ] Performance: query optimization, CDN tuning, Redis caching strategy
- [ ] Load testing: k6 scripts for upload, download, sync, photo timeline
- [ ] Security audit: OWASP top 10 check, dependency scan, penetration test
- [ ] GDPR: data export (zip), account deletion, data residency config
- [ ] App store submissions: Play Store, App Store, Microsoft Store
- [ ] Landing page + user documentation
- [ ] Monitoring dashboards: Grafana boards for each service
- [ ] Alerting: latency > P99, error rate > 1%, disk > 80%
- [ ] Runbook for common incidents

**Exit criteria:** Load test passes at 10x expected traffic. Security audit clean.
Apps published. Monitoring and alerting operational.
