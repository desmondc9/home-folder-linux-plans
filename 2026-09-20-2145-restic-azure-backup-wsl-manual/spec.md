# restic 备份 yaoshi15pro WSL(同仓库,纯手动)设计规格

- 日期:2026-09-20 21:45
- 环境:WSL2 Ubuntu 26.04.1(宿主 yaoshi15pro 笔记本,Windows 11,systemd 已启用),`/` 1007G 已用 30G,home 26G
- 状态:实施完成(当日回填,见 §4;首备由用户手动执行)
- 母方案:`~/plans/2026-09-11-1012-restic-azure-backup/`(原 Kubuntu 实体机,2026-09-11 上线);姊妹移植:`~/plans/2026-09-11-2100-restic-azure-backup-wsl/`(DESKTOP-J7NBNU4)

## 1. 背景与目标

笔记本现以 Windows 11 + WSL2 Ubuntu 为日常工作机,需要与母方案**同等能力**的 restic → Azure Blob 备份,复用同一仓库与凭据。与母方案最大的差异由用户明确:**不定时运行,仅手动触发**。本任务 = 母方案向本机的移植与适配,不重新设计。

## 2. 与母方案的差异(全部决策记录)

| # | 差异 | 决策与理由 |
|---|------|-----------|
| 1 | **同仓库 `azure:restic-desktop:/`** | 凭据由用户提供(`~/.restic/credentials.jsonc` 中转,值 = 1Password 同源),SAS 到期 2028-09-11T02:59Z;第三节点继续共享全局去重 |
| 2 | **不装 timer** | 用户要求手动。保留 3 个 oneshit service(**不 enable**),`backup-now.sh` = `wsl.exe -u root -- systemctl start`(WSL 免密取 root,母 WSL 方案先例;sudo 兜底)——与母方案 backup-now 同代码路径,保留 journald 日志、OnFailure 标记、`Nice=19`/idle I/O |
| 3 | include = `/home/desmond /etc /usr/local` | `/var/lib/tailscale` 与 `/var/spool/cron/crontabs` 不存在,出现后再加回(母 WSL 方案同款裁剪) |
| 4 | excludes 新增 `/home/desmond/.restic` | 凭据中转文件(含 SAS + 仓库密码)不进备份树;运行位在 `/root`(天然不在 include),灾备位在 1Password |
| 5 | restic **官方二进制** v0.19.1 | apt 26.04 构建无 azure 后端(母方案教训,本机同版本发行版,直接跳过 apt) |
| 6 | host = `yaoshi15pro`(默认 hostname) | 仓库既有 host 无冲突(连通性验证见 §4);不设 `--host` 覆盖 |
| 7 | forget 仍不带 `--host` | restic forget 默认按 host 分组各自应用 14d/8w/6m;三机策略一致,共享块全局 prune 本就该如此 |
| 8 | 不重建 `~/Repos/desmondc9-restic-azure-backup` | 该仓无 remote(母机本地仓);证据链副本入本目录 `files/`(母 WSL 方案先例) |

## 3. 落地清单

| 项 | 路径 | 来源 |
|---|------|------|
| restic | `/usr/local/bin/restic` 0.19.1 | 官方二进制(GitHub 直连) |
| 凭据 | `/root/restic-env`、`/root/restic.pw`(600) | 值 = `~/.restic/credentials.jsonc`;安装后临时件即删 |
| 排除表 | `/etc/restic/excludes.txt` | 母 WSL 方案版原样 + `~/.restic` 行 |
| 钩子 | `/usr/local/bin/restic-pre-backup.sh` | 母 WSL 方案版原样(snap 保护) |
| 单元 | `/etc/systemd/system/restic-{backup,maintenance,backup-failed}.service` ×3(无 timer、不 enable) | 母 WSL 方案版,仅改 Description |
| 手动入口 | `/usr/local/bin/backup-now.sh` | `wsl.exe -u root` 启动 service,sudo 兜底 |
| 档案副本 | 本目录 `files/` | 实际安装版(凭据除外) |

## 4. 验收结果(2026-09-20 实测回填)

1. 安装:`systemd-analyze verify` 3 个 service 通过;`systemctl is-enabled restic-*.timer` = not-found(无 timer,正确);`/root/restic-env`、`/root/restic.pw` 均 `-rw------- root root`;`/tmp` 凭据临时件已删
2. 连通性:`restic snapshots` 可见 12 个既有快照,host 分组 = `desmond-yaoshi15proseriesgm5ix0a`(原 Kubuntu 实体机 ×2)+ `DESKTOP-J7NBNU4`(桌面 WSL ×10,其 timer 仍在每日跑)——与本机 `yaoshi15pro` 无冲突;仓库 raw-data 75.421 GiB / 压缩比 1.36x
3. 钩子试跑:`~/Backups/manifests/` 共 740 行非空、属主 desmond(snap-list 空行 = 本机无 snap,`command -v` 守护分支正常;打捞到 `.sdkman/etc/config`)
4. dry-run:176,447 文件 / 7.686 GiB 原始 / **would-add 仅 1.236 GiB(580.5 MiB stored)** / 23 秒——与仓库既有块大量去重(home 数据系从仓库迁移而来);精确断言(顶层工具链/凭据目录)全部 0 命中;宽匹配 7 处人工复核均按设计在内(nvim 插件源码树自带 `.cargo/config.toml` ×4、钩子打捞件路径含 `.sdkman` ×3);必含项 `.ssh`/`plans`/`Repos`/`.config/opencode`/`.zshrc`/`.git/config`/`/etc/systemd`/`/usr/local/bin/restic` 全部在场
5. 首备:用户选择自行执行 `backup-now.sh`;完成后留档:`wsl.exe -u root -- bash -c 'source /root/restic-env && restic snapshots --host yaoshi15pro && restic stats --mode raw-data latest'`

## 5. 手动运行与维护(本机日常)

```bash
backup-now.sh                                        # 备份(等价 sudo systemctl start --no-block restic-backup.service)
journalctl -u restic-backup.service -f               # 看进度
cat ~/Backups/last-backup.txt                        # OK/FAIL 状态(末行)
wsl.exe -u root -- systemctl start restic-maintenance.service   # 维护:prune + check 1/10(建议每月一次)
wsl.exe -u root -- bash -c 'source /root/restic-env && restic unlock'   # 卡死锁清理(先 pgrep restic 确认无进程)
```

SAS 续签(2028-08 前):`az login` 后按母方案 `docs/recovery.md` 重签容器级 racwdl SAS(2 年),更新 `/root/restic-env` 与 1Password 条目。

## 6. 灾后恢复(简版;完整语义 = 母方案 RUNBOOK 的教训集)

1. 新机装 restic 官方二进制;从 1Password 取:账号名 `desmondlinbak26`、SAS、仓库密码
2. 导出 4 个环境变量(同 §5 unlock 命令的形状,`RESTIC_PASSWORD_FILE` 指向密码文件)
3. **必须带 `--host yaoshi15pro`** 选本机快照(仓库三机混存,`latest` 不可盲用)
4. `restic restore <id> --target /`;后处理 `chown -R desmond:desmond /home/desmond`、SSH 权限回填
5. 子目录还原:`--target` 直接写最终目录本身(restic 会剥掉过滤前缀,母 WSL 方案 2026-09-12 踩坑)

## 7. 性能与容量

- 基线:本机 `du`/`df` 实测(2026-09-20):home 26G(Repos 19G、工具链 .rustup/.sdkman/.m2/.nvm ≈ 2.7G、.cache/.npm/.vscode-server ≈ 1.2G——后两类均在排除表)
- 预估:排除后原始 ~10-20G;与仓库既有块(两机历史)去重后首备上传更少;存储增量 < $0.5/月(East Asia Hot LRS ≈ $0.0184/GB/月)
- 硬限制:Azure Block Blob 单块 ≤4000MiB,远超需求;手动运行无窗口冲突,`Nice=19` + idle I/O 不碍交互
- 性能债:无(排除表就是为此设计的)
