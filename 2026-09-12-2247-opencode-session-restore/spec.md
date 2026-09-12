# opencode 历史 session 从 restic 快照恢复并合并进本机 db

- 日期:2026-09-12 22:47
- 环境:WSL2 Ubuntu 26.04 @ Win11 物理机 DESKTOP-J7NBNU4(还原/合并目标);数据来源为 Kubuntu 26.04 笔记本 desmond-yaoshi15proseriesgm5ix0a 的 restic 快照
- 状态:已完成,验证通过

## 1. 背景

2026-09-11 晚将笔记本 home 选择性恢复到本 WSL 时(见 [2026-09-11-2100-restic-azure-backup-wsl](../2026-09-11-2100-restic-azure-backup-wsl/)),只捞了 `~/learning` 等目录;`~/.local/share/opencode` 未恢复——本机 opencode.db 是 WSL 自己新建的,仅 25 个 session(全是 2026-09-12),笔记本 8 个月的历史 session(620 个)只存在于 restic 快照。

用户先要找回 Rust 学习 session;记错的 session ID(`ses_f94593b2…` 实为 LazyVim 课程)提示不能靠记忆定位,需在快照 db 内检索标题。

## 2. 恢复过程

1. **定位**:`wsl.exe -u root`(WSL 内免密 root)source `/root/restic-env` 后用 restic 操作仓库;`restic snapshots` 确认笔记本两个快照 `d860c693`(09-11 12:25)与 `00ae3b7e`(09-11 14:54,更新,最终采用)。
2. **取出 db**:`restic restore 00ae3b7e --target /tmp/oc-merge/raw --include '/home/desmond/.local/share/opencode/opencode.db*' --include '…/storage/**'`(db 1.1G + storage 89M;跳过 2G 的 `snapshot/` 文件快照对象——非 session 数据)。
3. **覆盖面核验**(合并前必做):
   - 笔记本 db:620 session / 18,615 message / 80,568 part / 173,496 event;与本机 25 个 session **零重叠**(session id 全局随机)
   - JSON 时代老 session(`storage/*.json`,2026-02 起)已全部迁移进笔记本 db(抽查 `ses_360c106c…` 在 db 中存在)→ 无需导入 JSON,`storage/` 弃用
   - 两边 `migration` 表 38/38 完全一致 → schema 同版本,可直插
4. **备份**:`sqlite3 backup API` 把本机 db 一致性快照(含 WAL)存 `~/Backups/opencode-db-backups/2026-09-12-premerge/opencode.db`(53M)。注意 `~/Backups` 属主是 root(hook 由 root 写),建子目录需 `wsl.exe -u root`。
5. **合并**:python sqlite3 `ATTACH` 笔记本 db,单事务对 `session/message/part/event/event_sequence/session_message/session_input/session_context_epoch/session_share/todo/project/project_directory` 逐表 `INSERT OR IGNORE`(主键去重);**不动** `migration/data_migration`(已一致)与 `account*/credential/permission`(本机认证状态)。
6. **验证**:`PRAGMA integrity_check` = ok;645 session,时间跨度 2026-02-05 → 2026-09-12;Rust 学习 session(`ses_f88d2b2a…`,80 parts)可查。

## 3. 结果

| 表 | before | merged | after |
|---|---|---|---|
| session | 25 | 620 | 645 |
| message | 1,258 | 18,615 | 19,873 |
| part | 5,068 | 80,568 | 85,636 |
| event | 18,660 | 173,496 | 192,156 |
| todo | 62 | 675 | 737 |
| project / project_directory | 2 / 1 | 20 / 12 | 22 / 13 |

opencode 重启 TUI 后 session 列表即可见全部历史;`opencode -s <id>` 可直接续接任意旧 session。

## 4. 经验教训

- **跨机合并 opencode db 的前置三查**:session id 零重叠、migration 集合一致、JSON 时代数据已在源 db 内(否则还要处理 `storage/` JSON)。
- **opencode 运行中合并安全**:WAL 模式下 `BEGIN IMMEDIATE` 单事务短锁即可,不干扰当前会话;合并行重启后才在 TUI 可见。
- **文件级 cp 不适合备份运行中的 WAL db**,用 sqlite backup API 才有一致性快照。
- **`/tmp` 是 tmpfs(RAM)**,1.1G db 中转没问题,但更大恢复目标应落盘并尽快清理。
- 恢复用 `--include` 精确过滤比 `snap:path` 前缀过滤可预测(后者有前缀剥平铺坑,见母任务 RUNBOOK §3b)。

## 5. 性能与容量

- 传输:restic 从 Azure East Asia 拉增量块,1.14G / 14s(局域缓存热);合并事务秒级,无性能债。
- 备份保留:`~/Backups/opencode-db-backups/2026-09-12-premerge/`(53M)在每日 restic 备份范围内,可回滚本次合并。
