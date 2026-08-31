# exFAT U 盘挂载失败 "Filesystem type exfat not configured in kernel"

日期: 2026-08-22
状态: 已修复——即时修复与持久化配置均已验证;最终验收(下次开机直接挂载)待下次开机确认

## 背景

插入 SanDisk 57.3 GiB U 盘(/dev/sda1, exFAT)后,Plasma 提示:

> An error occurred while accessing '57.3 GiB Removable Media', the system responded:
> The requested operation has failed: Error mounting /dev/sda1 at /run/media/desmond/401B-7213:
> Filesystem type exfat not configured in kernel.

## 根因(证据链)

挂载失败 ≠ 盘坏、≠ 模块缺失。**内核按需自动加载模块的机制失效**:

1. `/proc/sys/kernel/modprobe` 为**空**(正常应为 `/sbin/modprobe`;`od -c` 确认只有换行字节)。
2. mount(2) 找不到 fs-exfat → request_module("fs-exfat") → helper 路径为空、无程序可调 → 静默失败 → ENODEV → util-linux 报 "not configured in kernel"。
3. exfat 模块本身完好:`/lib/modules/7.0.0-30-generic/kernel/fs/exfat/exfat.ko.zst`,在 modules.dep 中且无依赖,`modprobe --dry-run` 解析正常;exfatprogs 1.3.2 已装。
4. `sudo modprobe exfat` 后挂载立即成功 → 因果链闭环(用户实测)。

### 排除表

| 嫌疑 | 结论 | 证据 |
|------|------|------|
| exfat 模块缺失 | ❌ | 模块存在、可解析、手动加载成功 |
| 内核构建配置错误 | ❌ | `/boot/config-7.0.0-30-generic` 中 `CONFIG_MODPROBE_PATH="/sbin/modprobe"` 正确 |
| 盘/分区损坏 | ❌ | `lsblk` 显示 sda1 exfat 完好;内核 15:02:06 正常识别 |
| crun 清空 | ❌ | 下载 crun 1.21 源码 grep + GitHub code search 全仓库:无 kernel.modprobe 写入 |
| conmon 清空 | ❌ | GitHub code search `repo:containers/conmon`:无(仅 CI hack 文件里调 modprobe 命令) |
| docker/runc 清空 | ❌ | `/usr/bin/docker` 是 podman shim;dockerd/containerd 未运行;runc 未安装 |
| GRUB cmdline / sysctl.d / udev rules / 用户脚本 / shell history | ❌ | `/proc/cmdline`、`/etc/sysctl.d`、`/usr/lib/sysctl.d`、`/etc/udev`、`~/.local/bin`、`/etc/sing-box`、`/etc/systemd`、bash/zsh history 全部干净 |

**写入者未找到**:sysctl 写入不留任何日志,无法追溯。`kernel.modprobe` 是非命名空间化的全局 sysctl,容器运行时对它的写入会泄漏到宿主;本机两个 OCI 运行时相关组件(crun、conmon)已被源码级排除,最可能是容器栈其他环节或一次已失传的交互命令。内核每次开机都从 CONFIG 初始化为正确值,所以空值是**本次开机后**(08:53 之后)运行时被写入的。**修复方案设计为不依赖找到写入者**。

### 时间线

| 时间 | 事件 | 证据 |
|------|------|------|
| 08:53:47 | 开机,systemd-modules-load 正常(直接调 modprobe,不走被清空的 helper) | journal `modprobe@efi_pstore.service` |
| 12:57 | redroid 容器启动(rootful podman + crun,compose `privileged: true`) | root 属主 conmon 进程起始时间 |
| 15:02:06 | U 盘插入,内核正常识别 `sda: sda1` | journal kernel 消息 |
| 15:02:26 | KDE 分区管理器被打开(用户试图自查) | journal `org.kde.kpmcore.helperinterface` |
| 15:02:54 | 分区管理器排队"删除 /dev/sda1 + 重建 exfat 分区"操作 | journal "Add operation: Delete partition…" |
| 15:10+ | Claude 定位根因;`modprobe exfat` 后挂载成功 | 本档案 |

## 解决方案

- **即时**(已验证):`sudo modprobe exfat`。
- **持久化**:`/etc/modules-load.d/exfat.conf`(内容 `exfat`)——开机由 systemd-modules-load **直接**调 modprobe 加载,不走 request_module,对该 sysctl 状态免疫。以后每次开机插 exFAT 盘都可直接挂载。
- **运行时恢复**:`sudo sysctl -w kernel.modprobe=/sbin/modprobe`——恢复其他模块的按需加载,直到再次被清空(若元凶再次运行会复发;exfat 有上一条兜底)。
- **明确不做**:不动分区表。分区管理器排队中的"删除 sda1 + 重建"操作**未应用、必须取消**——盘无任何问题,那是误操作。

## 验收标准

- [x] `sudo modprobe exfat` 后 U 盘挂载成功(用户实测)
- [x] `/etc/modules-load.d/exfat.conf` 存在且内容为 `exfat`(cat 验证)
- [x] `sysctl -w` 后 `cat /proc/sys/kernel/modprobe` 输出 `/sbin/modprobe`
- [x] exfat 模块已加载并注册进 `/proc/filesystems`(`lsmod` + grep 验证)
- [ ] 下次开机直接插入 exFAT U 盘可挂载(留待下次开机验证)

## 风险与缓解

- **写入者复发**:若元凶是 redroid 容器启动流程,每次重启容器可能再次清空 sysctl → exfat 有 modules-load.d 兜底不受影响;其他文件系统模块(如 ntfs3)如需按需加载仍会受影响 → 届时同样加 modules-load.d 条目,或用 `auditctl -w /proc/sys/kernel/modprobe` 抓现行。
- **分区管理器挂起操作**:点 Apply 会删盘丢数据 → 已告知取消;若已误应用,立即停止写盘并做数据恢复。

## 参考

- 关联档案:[kernel-7.0.0-30-boot-binderfs-race](../2026-08-21-0917-kernel-7.0.0-30-boot-binderfs-race/)(同涉 systemd-modules-load 的开机环节)
- redroid 容器:`~/redroid/compose.yml`(privileged: true, rootful podman)
