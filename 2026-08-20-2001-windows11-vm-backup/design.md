# Windows 11 VM 备份 — 设计文档

日期:2026-08-20

## 背景与目标

`~/windows-vm` 里的 dockur/windows Win11 25H2 虚拟机(rootless podman)已经配置到可用状态。用户希望在系统被弄坏时能一键回滚到当前版本,因此需要一份完整、可恢复的本机备份。

## 现状分析

- 虚拟磁盘:`~/windows-vm/storage/data.img`,raw 稀疏格式,虚拟 128G,实际占用 ~19.6G。
- 元数据小文件:`storage/windows.{base,boot,mac,rom,vars,ver}`(MAC 地址、OVMF ROM/vars 等,影响 Windows 激活与网络标识)。
- 配置:`compose.yml` + `oem/`。
- 安装介质 `iso/win11x64.iso` 无需备份(恢复用不到)。
- 备份时容器已停止(Exited 143,ACPI 干净关机),磁盘一致。

## 方案

1. 系统盘:`qemu-img convert -c -O qcow2 storage/data.img backups/data-2026-08-20.qcow2` — 压缩 qcow2,兼顾体积与 `qemu-img check` 可校验性。
2. 元数据 + 配置:打 `state-2026-08-20.tar.gz`(compose.yml、oem/、storage 小文件)。
3. 恢复说明:同目录 `README-2026-08-20.md`,核心步骤是 `qemu-img convert -O raw` 转回 raw 稀疏盘 + 可选还原元数据。

备份位置:`~/windows-vm/backups/`(磁盘剩余 ~1.1T,18G 备份无压力)。

## 验收标准

- [x] qcow2 镜像 `qemu-img check` 无错误
- [x] 状态文件 tarball 可解包
- [x] 恢复步骤写成 README 放在备份旁边
