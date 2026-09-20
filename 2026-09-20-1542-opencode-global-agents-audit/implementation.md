# Implementation Record

## Goal

Complete and archive the OpenCode V2 global `AGENTS.md` audit described in [spec.md](./spec.md).

## Completed Tasks

- [x] Verified OpenCode V2 global instruction discovery against official documentation.
- [x] Verified installed CLI tools and the active Podman Compose provider.
- [x] Translated Chinese-first global instructions into English-first wording.
- [x] Applied all user-approved factual and workflow corrections.
- [x] Corrected stale references in four supporting documents.
- [x] Restricted the ADO credential file to mode `0600` without copying its contents.
- [x] Created a post-audit backup with a SHA-256 manifest.
- [x] Verified every checksum in the manifest.
- [x] Added this task to the plans repository index.
- [x] Restored required secret-scanning capability by installing checksum-verified Gitleaks v8.30.1.
- [x] Scanned both repository history and the new archive; no leaks were found.

## Changed Files Outside This Archive

| File | Change |
|---|---|
| `~/.config/opencode/AGENTS.md` | Translation, factual corrections, workflow consistency, and safer test-data rules |
| `~/docs/network-access-china.md` | Corrected global instruction reference |
| `~/docs/repo-shapes-and-gitignore.md` | Corrected global instruction references |
| `~/docs/scalability-review-checklist.md` | Corrected global instruction references |
| `~/docs/ado-work-item-notes.md` | Corrected global instruction reference and credential path |
| `~/.azure-devops/credentials.jsonc` | Permission mode changed from `0644` to `0600`; contents unchanged and not archived |
| `~/.ssh/id_rsa` | Permission mode changed from `0644` to `0600` so Git could safely use the key |

## Verification

- OpenCode version: `v2.0.10`
- Docker Compose provider: `2.40.3`
- Backup SHA-256 verification: all files passed.
- Secret scan: Gitleaks v8.30.1 scanned all 164 repository commits and the complete new archive; no leaks were found.
- Performance gate: not triggered because the task is documentation/configuration guidance only.

## Notes

- The snapshot represents the corrected post-audit state, not the pre-audit state.
- Existing unrelated modifications in `~/plans` are intentionally excluded from this task's commit.
