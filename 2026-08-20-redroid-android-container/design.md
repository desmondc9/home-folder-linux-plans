# redroid Android 容器 (droidvm) — 设计

## 背景与目标

在 Kubuntu 26.04 (KDE Plasma + Wayland) 上配置一个高性能、可持久化的 Android 容器,类似 dockur/windows 的 winvm 模式:

- 屏幕参数对标 OnePlus 15: 1272×2772 @450dpi (6.78" 1.5K)
- 机型伪装 (spoof) 为真实手机,过应用的模拟器检测
- scrcpy 投屏 (Wayland 下锐利,无 Remmina 分数缩放模糊)
- adb 仅绑 127.0.0.1,不自启,`droidvm` 命令对齐 `winvm`

## 关键决策

| 项 | 决策 | 原因 |
|---|---|---|
| 镜像 | `redroid/redroid:15.0.0-latest` | **16.0.0 在 SwiftShader guest 模式必崩** (SF abort "output buffer not gpu writeable",上游 issue remote-android/redroid-doc#934 未修,16.0.0 只有 2025-06 一个构建) |
| 运行模式 | **rootful podman** (sudo) | rootless 下 Android init second stage 挂 cgroup v2 控制器时 EBUSY (容器 cgroup 非 root,受 no-internal-process 约束),init FATAL 后主动 reboot("bootloader"),容器 exit 129 全程零日志。官方也只测 rootful docker |
| GPU | SwiftShader 软渲染 (`gpu_mode=guest`) | 宿主 N 卡只有单个 render 节点,virtio-gpu 路径容器内不可用;日常 App 流畅,3D 游戏不适合 |
| 网络 | bridge 网络 + 显式 `mtu: "1500"` | **netavark 会误读 sing-box tproxy 表 (table 100, `local default dev lo`, MTU 65536) 作为默认路由接口**,65536 超过 veth 上限 65535 → 创建 veth EINVAL,容器起不来 |
| 机型伪装 | OnePlus 13 (PJZ110, Android 15) | 镜像降为 15 后伪装目标随之从 OnePlus 15 (PLK110) 调整;fingerprint 取自 GitHub 上公开的真实设备值 |
| ARM 翻译 | 预留 libndk/ 目录,暂未挂 | 先跑通 x86_64 原生,ARM-only 应用后续再接 |

## 布局

```
~/redroid/
├── compose.yml      # redroid/redroid:15.0.0-latest
├── data/            # /data 持久化卷 (删它 = 恢复出厂; rootful 运行故为 root 所有)
└── libndk/          # (预留) arm64→x86_64 翻译层 blobs
```

管理命令: `~/.local/bin/droidvm` — `start/stop/restart/status/logs/screen/shell/spoof/edit`。
容器 rootful,故 podman 相关子命令走 sudo;adb/scrcpy 走发布的 127.0.0.1:5555,无需 sudo。

## 机型伪装实现 (droidvm spoof)

`ro.product.*` 全局属性由 init 从各分区 build.prop 派生,**七个文件一个都不能漏**:

- `/system/build.prop` (system)
- `/vendor/build.prop` (vendor)
- `/odm/etc/build.prop` (odm)
- `/system_ext/etc/build.prop` (system_ext)
- `/system/product/etc/build.prop` (product)
- `/vendor/odm_dlkm/etc/build.prop` (odm_dlkm)
- `/vendor/vendor_dlkm/etc/build.prop` (vendor_dlkm)

sed 按 `ro.product.<part>.{brand,device,manufacturer,model,name}` 通配分区段替换 +
`ro.<part>.build.fingerprint` 统一指纹 + `/system/build.prop` 补 `ro.build.fingerprint` 和 `ro.build.product`。
所有分区在 redroid 里都是可写的,改完 `droidvm restart` 生效。容器重建 (`compose up` 换镜像/强制重建) 后需重跑。

指纹: `OnePlus/PJZ110/OP5D0DL1:15/AP3A.240617.008/V.1bd19a1-1-2:user/release-keys`

## 验收结果 (2026-08-20 验证)

- `sys.boot_completed=1`, Android 15, SF 稳定 running
- `wm size` = 1272x2772, `wm density` = 450
- scrcpy 投屏正常 (需 `--audio-codec=aac`,redroid 无 opus 编码器)
- 伪装后 `ro.product.{model,brand,device,manufacturer,name}` = PJZ110/OnePlus/OP5D0DL1,指纹正确

## 已知限制 / 后续

- Android 16 需等 redroid 上游修复 SF SwiftShader 崩溃后换回 (compose.yml 里有注释说明)
- rootful 的 podman 默认网络 (`podman`, 10.88.0.0/16) 有同样的 MTU 问题,其他 rootful 容器会踩;如需可 `podman network rm podman && podman network create --opt mtu=1500 podman`
- 不自启 (`restart: "no"`),与 winvm 一致
