# MVP completion and UX details

## Scope

Finish the existing file-storage and desktop-sync experience, following the project analysis accepted by the user. Preserve existing accounts and API routes. Deploy the updated FileService and StorageService before the Flutter client, which requires immutable-manifest confirmation. Do not provision infrastructure or switch authentication providers.

## Acceptance criteria

- A late-committing file change cannot be permanently skipped by the feed cursor.
- Downloaded content is selected by the committed metadata manifest, so a failed legacy latest-manifest flip cannot make restored content invisible to updated clients.
- Native synchronization can write verified chunks to a temporary file rather than assemble the entire file in memory; failed transfers preserve existing local content.
- Focus on UX details: trash and version history have localized errors, retry, visible pending operations, protection from repeated submissions, and safe navigation during asynchronous work. Trash supports more than one server page.
- Manual desktop downloads select a destination before subscribing to the verified stream and stage content before replacement; cancelling the save dialog starts no transfer.
- Search discards stale responses after a newer query or clear action, cancels pending debounce work when cleared, and provides localized error and retry states.
- New behavior has regression tests. Run backend unit tests, relevant real-infrastructure tests where available, Flutter tests, analysis, and web and Windows builds. Report unavailable validation separately.

## Implementation status

The planned implementation and case-only rename review fix are integrated through `4ec29b7`. Backend verification passed 323 tests; the combined Flutter suite passed 340 with one preexisting skip, the focused sync suite passed 48, and full analysis reported No issues found. Hydra approved the aggregate `2c3a37b..4ec29b7`; Windows regressions reproduced its only P1 finding before the fix and passed afterward. Web and Windows release builds passed at the final source revision. Green CI remains required before merge. See the [implementation plan](../plans/2026-09-15-mvp-completion.md) for the validation record.

## Design

### Change feed

Keep the public cursor contract. Obtain a short PostgreSQL SHARE lock on the file_changes table in a read-committed transaction before reading a page. This waits for outstanding inserts and prevents new inserts from allocating identities until the page has been materialized. Preserve the existing age hold-back for compatibility. Lock acquisition respects cancellation; all exits release the transaction. Tradeoff: a long writer delays polling, favoring correctness over returning a cursor that skips a change.

### Content and versions

Expose immutable manifest reads through the existing StorageService manifest endpoint using an optional manifestHash query parameter. Validate the hash and use the existing tenant/user blob path. Updated downloads resolve FileService metadata first and request that immutable snapshot, requiring the response to echo the requested manifestHash. A backend without that confirmation causes a safe download failure. Keep the latest-manifest path for old clients. Preserve the legacy restore flip and report partial failures honestly; updated download correctness does not depend on the mutable latest pointer, but old clients remain exposed until the flip succeeds. Apply the configured version-count retention to restored versions as well as uploads.

### Native downloads

Expose a verified chunk stream while preserving the existing byte-array API for web and callers that need it. Native sync consumes the stream into a sibling temporary file, verifies length and hashes, then replaces the destination. Only update the mirror after successful installation. Avoid removing the previous local copy before a transfer succeeds.

Extend staging to manual desktop saves, selecting the destination before stream subscription. Keep the existing byte-based save path on web and mobile. Filesystem replacement and SQLite mirror updates remain separate operations; process interruption can leave ignored staging files or a later local conflict.

### UX details

Use the existing theme, localization and error translation. Add no new design system. Handle empty, loading, failed and retry states, preserve useful lists during operation failures, prevent duplicate destructive operations, and show progress during restores. Add pagination to trash with an explicit load-more interaction using existing localized vocabulary where possible.

For search, track the current request generation so older results cannot replace a newer query or repopulate a cleared screen. Clearing also cancels scheduled debounce work. Translate failures through the existing error helper and offer retry for the current query.

## Deferred product tracks

Public sharing end-to-end, real-backend Flutter journeys, macOS entitlements and persistent folder bookmarks, mobile background backup, the photo pipeline and AI, Entra rollout, blob garbage collection and feed retention remain separate work. Production infrastructure changes and store distribution also need operational verification. See [completion and rollout notes](../../mvp-completion.md) for current evidence and limitations.
