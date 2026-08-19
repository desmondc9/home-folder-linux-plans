# dockur/windows Windows 11 VM — 实施记录

日期: 2026-08-19 · 关联: [design.md](design.md)

## 任务清单

- [x] 1. 清理旧 libvirt win11 VM: `virsh undefine win11 --nvram` + `vol-delete win11.qcow2 default` (回收实占 21G)
- [x] 2. 准备 `~/windows-vm/`: storage/iso/oem;复制 ISO 为 `iso/win11x64.iso`;写 `oem/install.bat` (OpenSSH 自动安装);写 `compose.yml`
- [x] 3. `podman pull docker.io/dockurr/windows:latest` — Docker Hub 直连成功;`podman compose up -d` 启动,端口映射正确
- [x] 4. 安装完成 — 全程约 **9 分钟** (比预估 20–40 分钟快,25H2 ISO + NVMe + 8 核);OOBE 自动执行 install.bat 装好 OpenSSH
- [x] 5. 验证全部通过 (见下)
- [x] 6. 归档文档 + gitleaks 扫描 + commit

## 实施备注

- 硬链接 ISO 失败 (`fs.protected_hardlinks`: 源文件属 libvirt-qemu:kvm),改用 `cp --reflink=auto`。
- 容器日志确认: 检测到 Windows 11 Pro、注入 OEM 文件与 win11x64.xml 自动应答、创建 128G raw 稀疏盘、从 DVD 引导进入安装。
- 安装监控: `podman logs -f windows11` (❯ 前缀为阶段日志);web 控制台 8006 实时画面。

## 验证结果 (2026-08-19 17:3x 实测)

| 验证项 | 结果 |
|---|---|
| SSH banner | `SSH-2.0-OpenSSH_for_Windows_9.5` ✓ |
| SSH 登录 (paramiko, user/password) | `win-75eiilsv34u\user` ✓ |
| OS 版本 | Windows 11 Pro, Build 26200 (25H2) ✓ |
| 资源生效 | 16G RAM / 8 逻辑核 ✓ |
| 端口监听 (rootlessport, 仅 127.0.0.1) | 2222 / 3389 / 8006 ✓ |
| 优雅关机 | `podman restart` → SIGTERM → ACPI shutdown,11 tick 完成 ✓ |
| 持久化 | 重启后直接从 data.img 引导 (无重装),`Windows started successfully`,SSH 约 1 分钟恢复登录 ✓ |

## 日常管理

```bash
cd ~/windows-vm
podman compose logs -f      # 看日志
podman restart windows11    # 重启 (ACPI 优雅关机)
podman stop windows11       # 关机
podman start windows11      # 开机 (重启宿主机后也会自动拉起: linger + unless-stopped)
```

- RDP: Remmina 连 `127.0.0.1:3389`,账号 `user` / `password`
- Web 控制台: http://localhost:8006
- SSH: `ssh -p 2222 user@localhost`
- 重装系统 (慎用): `podman compose down && rm ~/windows-vm/storage/data.img && podman compose up -d`
