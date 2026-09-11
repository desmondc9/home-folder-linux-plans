# restic WSL 侧备份 实施记录

> 单阶段任务(母方案复用为主),无独立 implementation 计划文件,本文件即实施记录。

## 任务清单

- [x] 勘察:systemd 已启用 / `wsl.exe -u root` 免密可用 / az 未装 / tailscale 与 crontabs 不存在
- [x] restic 0.18.0 → `/usr/local/bin`(755)
- [x] `/root/restic-env` + `/root/restic.pw`(600,值经 `/tmp` 中转 install,临时件即删)
- [x] `/etc/restic/excludes.txt`(母方案原样)
- [x] `/usr/local/bin/restic-pre-backup.sh`(snap 保护)
- [x] 5 个 systemd 单元(`files/` 存档),include = `/home/desmond /etc /usr/local`
- [x] `systemd-analyze verify` 通过;双 timer enable(backup 明日 03:00 / maintenance 周日 04:00)
- [x] dry-run 双断言通过(396,744 文件 / 45.129 GiB;宽匹配 104 处人工复核 = 文件名撞词,精确断言全 0)
- [x] hook 试跑:manifests 741 行,属主 desmond
- [x] 首备:快照 `7e05d536` 45.478 GiB / 4m36s;`last-backup.txt` OK;stats 33.079 GiB / 1.18x
- [x] spec.md 回填(验收结果 + 事故教训)

## 首备事故时间线

1. 21:03 `systemctl start`:backup 成功(快照 `83415101`)→ forget 阶段 exit 11(仓库陈旧锁,系 20:13 被超时 kill 的 `restic restore` 所留)→ OnFailure 记 FAIL
2. `pgrep restic` 确认无进程 → `restic unlock`(3 把)→ 重跑
3. 21:06-21:11 快照 `7e05d536` + forget 完成,记 OK(两个同日快照,保留策略内)

## 用户手动动作(提醒)

- 1Password 条目「restic desmondlinbak26」无需变更(同仓库同凭据);如尚未做纸质件,补打
