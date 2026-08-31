# 内核升级 7.0.0-30 后正常模式启动失败 —  binderfs 挂载竞态

## 背景

2026-08-21 安装 Ubuntu 内核更新（7.0.0-29 → 7.0.0-30）后，正常模式连续多次启动失败，
只能通过 recovery 模式进入系统。

## 根因分析

失败启动的 journal(`journalctl -b -2/-1`）关键日志：

```
mount: /dev/binderfs: unknown filesystem type 'binder'
dev-binderfs.mount: Failed with result 'exit-code'.
Dependency failed for local-fs.target - Local File Systems.
local-fs.target: Triggering OnFailure= dependencies.
```

- `/etc/fstab` 中有一行（redroid/waydroid 时期添加）:
  `binder /dev/binderfs binder defaults 0 0`
- 该 fstab 挂载由 systemd-fstab-generator 生成 `dev-binderfs.mount`，属于 `local-fs.target` 的**硬依赖**（无 `nofail`)。
- `binder_linux` 模块由 `/etc/modules-load.d/binder.conf`（及 waydroid.conf）经
  `systemd-modules-load.service` 加载，但 mount 单元**没有对它的排序依赖**，两者并行执行 → 竞态。
- 挂载先跑时 binder 文件系统类型尚未注册 → 挂载失败 → `local-fs.target` 失败 →
  OnFailure 触发 emergency 模式 → 表现为"正常模式启动失败"。
- 竞态在旧内核上一直潜伏存在，7.0.0-30 改变了启动时序才暴露。recovery 模式跳过该依赖，故能进系统。
- 排除项：NVIDIA 595.84 内核模块在新内核上加载正常（`nvidia-drm` 初始化成功），非显卡问题。

## 修复方案

fstab 的 binder 行改为：

```
binder /dev/binderfs binder nofail,x-systemd.after=systemd-modules-load.service 0 0
```

- `x-systemd.after=systemd-modules-load.service`：消除竞态本身，挂载排在模块加载之后。
- `nofail`：双保险——即使未来某内核移除 binder 支持或模块加载失败，也只降级为
  redroid/waydroid 不可用，绝不再阻塞系统启动。

## 验证

- `systemctl show dev-binderfs.mount` 确认：
  - `After=` 包含 `systemd-modules-load.service`
  - 依赖关系从 `RequiredBy=local-fs.target` 降为 `WantedBy=local-fs.target`
- 重启后正常模式一次进入 Kubuntu（用户确认）。
- 回滚方案：`sudo cp /etc/fstab.bak-20260821 /etc/fstab && sudo systemctl daemon-reload`
