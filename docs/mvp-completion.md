# MVP completion and rollout notes

This change improves existing file storage, version restore, desktop synchronization and recovery UX. It does not establish completion of the whole product or record a production deployment. The [implementation plan](superpowers/plans/2026-09-15-mvp-completion.md) tracks remaining validation.

## Integrated changes

- **Change feed:** a cancellable PostgreSQL transaction obtains a SHARE lock before reading the feed page, preventing late commits from being skipped by an advanced cursor. The existing five-second hold-back remains.
- **Version downloads:** updated Flutter downloads resolve the committed metadata manifest and request its immutable snapshot. StorageService validates the optional `manifestHash` query parameter and echoes the selected hash; the client requires that confirmation. Restoring a version now applies the configured version-count retention.
- **Native sync:** verified chunks stream into sibling staging files before destination replacement. Failed transfers preserve existing content, and the SQLite mirror updates only after installation. Local edits and path links are checked before replacement. A filesystem identity check prevents cleanup from deleting the installed file after a rename that changes only letter case.
- **Recovery UX:** trash supports explicit pagination, localized failures and retry. Trash and version history preserve useful state, prevent duplicate operations and show pending work. Unexpected errors use a localized fallback.
- **Search UX:** request generations prevent stale responses from replacing newer results or repopulating a cleared screen. Clearing cancels pending debounce work; failures use localized messages with retry.
- **Manual desktop downloads:** the save dialog selects a destination before transfer starts. Verified content streams into staging before replacement; cancelling the dialog starts no transfer, and failed downloads preserve existing content.

## Validation

- Backend: **323 passed, zero failed** across ApiGateway, AuthService, FileService, NotificationService, PhotoService, StorageService, SyncService and BackupCli test projects. Evidence is in their `TestResults/mvp-completion_net8.0_20260915*.trx` reports.
- Regression coverage includes out-of-order feed commits, immutable snapshot selection and isolation, restore retention, and downloading restored content before the legacy blob flip.
- The joint restore/download integration test uses service test hosts through a simulated gateway. It does not prove the deployed gateway or a Flutter GUI journey.
- Flutter at `4ec29b7`: **340 passed and one preexisting skip** in the combined suite; **48 passed** in the focused sync suite. Full `flutter analyze` reported **No issues found**.
- Case-only rename regressions with unchanged and changed content failed before the fix on Windows and passed after it.
- Hydra **approved** the aggregate `2c3a37b..4ec29b7` through Codex CLI 0.154 with `gpt-6-astra`. Its only P1 finding, case-only rename cleanup, is fixed in `4ec29b7`.
- Web and Windows release builds passed at the final source revision. Green CI remains required before merge.

## Rollout order

1. Complete final validation and review, then deploy the updated **FileService and StorageService** before publishing Flutter clients.
2. Verify an authenticated metadata read supplies a committed manifest hash and `GET /api/v1/storage/download/{fileId}/manifest?manifestHash={hash}` returns the same hash. Exercise upload, download and restore through the target gateway.
3. Publish the updated Flutter client and verify file download, sync, trash recovery and version restore on each supported target.

Old clients retain their existing routes and latest-manifest reads. New clients safely reject a StorageService response that lacks the requested `manifestHash` confirmation, so a client-first rollout can interrupt downloads. Do not roll StorageService back behind already-published clients without accounting for that dependency.

Restore still makes two calls: commit FileService metadata, then flip StorageService's mutable latest manifest. Updated snapshot reads select restored content even if the second call fails. Old clients can still read the previous latest content until that flip succeeds. This change does not make restore a cross-service transaction.

## Limits and follow-up work

- **Concurrency:** the feed SHARE lock covers the whole `files.file_changes` table, including other tenants. Long writes can delay polls, and reads briefly block writes. Measure lock waits and polling latency under load.
- **Local durability:** filesystem installation and SQLite updates are not atomic together. A crash can leave ignored staging files or content that a later pull reports as a local conflict. Destination replacement also depends on operating-system rename semantics.
- **Download size:** web and mobile retain byte-based save paths that buffer complete files. Native sync streaming does not remove those platform limits.
- **Public sharing:** the recipient journey remains incomplete. [share_dialog.dart](../src/client/zdrive_app/lib/features/files/presentation/widgets/share_dialog.dart) line 172 builds `/share/{token}`; [SharesController.cs](../src/services/FileService/ZDrive.FileService.Api/Controllers/SharesController.cs) lines 15 and 48 expose `/api/v1/shares/link/{token}`. The shares route in [ApiGateway/appsettings.json](../src/services/ApiGateway/appsettings.json) line 62 requires authentication. [app_router.dart](../src/client/zdrive_app/lib/shared/router/app_router.dart) line 25 defines authenticated application routing with no public share page.
- **End-to-end proof:** run full Flutter user journeys against the real backend and gateway, including download, restore and interrupted-transfer recovery.
- **Platform support:** finish macOS entitlements and persistent folder bookmarks, and verify mobile background backup on devices.
- **Remaining product tracks:** complete the photo processing pipeline and AI, Entra identity rollout, blob garbage collection and change-feed retention. Production operations and store distribution require separate verification.
