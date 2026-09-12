# 全量回填 spec 环境信息(58 个档案)

- 日期:2026-09-12 19:55
- 类型:档案库治理(无代码变更,无 PR)
- 状态:已完成——66/66 个 spec 均含环境信息

## 环境

- 操作方为 **WSL2 Ubuntu 26.04**(宿主 Windows 11 物理机 DESKTOP-J7NBNU4),被治理的档案库 `~/plans` 同时覆盖四类机器的历史任务

## 背景

2026-09-12 晚新增「spec 必须记录环境」约定后,存量 58 个档案缺环境信息。用户要求逐目录检查,缺失者按内容与 git log/时间线推断补上。

## 推断规则(判据可复用)

1. **时间线硬边界**:WSL2 机器 2026-09-11 才启用——之前的「本机」任务全部是 Kubuntu 笔记本(yaoshi15pro)
2. **关键词指纹**:Konsole/KDE/Plasma/kscreen/kdeglobals → Kubuntu 笔记本;`/mnt/c`/powershell.exe/DESKTOP-J7NBNU4 → WSL;C:\Windows/HKLM → Windows 11;Bandwagon/104.194.83.82 → VPS;qcow2/dockur → 笔记本上的 Win11 VM;redroid/SFA/OnePlus → Android
3. **双端任务**(tailnet 出口、frp、sunshine 串流)写明两端角色而不是只写操作方

## 环境清单(本次判定的标准串)

| 代号 | 环境串 | 档案数 |
|---|---|---|
| 笔记本 | Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro) | 39 |
| VPS | Bandwagon VPS(Ubuntu,ssh 远程) | 4(librechat×2、lazyvim-vps-replay、lazyvim-dap-setup、headscale-derp) |
| WSL | WSL2 Ubuntu 26.04(宿主 Win11 物理机 DESKTOP-J7NBNU4,mirrored networking) | 4 |
| Windows | Windows 11 物理机(DESKTOP-J7NBNU4) | 2(exit-node、sunshine-winnat,均经 WSL interop) |
| 双端/组合 | 笔记本+VPS、笔记本+VM、笔记本+redroid、Android 真机等 | 9 |

## 变更内容

- 51 个:头部 `- 日期` 行后插入 `- 环境:...`
- 5 个头部无日期行(英文 Date / 无元数据):标题/Date/Status 后插入
- 2 个已有异构环境信息(wine 的 `**Machine:**`、librechat 的 `**运行环境**`):补统一行,原信息保留
- 8 个已有 `## 环境`/`- 环境` 格式(均为 2026-09-12 当天新档案):不动
- `CLAUDE.md` 约定更新:格式放宽为「头部 `- 环境:` 行(推荐)或 ## 环境 章节」

## 验证

- [x] 全目录扫描:66/66 spec 含 `^- 环境` 或 `^## 环境`
- [x] 抽查 3 个(打印机/exit-node/token-redaction)插入位置与内容正确
- [x] 5 个特殊格式文件逐一人工确认插入点

## 遗留 / 跟进

- ~~6 个目录在 README 索引中缺行(2026-09-01-1537-cursor-sdk2api-shutdown、2026-09-01-1547-vscode-kwallet-keyring、2026-09-03-0953-coding-agents-auto-update、2026-09-03-1025-github-token-multi-tool、2026-09-07-1141-librechat-openclaw、2026-09-07-1329-librechat-websearch)~~(同日已按时间序补入 README,覆盖率校验 66/66 通过)
