# restic 备份 WSL 侧重建(同仓库)设计规格

- 日期:2026-09-11 21:00
- 环境:WSL2 Ubuntu 26.04(宿主 Windows 11 物理机 DESKTOP-J7NBNU4,mirrored networking)
- 状态:实施完成(当日回填)
- 目标机器:Windows 11 + WSL2 Ubuntu 26.04(`DESKTOP-J7NBNU4`,systemd 已启用)
- 母方案:`~/plans/2026-09-11-1012-restic-azure-backup/`(原实体机 yaoshi15pro 系列,2026-09-11 上午上线)

## 1. 背景与目标

原实体机当日已建立 restic → Azure Blob 备份;本 WSL 机从该仓库恢复了 home 等内容后,作为新的日常工作机,需要**同等能力**的每日自动备份。本任务 = 母方案向 WSL 环境的移植与适配,不重新设计。

## 2. 与母方案的差异(全部决策记录)

| # | 差异 | 决策与理由 |
|---|------|-----------|
| 1 | **同仓库 `azure:restic-desktop:/`**(用户确认) | 复用 SAS/密码/1Password 条目;host 自动区分两机快照;刚恢复的 45G 数据块已在仓库,首备几乎零上传(实测 4.5 分钟)。代价:两机的 `forget --keep-*` 按 host 分组各自应用,但 `prune` 是全局的——可接受(共享块本就该全局去重) |
| 2 | **`wsl.exe -u root` 替代 `sudo`** | WSL 内 sudo 需交互密码,自动化不可用;`wsl.exe -u root --` 免密取得 root,母方案的 root systemd timer 架构得以原样保留 |
| 3 | **include 裁剪**:`/home/desmond /etc /usr/local` | 母方案的 `/var/lib/tailscale`(不存在)与 `/var/spool/cron/crontabs`(空)剔除;出现后再加回 |
| 4 | **restic 0.18.0**(官方二进制,`~/.local/bin` → 复制到 `/usr/local/bin`) | root 的 PATH 不含用户 bin;系统路径与母方案单元文件一致 |
| 5 | **hook 微调**:`snap list` 加 `command -v` 保护 | WSL 有 snap 命令但输出提示性 stderr;防御性修正,其余 hook 原样 |
| 6 | **排除表原样复用** | 不存在的路径(Steam/windows-vm 等)在 exclude 里无害;防御层语义不变 |
| 7 | **凭据仅存 `/root`**(`restic-env` + `restic.pw`,600) | 与母方案一致;用户会话临时 export 的 4 个变量(灾后还原用)不落任何用户可读文件 |

### WSL 平台固有限制(知悉项)

- WSL 发行版无运行会话时整个 VM 停止,timer 不触发;`Persistent=true` 保证下次启动补跑错过的任务(已验证 systemd 支持)。
- 用户日常经 Windows Terminal 使用 WSL,timer 在会话期间正常触发;长期不开 WSL 则备份暂停——个人机可接受。

## 3. 落地清单

| 项 | 路径 | 来源 |
|---|------|------|
| restic | `/usr/local/bin/restic` 0.18.0 | 官方二进制(恢复任务时已装 `~/.local/bin`) |
| 凭据 | `/root/restic-env`、`/root/restic.pw` | 值 = 母方案同源(1Password),SAS 到期 2028-09-11T02:59Z |
| 排除表 | `/etc/restic/excludes.txt` | 母方案 `excludes.txt` 原样 |
| 钩子 | `/usr/local/bin/restic-pre-backup.sh` | 母方案 + snap 保护(本档案 `files/`) |
| 单元 | `/etc/systemd/system/restic-*.{service,timer}` ×5 | 母方案 + include 裁剪(本档案 `files/`) |
| 手动入口 | `/usr/local/bin/backup-now.sh` | 母方案原样(`sudo systemctl start`,交互终端可用) |
| 档案副本 | 本目录 `files/` | 实际安装版的证据链副本 |

## 4. 验收结果(2026-09-11 实测)

1. dry-run 精确断言:排除模式零命中;必含项(.ssh/.claude/.config/opencode/Repos/plans)全部在场;396,744 文件 / 45.129 GiB(宽匹配的 104 处"命中"均为文件名恰含关键词的普通文件,人工复核通过)
2. 首备快照 `7e05d536`(tag daily,45.478 GiB),4 分 36 秒(同仓库去重生效)
3. `restic stats --mode raw-data latest`:33.079 GiB / 压缩比 1.18x(与原机快照大量共享块)
4. `systemctl list-timers`:backup 明日 03:00 / maintenance 周日 04:00
5. `~/Backups/last-backup.txt` 末行 OK;manifests 741 行非空
6. 两机快照共存:yaoshi15pro×2 + DESKTOP-J7NBNU4×2(host 分组,互不误删)

## 5. 事故与教训(本次新增)

1. **陈旧锁**:前一日恢复任务中 shell 超时 kill 的 `restic restore` 在仓库留锁,首备 `forget` 阶段 exit 11。处理:`pgrep restic` 确认无进程 → `restic unlock`(移除 3 把锁)→ 重跑成功。教训:被中断的 restic 操作(restore/backup)之后,下一操作前检查锁。
2. **forget 作用于全部 host 分组**:service 里的 forget 不带 `--host`,会按组对仓库内**所有**机器的快照应用 14d/8w/6m——原机 4 个同日快照被精简为 2 个(策略语义内,无损)。若未来想完全隔离,需给 forget 加 `--host $(hostname)`;当前两机策略相同,不改。

## 6. 灾后恢复

RUNBOOK 沿用 `~/Repos/desmondc9-restic-azure-backup/RUNBOOK.md`;差异:还原时用 `--host DESKTOP-J7NBNU4` 选 WSL 侧快照(或默认 latest 时注意两机混存)。

## 7. 性能与容量

- 首备实测 45.478 GiB 原始 / 新增上传极小(去重);每日增量预计 <1G
- 存储成本:与原机共享仓库,总 33 GiB(raw-data, latest 计)级别,$1/月内
- 备份窗口 03:00,Nice=19 + idle I/O,对交互无感
