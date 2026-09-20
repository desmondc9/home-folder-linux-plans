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
- [x] 首备(用户手动触发,22:07):`5b66ae4c` 落库(46 秒,实存 2.792 GiB / 1.78x);forget exit 11(桌面机 181h 前的陈旧锁)→ unlock → 重跑 `2cade3bb` + forget 完成,`last-backup.txt` OK 22:09:02(详见 spec §4.5)

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

## 首备事故时间线(2026-09-20 22:07,与母 WSL 方案 09-11 事故同型)

1. 22:07 用户 `backup-now.sh`:backup 阶段成功(`5b66ae4c`,46 秒)→ forget 阶段 exit 11,报仓库被 PID 3145@DESKTOP-J7NBNU4 锁定,锁龄 181h(2026-09-13 08:59:11 所留)→ OnFailure 记 FAIL
2. `pgrep -x restic` 确认本机无活进程 → `restic unlock`(removed 1)→ 重跑 service
3. 22:08:38 快照 `2cade3bb` + forget 完整跑完,`last-backup.txt` 记 OK(22:09:02);同日双快照保留策略内
4. 根因在桌面机(锁创建时刻与其 WSL 关机挂起事件吻合):其 backup 非排它锁不受阻,forget 排它锁大概率日日失败 → 待办见 spec §4.5 观察段

### 本次新增教训

1. **跨机陈旧锁会隔空打新节点**:共享仓库的第三台机首备即被另一机的陈旧锁打出 exit 11;共享仓库环境下 forget/prune 失败先 `restic snapshots --json` 看锁归属再 unlock
2. **监视脚本等待循环的竞态**:`systemctl start --no-block` 后服务仍处 failed 态的一瞬,`is-active --quiet` 返回非零使循环立即假退出——等待循环首检前应 sleep 几秒(或对 activating 也计为在跑)

## 用户手动动作(提醒)

- 首备:`backup-now.sh`,进度 `journalctl -u restic-backup.service -f`
- 维护(建议每月):`wsl.exe -u root -- systemctl start restic-maintenance.service`(prune + check 1/10)
- 1Password 条目「restic desmondlinbak26」无需变更(同仓库同凭据);`~/.restic/credentials.jsonc` 是否保留由用户自定(已排除在备份外)
- SAS 到期 2028-09-11T02:59Z,续签见 spec §5
