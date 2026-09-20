# Backup Manifest

- Created: `2026-09-20T15:46:41+08:00`
- Snapshot type: post-audit corrected state
- Secret handling: ADO credential contents were not copied.
- Credential metadata verified: `~/.azure-devops/credentials.jsonc`, mode `600`.

| Source | Backup file | Bytes | SHA-256 |
|---|---|---:|---|
| `/home/desmond/.config/opencode/AGENTS.md` | `AGENTS.md` | 39529 | `6f29d192e7131fb5f295c09b1f4bbdc064e807d2c8de8ea03df480adab35e942` |
| `/home/desmond/docs/network-access-china.md` | `network-access-china.md` | 4588 | `e3b47d5aedaf1e5ceb43525fc58079ba3743a223c79697ebc64da638e8c142ba` |
| `/home/desmond/docs/repo-shapes-and-gitignore.md` | `repo-shapes-and-gitignore.md` | 9433 | `ca66b99b90726e839cd85bb53825fa60a12ee4cc27b8794c7ab1b72b2a6bb9f5` |
| `/home/desmond/docs/scalability-review-checklist.md` | `scalability-review-checklist.md` | 37650 | `d5689c35b441357d9c726f99cf9da85fd5f843b3fd97966d44decdd1ebcd08c6` |
| `/home/desmond/docs/ado-work-item-notes.md` | `ado-work-item-notes.md` | 3552 | `d068f59a44bfeb458aea3fec3aedb3b33bfd5390311a7f00346b886d728c87f4` |

## Restore

Review the desired backup file before restoring it. Copy only that file back to its source path, then start a new OpenCode session if the restored `AGENTS.md` must apply from a clean context.
