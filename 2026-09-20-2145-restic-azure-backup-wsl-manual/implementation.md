# restic yaoshi15pro WSL(手动)实施记录

> 单阶段任务(母方案复用为主),无独立 implementation 计划文件,本文件即实施记录。

## 任务清单

- [x] 勘察:WSL2 Ubuntu 26.04.1 / systemd 已启用 / restic 未装 / az 2.90.0 在 / tailscale 与 crontabs 不存在 / home 26G / sudo 需密码(→ root 操作走 `wsl.exe -u root`)
- [x] plans 目录 `2026-09-20-2145-restic-azure-backup-wsl-manual/` + spec.md
- [x] restic 官方二进制 0.19.1(GitHub 直连)→ `/usr/local/bin/restic`(apt 26.04 构建无 azure 后端,母方案教训,未走 apt)
- [x] `/root/restic-env` + `/root/restic.pw`(600,值取自 `~/.restic/credentials.jsonc`,经 /tmp 中转 install 后临时件即删)
- [x] `/etc/restic/excludes.txt` = 母 WSL 方案版 + `/home/desmond/.restic`(凭据中转文件不进备份树)
- [x] `/usr/local/bin/restic-pre-backup.sh`(母 WSL 方案版原样,snap 守护)
- [x] 3 个 oneshit service(backup / maintenance / backup-failed)**无 timer、不 enable**;`systemd-analyze verify` 通过;`is-enabled restic-*.timer` = not-found
- [x] `/usr/local/bin/backup-now.sh`(`wsl.exe -u root -- systemctl start --no-block restic-backup.service`,sudo 兜底)
- [x] 连通性 + host 冲突检查:仓库既有 host `desmond-yaoshi15proseriesgm5ix0a` ×2、`DESKTOP-J7NBNU4` ×10(桌面机 timer 仍活着),本机 `yaoshi15pro` 无冲突
- [x] 钩子试跑:manifests 740 行、属主 desmond;打捞 `.sdkman/etc/config`
- [x] dry-run 双断言:精确断言(顶层工具链/凭据目录)全 0;宽匹配 7 处人工复核 = 按设计在内(nvim 插件源码 `.cargo` ×4 + 钩子打捞件路径含 `.sdkman` ×3);必含项全在场
- [x] spec.md 回填(验收结果);`files/` 证据链副本(凭据除外)
- [ ] 首备:用户自行执行 `backup-now.sh`(选择不代跑);结果可按 spec §4.5 留档

## 关键实现点(复用的教训)

1. apt restic 无 azure 后端 → 官方二进制直装 `/usr/local/bin`
2. systemd `EnvironmentFile=` 不解析 `export` 行 → 单元用 `bash -c 'source /root/restic-env && exec …'` 模式
3. systemd 服务无 `HOME` → `Environment=HOME=/root`
4. root 操作不经 sudo(本机 sudo 需密码且 agent 非交互)→ `wsl.exe -u root -- bash <脚本>`(母 WSL 方案先例);复杂命令一律写脚本文件再执行,避免经 Windows 命令行二次编组损坏引号
5. 凭据只落 `/root`(不在 include 路径);`~/.restic/credentials.jsonc` 留在原处但已被排除表挡在备份树外

## 与母 WSL 方案(DESKTOP-J7NBNU4)的差异汇总

| 项 | 母 WSL 方案 | 本机 |
|---|---|---|
| 调度 | 双 timer(每日 03:00 / 周日 04:00) | **无 timer,纯手动**(用户要求) |
| 单元 | 5 个(含 2 timer) | 3 个(service ×3,不 enable) |
| 手动入口 | `sudo systemctl start` | `wsl.exe -u root` 优先,sudo 兜底 |
| 排除表 | 原样 | + `/home/desmond/.restic` |
| 其余 | — | 凭据/钩子/forget 策略/service 内容原样复用 |

## 用户手动动作(提醒)

- 首备:`backup-now.sh`,进度 `journalctl -u restic-backup.service -f`
- 维护(建议每月):`wsl.exe -u root -- systemctl start restic-maintenance.service`(prune + check 1/10)
- 1Password 条目「restic desmondlinbak26」无需变更(同仓库同凭据);`~/.restic/credentials.jsonc` 是否保留由用户自定(已排除在备份外)
- SAS 到期 2028-09-11T02:59Z,续签见 spec §5
