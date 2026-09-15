# MVP Completion Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent tasks and focused review.

**Goal:** Improve the correctness and completeness of existing file and sync flows, including UX details.

**Architecture:** Preserve deployed routes and account identities. Add a safe read boundary to the feed, immutable manifest selection, and incremental native downloads. Polish existing Flutter screens.

**Tech Stack:** .NET 8, PostgreSQL, Azure Blob, Flutter, Bloc, Dio, SQLite.

**Spec:** ../specs/2026-09-15-mvp-completion-design.md

## Global constraints

- Existing user changes remain untouched; implementation uses isolated worktrees.
- Code and documentation in English; user communication in Czech.
- No cloud provisioning, authentication migration or production deployment in this change.
- Regression tests precede behavior changes; no merge without green CI and Hydra review.

## Tasks

- [ ] 1. FileService: add cancellable transactional feed-read boundary and integration regression for out-of-order commits. Own IFileDbContext, FileDbContext, GetFileChangesQueryHandler and FileChangeFeedTests. Verify existing feed semantics and backend tests.
- [ ] 2. StorageService and Flutter data: accept validated optional manifestHash for snapshot reads; updated repository resolves the metadata reference before download. Test missing/invalid snapshot, isolation and latest-pointer divergence.
- [ ] 3. Flutter native sync: verified download stream to sibling temporary file with failure cleanup and delayed replacement. Test interrupted/corrupt downloads preserve destination and mirror; run sync suite.
- [ ] 4. **Focus on UX details:** trash pagination, retry/localized errors, duplicate-action prevention and lifecycle safety; version history retry, localized errors and visible restore state. Widget tests for each user-observable failure and recovery.
- [ ] 5. Run backend and Flutter verification, review all diffs, record remaining limitations and concrete follow-up work.

## Execution record

- Baseline: backend non-integration tests 179 passed. Flutter SDK requires access outside sandbox; baseline test run started with that access.
- Ruling: user request follows the project analysis and accepts its completion priorities; proceed with the described fixes without another approval loop.
- Ruling: preserve the 5-second hold-back while adding the transaction boundary, keeping current clients and tests compatible.
