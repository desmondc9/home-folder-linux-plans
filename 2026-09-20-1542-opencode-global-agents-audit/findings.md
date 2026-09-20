# OpenCode V2 Global AGENTS.md Audit

## Scope

- Audited `/home/desmond/.config/opencode/AGENTS.md` against OpenCode V2 documentation and the local environment on 2026-09-20.
- Verified referenced local files, declared CLI tools, internal workflow consistency, language, and credential-file permissions.

## Sources

- OpenCode V2 instructions: <https://opencode.ai/v2/docs/instructions/>
- OpenCode V2 configuration: <https://opencode.ai/v2/docs/config/>
- Installed OpenCode version: `v2.0.10`

## Verified

- `/home/desmond/.config/opencode/AGENTS.md` is the correct global instruction path for OpenCode V2 and is loaded by the active session.
- OpenCode V2 automatically loads `AGENTS.md` files but does not automatically fall back to `CLAUDE.md`.
- `rg`, `fdfind`, `sd`, `batcat`, `jq`, `uv`, `rustup`, `npm`, `podman`, and `podman compose` are available.
- `podman compose` uses the native Docker Compose provider at `/usr/libexec/docker/cli-plugins/docker-compose`.
- All local documents and credential paths referenced by the global instructions exist after correction.

## Corrections Applied

- Translated Chinese-first instructions into English, retaining selected Chinese terminology only as secondary parenthetical labels.
- Removed the false claim that mise and Go were installed.
- Added an explicit `AGENTS.md`-first, `CLAUDE.md`-fallback rule while documenting that the fallback must be read manually.
- Corrected stale `~/.claude/CLAUDE.md` references in linked documents to `~/.config/opencode/AGENTS.md`.
- Corrected the ADO PAT path from the nonexistent `pats.jsonc` to `credentials.jsonc`.
- Changed the ADO credential file mode from `0644` to `0600`.
- Made task worktrees branch directly from fresh `origin/<default-branch>` and stopped routine remote-merging of submodules.
- Unified phased plan names as `implementation-phase-*.md` in the task plan directory.
- Unified missing-work-item behavior: the agent drafts it, gets user confirmation, creates it with an available tracker tool, and links it.
- Required sanitized or synthetic test fixtures and prohibited committing raw operational data.
- Unified post-squash local branch cleanup on `git branch -D` after merge verification.

## Result

The global instruction file is active, predominantly English with approved bilingual terminology, consistent with the verified local environment, and aligned with documented OpenCode V2 instruction behavior.

## Backup

A post-audit snapshot was created at:

`/home/desmond/plans/2026-09-20-1542-opencode-global-agents-audit/backup-2026-09-20-154641/`

The snapshot contains the corrected global `AGENTS.md` and the four corrected supporting documents. `MANIFEST.md` records each source path, backup filename, byte size, SHA-256 checksum, creation time, and restore guidance.

The ADO credential file was deliberately not copied into `~/plans`. Only its path and verified `0600` permission mode are recorded in the manifest.
