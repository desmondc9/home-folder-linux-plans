# OpenCode V2 Global AGENTS.md Audit and Backup

- Environment: WSL2 Ubuntu 26.04 on Windows 11 physical host `DESKTOP-J7NBNU4`; OpenCode v2.0.10

## Background and Goal

Audit `/home/desmond/.config/opencode/AGENTS.md` against OpenCode V2 behavior and the current machine, make its primary language English, correct confirmed discrepancies after user approval, and preserve a verifiable snapshot in `~/plans`.

## Scope

### In scope

- Validate the OpenCode V2 global instruction path and loading behavior.
- Validate locally declared tools and referenced files.
- Translate Chinese-first content into English while retaining selected Chinese terminology as secondary labels.
- Correct user-approved factual, security, and workflow inconsistencies.
- Back up the corrected non-secret files with checksums.

### Out of scope

- Translating the complete supporting documents under `~/docs`.
- Copying credential contents into this public repository.
- Modifying unrelated existing changes in the plans repository.

## Findings and Decisions

The detailed audit is recorded in [findings.md](./findings.md). Key decisions were:

- Use `AGENTS.md` first and manually read `CLAUDE.md` only when no project `AGENTS.md` exists.
- Remove the false mise/Go installation claim rather than installing them.
- Create worktrees directly from fresh `origin/<default-branch>`.
- Keep submodules at umbrella-pinned commits unless a task explicitly updates them.
- Use `implementation-phase-*.md` for multi-phase plans.
- Require sanitized or synthetic fixtures; never commit raw operational data.
- Use `git branch -D` only after confirming a squash-merged PR.
- Correct the ADO credential path and restrict its mode to `0600`.

## Acceptance Criteria

- [x] OpenCode V2 documentation confirms the global `AGENTS.md` location and behavior.
- [x] Machine-specific tool claims are verified or corrected.
- [x] English is the primary language throughout global `AGENTS.md`.
- [x] Retained Chinese text appears only as a secondary terminology label.
- [x] Referenced local files exist and stale paths are corrected.
- [x] Credential contents are excluded from the archive.
- [x] Backup files have recorded and verified SHA-256 checksums.

## Backup

The corrected snapshot and manifest are stored in:

[`backup-2026-09-20-154641/`](./backup-2026-09-20-154641/)

## Performance and Capacity (性能与容量)

The performance gate was not triggered because this task changes documentation and local instruction files only; it adds no runtime path, query, cache, external call, migration, or data-processing workload.

## References

- <https://opencode.ai/v2/docs/instructions/>
- <https://opencode.ai/v2/docs/config/>
- [Backup manifest](./backup-2026-09-20-154641/MANIFEST.md)
