# dockur/windows Windows 11 VM — 设计

日期: 2026-08-19

## 背景与目标

在 Kubuntu 26.04 (KDE Plasma + Wayland, i7-14650HX / 62G RAM / 1.9T NVMe) 上配置一个**高性能 (virtio + KVM)、可持久化**的 Windows 11 VM,使用 [dockur/windows](https://github.com/dockur/windows) 容器方案而非 virt-manager。

## 决策记录

1. **dockur/windows 而非 virt-manager**: 用户明确要求。dockur 内部同样是 QEMU/KVM + virtio 磁盘/网卡,性能路径一致,但生命周期管理简化为容器操作。
2. **rootless podman 而非 rootful**(实施中调整): 原设计 rootful,但本会话 sudo 无 TTY 无法缓存凭证;且实测 `/dev/kvm` 已有 `user:desmond:rw-` ACL、`Linger=yes` 已开、docker-compose 2.40.3 + podman-compose 均在 —— rootless 零 sudo 全链路可跑,自动启动由 linger + `restart: unless-stopped` 保证。
3. **复用本地 ISO**: `~/Downloads/Win11_25H2_English_x64.iso` (7.3G) 复制为 `~/windows-vm/iso/win11x64.iso` 并挂载为 `/boot.iso`,跳过 7.3G 下载;版本由 dockur 自动识别 (Windows 11 Pro)。
4. **旧 libvirt win11 VM 已清除**: undefine + 删除 win11.qcow2 (300G 上限/实占 21G,从未完成安装)。

## 布局

```
~/windows-vm/
├── compose.yml        # 配置即代码 (podman compose / podman-compose 均可)
├── iso/win11x64.iso   # Win11 25H2 安装 ISO,挂为 /boot.iso
├── oem/install.bat    # OOBE 末尾自动安装 OpenSSH Server
└── storage/           # dockur 管理;data.img (raw, 稀疏, 128G 上限)
```

## VM 规格

| 项 | 值 |
|---|---|
| 镜像 | `docker.io/dockurr/windows:latest` (v6.04, QEMU 10.0.11) |
| CPU/RAM/盘 | 8 核 / 16G / 128G (raw sparse, 按需增长) |
| 加速 | /dev/kvm + /dev/net/tun + NET_ADMIN;dockur 默认 host CPU 模型 + virtio |
| TPM/SecureBoot | dockur 内置 swtpm,满足 Win11 25H2 要求 |
| 端口 (仅 127.0.0.1) | 3389 RDP · 8006 web 控制台 · 2222 SSH |
| 账号 | `user` / `password` (localhost-only;改 compose env 后需重建 storage) |
| 持久化 | storage/ 卷持久保存;`restart: "no"` —— 不随宿主机自启(用户明确要求),用 `winvm start` 手动拉起 |

## 访问方式

- 日常: **Remmina → RDP 127.0.0.1:3389** (剪贴板/音频/分辨率自适应)
- 兜底: 浏览器 http://localhost:8006 (web 控制台,装系统时也可看进度)
- 自动化: `ssh -p 2222 user@localhost`

## 风险与注意

- podman 端口转发在容器启动即监听,**"端口通" ≠ guest sshd 就绪** —— 验证必须读到 `SSH-2.0-` banner。
- OpenSSH Server 由 install.bat 通过 Windows Update 在线安装,国内直连可用但慢,首次安装总时长约 20–40 分钟。
- `storage/` 由 dockur 管理,`compose down` 不丢数据;只有手动删 `storage/data.img` 才会重装系统。
- Docker Hub 直连已验证可达 (2026-08-19);若未来失效,按 CLAUDE.md 走 `127.0.0.1:10809` 代理。
