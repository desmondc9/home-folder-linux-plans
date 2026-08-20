# Windows 11 VM 备份 — 实施记录

日期:2026-08-20

- [x] 确认 VM 已停止(`podman ps -a` → Exited 143,2m grace 内 ACPI 关机,磁盘一致)
- [x] `qemu-img info` 确认 data.img 为 raw 稀疏,虚拟 128G / 实际 19.6G
- [x] 打元数据包:`backups/state-2026-08-20.tar.gz`(1.6M,compose.yml + oem/ + storage 小文件)
- [x] 转换系统盘:`qemu-img convert -c -O qcow2` → `backups/data-2026-08-20.qcow2`(18G)
- [x] 校验:`qemu-img check` 通过(No errors found;15.91% allocated,74.56% 压缩簇)
- [x] 写恢复说明 `~/windows-vm/backups/README-2026-08-20.md`

## 备份产物

| 文件 | 大小 |
|------|------|
| `~/windows-vm/backups/data-2026-08-20.qcow2` | 18G |
| `~/windows-vm/backups/state-2026-08-20.tar.gz` | 1.6M |
| `~/windows-vm/backups/README-2026-08-20.md` | 恢复步骤 |

## 恢复要点(详见备份目录 README)

1. `podman compose down`
2. `mv storage/data.img storage/data.img.broken`
3. `qemu-img convert -O raw backups/data-2026-08-20.qcow2 storage/data.img`
4. (可选)`tar xzf backups/state-2026-08-20.tar.gz` 还原 MAC/vars,避免激活变化
5. `podman compose up -d`
