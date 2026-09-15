# MVP completion and UX details

## Scope

Finish the existing file-storage and desktop-sync experience, following the project analysis accepted by the user. Preserve existing accounts and deployed API compatibility. Do not provision infrastructure or switch authentication providers.

## Acceptance criteria

- A late-committing file change cannot be permanently skipped by the feed cursor.
- Downloaded content is selected by the committed metadata manifest, so a failed legacy latest-manifest flip cannot make restored content invisible to updated clients.
- Native synchronization can write verified chunks to a temporary file rather than assemble the entire file in memory; failed transfers preserve existing local content.
- Focus on UX details: trash and version history have localized errors, retry, visible pending operations, protection from repeated submissions, and safe navigation during asynchronous work. Trash supports more than one server page.
- New behavior has regression tests. Run backend unit tests, relevant real-infrastructure tests where available, Flutter tests, analysis, and web build. Report unavailable validation separately.

## Design

### Change feed

Keep the public cursor contract. Obtain a short PostgreSQL SHARE lock on the file_changes table in a read-committed transaction before reading a page. This waits for outstanding inserts and prevents new inserts from allocating identities until the page has been materialized. Preserve the existing age hold-back for compatibility. Lock acquisition respects cancellation; all exits release the transaction. Tradeoff: a long writer delays polling, favoring correctness over returning a cursor that skips a change.

### Content and versions

Expose immutable manifest reads through the existing StorageService manifest endpoint using an optional manifestHash query parameter. Validate the hash and use the existing tenant/user blob path. Updated downloads resolve FileService metadata first and request that immutable snapshot. Keep the latest-manifest path for old clients. Preserve the legacy restore flip for compatibility and report partial failures honestly; updated download correctness does not depend on the mutable latest pointer.

### Native downloads

Expose a verified chunk stream while preserving the existing byte-array API for web and callers that need it. Native sync consumes the stream into a sibling temporary file, verifies length and hashes, then replaces the destination. Only update the mirror after successful installation. Avoid removing the previous local copy before a transfer succeeds.

### UX details

Use the existing theme, localization and error translation. Add no new design system. Handle empty, loading, failed and retry states, preserve useful lists during operation failures, prevent duplicate destructive operations, and show progress during restores. Add pagination to trash with an explicit load-more interaction using existing localized vocabulary where possible.

## Deferred product tracks

Photo AI, mobile background backup, Entra rollout, production infrastructure changes and store distribution need separate platform and operational verification. Keep their status visible; do not label them complete based on API scaffolding.
