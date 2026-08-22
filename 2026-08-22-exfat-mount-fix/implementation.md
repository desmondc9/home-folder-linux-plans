# implementation — exFAT U 盘挂载失败修复

对应 [design.md](./design.md)。

## 任务清单

- [x] 诊断:定位根因为 `/proc/sys/kernel/modprobe` 为空致模块按需加载失效(证据链见 design.md)
- [x] 即时修复:`sudo modprobe exfat` —— 用户实测挂载成功
- [x] 持久化:新建 `/etc/modules-load.d/exfat.conf`(内容 `exfat`)
- [x] 运行时恢复:`sudo sysctl -w kernel.modprobe=/sbin/modprobe`
- [x] 归档:本目录 design.md + implementation.md 提交至 ~/plans 仓库

## 变更文件表

| 文件 | 变更 | 说明 |
|------|------|------|
| `/etc/modules-load.d/exfat.conf` | 新建 | 开机预加载 exfat,绕过被清空的 request_module helper |
| (无其他文件变更) | — | 分区表未做任何修改 |

## 验证方式

- [x] 用户实测:modprobe 后重新挂载 U 盘成功(2026-08-22 23:00 前确认)
- [x] `cat /etc/modules-load.d/exfat.conf` 输出 `exfat`
- [x] `cat /proc/sys/kernel/modprobe` 输出 `/sbin/modprobe`
- [x] `lsmod` 中 exfat 已加载(122880, refcount=1 为已挂载的盘),`/proc/filesystems` 已注册
- [ ] 下次开机直接插 exFAT U 盘验证(持久化验收,留待下次开机)

## 备注(可迁移经验)

- **"Filesystem type X not configured in kernel" ≠ 模块缺失**:先查 `/proc/sys/kernel/modprobe` 是否为空(`cat -A` / `od -c` 看真实字节,别被空行骗了),再查模块文件与 modules.dep。模块存在但该值为空时,症状与模块缺失完全一致。
- `kernel.modprobe` 是**非命名空间化**全局 sysctl,容器运行时对它写入会泄漏宿主;但不要默认甩锅——本次 crun/conmon 均经源码验证排除,写入者可能永远找不到。
- 修复别依赖找到写入者:modules-load.d 预加载走 systemd 直调 modprobe 的路径,与 request_module 机制解耦。
- sysctl 写入不留日志;想抓现行用 `auditctl -w /proc/sys/kernel/modprobe -p wa`。
- 用户遇到挂载失败时会去开分区管理器自查——注意其"删除+重建分区"操作只是**排队**,点 Apply 才生效;排查期间要提醒取消。
