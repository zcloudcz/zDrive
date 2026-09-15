# MVP Completion Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent tasks and focused review.

**Goal:** Improve the correctness and completeness of existing file and sync flows, including UX details.

**Architecture:** Preserve deployed routes and account identities. Add a safe read boundary to the feed, confirmed immutable manifest selection, and incremental native downloads. Polish existing Flutter screens. Updated FileService and StorageService must precede the Flutter rollout.

**Tech Stack:** .NET 8, PostgreSQL, Azure Blob, Flutter, Bloc, Dio, SQLite.

**Spec:** ../specs/2026-09-15-mvp-completion-design.md

## Global constraints

- Existing user changes remain untouched; implementation uses isolated worktrees.
- Code and documentation in English; user communication in Czech.
- No cloud provisioning, authentication migration or production deployment in this change.
- Regression tests precede behavior changes; no merge without green CI and Hydra review.

## Tasks

- [x] 1. FileService: add cancellable transactional feed-read boundary and integration regression for out-of-order commits. Own IFileDbContext, FileDbContext, GetFileChangesQueryHandler and FileChangeFeedTests. Verify existing feed semantics and backend tests.
- [x] 2. StorageService and Flutter data: accept validated optional manifestHash for snapshot reads and echo the selected hash; updated repository resolves the metadata reference and requires confirmation before download. Test missing/invalid snapshot, isolation and latest-pointer divergence. Apply retention when restoring a version.
- [x] 3. Flutter native sync: integrate verified download stream to sibling temporary file with failure cleanup and delayed replacement, plus regression tests for interrupted/corrupt downloads, destination preservation and mirror updates.
- [x] 4. **Focus on UX details:** integrate trash pagination, retry/localized errors, duplicate-action prevention and lifecycle safety; version history retry, localized errors and visible restore state. Add widget regression coverage.
- [x] 5. Manual desktop downloads: select destination before stream subscription, stage verified content before replacement, and preserve existing content on failure. Verify save-dialog cancellation starts no transfer.
- [x] 6. Search UX: integrate request-generation guards for stale responses, cancel pending debounce work on clear, and add localized errors and retry, with regression coverage.
- [x] 7. Run backend verification: 323 tests passed across eight test projects, including integration tests.
- [x] 8. Run combined Flutter verification after the review fix: 340 passed, one preexisting skip; full analysis reported No issues found.
- [x] 9. Complete web and Windows release builds at the final source revision.
- [x] 10. Repair the P1 case-only rename cleanup issue from Hydra review. Verify unchanged- and changed-content regressions fail before the fix and pass after it on Windows. Focused sync suite: 48 passed.
- [x] 11. Obtain Hydra approval for aggregate source changes `2c3a37b..4ec29b7`.
- [ ] 12. Obtain green CI, and update [completion notes](../../mvp-completion.md) with final results.

## Execution record

- Baseline: backend non-integration tests 179 passed. Flutter SDK requires access outside sandbox; baseline test run started with that access.
- Ruling: user request follows the project analysis and accepts its completion priorities; proceed with the described fixes without another approval loop.
- Ruling: preserve the 5-second hold-back while adding the transaction boundary, keeping current clients and tests compatible.
- Integrated commits: `c627e8d` (feed boundary), `3ed3e45` (snapshot selection and restore retention), `fb65ba4` (trash/version/error UX), `7fdc18e` (streamed native sync and metadata-pinned downloads), `5d81b85` (search request/error handling), `f5cea38` (manual desktop save streaming), `4ec29b7` (filesystem identity guard for case-only rename cleanup).
- Backend evidence: eight `TestResults/mvp-completion_net8.0_20260915*.trx` files under service and BackupCli test projects record 323 passed and zero failed. The joint restore/download test uses an HTTP gateway simulation with service test hosts; it is not a Flutter GUI end-to-end test.
- Combined Flutter suite at `4ec29b7`: 340 passed and one preexisting skip. Focused sync suite: 48 passed. Full analysis: No issues found.
- Web and Windows release builds passed at the final source revision. Green CI remains required before merge.
- Hydra approved `2c3a37b..4ec29b7` through Codex CLI 0.154 with `gpt-6-astra`. Its only P1 finding was fixed by checking filesystem identity before hashing or deleting the old path. Both case-only rename regressions failed before the fix and passed after it on Windows. No production deployment has occurred.
