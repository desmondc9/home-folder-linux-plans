# opencode 历史 session(v1→v2 schema 断代)+ cursor-agent 会话 + 4 项 MCP 从 restic 快照恢复

- 日期:2026-09-20 22:15
- 环境:WSL2 Ubuntu 26.04 @ yaoshi15pro(目标);数据来源 = 桌面机快照 `8b56d354`(DESKTOP-J7NBNU4,2026-09-19 08:01,内容 = 笔记本 8 个月 + 桌面机一周的**全量超集**)
- 状态:数据已就位;opencode v1→v2 迁移待服务重启自动触发(见 §5 待办)

## 1. 背景与关键发现(opencode v1/v2 schema 断代)

本机 opencode 为 **v2.0.10**(47 migrations,`session_v2` + `instruction_*` 事件溯源新 schema);桌面机快照 db 停在 **38 migrations**(v1 经典 schema:`session`/`message`/`part`)。v2 线 9/12 起步(v2.0.3),v2.0.4+(9/16-19)引入 schema 重构——**v2 对 v1 表"保留但不可见"**:`session list` 返回 `[]`、`session export` 报 not found。

解法在源码 `packages/core/src/database/v1-migration.bun.ts`:server 启动层挂载 `V1Migration.layer`(`routes.ts:186`),自动把主库 v1 表转换为 `session_v2`/`session_message`(逐 session 事务,kv 键 `migration.v1-v2` 记进度/完成态)。触发条件:存在 v1 `session` 表 且 kv 无完成标记。API 只有 `migration.v1.status`,无手动 run。

先例 [2026-09-12-2247-opencode-session-restore](../2026-09-12-2247-opencode-session-restore/) 的直插 12 表方案因 schema 断代不可用。

## 2. 恢复过程

1. **抽取**:restic restore → /tmp 暂存(db 1.64G + wal 1.14G + shm,共 2.587 GiB / 20s);`opencode.jsonc` 同批取出
2. **沙箱端到端验证**(HOME=/tmp/oc-sbx,不碰真库):v2.0.10 打开旧库自动补齐 schema 39-47 → `(sleep 900 | opencode acp)` 维持 server 存活触发 V1Migration → **~10 秒完成**:840/840 v1 session 全量进 `session_v2`(此前 32 条 v2 行是双写过渡期同 id 会话,`INSERT OR IGNORE` 天然合并,零丢失);integrity ok;2247 的 Rust 学习 session(`ses_f88d2b2a…`)标题 + 62 messages 俱在;CLI `session list` 正常出列表
3. **真库备份**:sqlite backup API → `~/Backups/opencode-db-backups/2026-09-20-premerge-v2/opencode.db`(12.8M;~/Backups 属主 root,root 建子目录后 chown)
4. **真库合并**(desmond 直连,WAL 不扰运行中会话):按沙箱 DDL 建缺失的 v1 表(session/message/part/todo + 索引)→ ATTACH + INSERT OR IGNORE:`session 840 / message 29,616 / part 125,410 / todo 885 / project 25 / project_directory 16`,1.1s,integrity ok,project 引用孤儿 0,kv 无 `migration.v1-v2`(保持待迁移态)。**不合并** event/event_sequence/session_message/session_v2/kv——本机 v2 数据原样,由迁移器生成
5. **MCP 配置**:`opencode.jsonc`(快照 9/17 版,本机原无此文件)整文件恢复到 `~/.config/opencode/`(chmod 600,含 API key),4 个 MCP:`zai-mcp-server`(local,npx)、`web-search-prime`、`web-reader`、`zread`(remote,z.ai);JSONC 解析校验通过,**当前会话已热加载 4 个 MCP 工具**
6. **cursor-agent 会话**:union 恢复(`--overwrite never` + 精确 `--include`,2310 模式):`projects`(1426 文件,**194 个 agent transcript**,107M)、`chats`(283 文件,1.4G)、`acp-sessions`(18)、`ai-tracking`、`agents`、`agent-cli-state.json`、`unified_repo_list.json`——共 2235 files/dirs / 1.539 GiB / 12s,root 落盘后 chown;`plugins`/`extensions`(可重装)跳过

## 3. 验收

| 项 | 结果 |
|---|---|
| 沙箱 E2E | ✅ 迁移 840/840、integrity ok、list 可见、Rust session 抽查通过 |
| 真库合并 | ✅ 840/29,616/125,410/885 入库,孤儿 0,kv 待迁移态 |
| MCP | ✅ 4 项恢复,本会话热加载可见 |
| cursor-agent | ✅ 194 transcripts @ 24 项目目录;`cursor-agent ls/--resume` 可用(CLI 2026.09.18) |
| 真库迁移触发 | ⏳ 待 `opencode service restart`(见 §5)|

## 4. 教训

1. **opencode v1/v2 断代**:跨大版本恢复 session,先对齐 migration 清单;v2 恢复 v1 数据的正道 = 把 v1 表原样放进主库 + 重启服务让官方 `V1Migration` 转换,不要自己写 v2 行(schema 未公开稳定)
2. **CLI `--standalone` 秒退不触发后台迁移**(fork 层随进程死);沙箱触发用 `(sleep N | opencode acp)` 维持 server
3. V1Migration 会**清空 `event` 表**(v2 设计:session_message 是投影,可重建;本机既有 v2 session 不受损)
4. 双写过渡期 session 同 id 双表并存是正常现象,INSERT OR IGNORE 语义正好
5. restic 0.19 `restic ls` 默认输出**纯路径**(无 size/时间列),别按旧格式 awk
6. zsh 里 `wsl.exe … /tmp/x-*` 无匹配时 nomatch 中止整条命令(连 wsl.exe 都不执行)——通配交给对端 bash
7. 恢复的登录态可能要求重新登录(机器指纹),属预期(2310 先例)

## 5. 待办(用户操作)

- **重启 opencode(关掉重开,或 `opencode service restart`)**:首次启动自动跑 V1Migration(沙箱实测 840 个约 10 秒),之后 `opencode session list` 应见 843 个(840 历史 + 本机 3)
- 回滚(如需):`~/Backups/opencode-db-backups/2026-09-20-premerge-v2/opencode.db` 覆盖回 `~/.local/share/opencode/opencode.db`(服务停止状态下)

## 6. 性能与容量

- 传输:抽取 2.587 GiB/20s + cursor 1.539 GiB/12s(Azure East Asia → 本机);合并 1.1s
- 落盘:~/.cursor 1.6G、db 增长 ~1.6G(v1 表入库,迁移后 v2 侧再增 ~与其相当);均随每日 restic 备份带走
- 无性能债:一次性操作,v1 表保留为迁移器幂等依据(不删)
