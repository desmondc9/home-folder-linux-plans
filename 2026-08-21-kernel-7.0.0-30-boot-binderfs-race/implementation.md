# 实施记录 — binderfs 启动竞态修复

- [x] 收集证据：`journalctl --list-boots` 定位两次失败启动（09:04、09:07)
- [x] 失败启动日志确认根因：`unknown filesystem type 'binder'` → local-fs.target 失败 → emergency 模式
- [x] 排除 NVIDIA 驱动问题（595.84 在 7.0.0-30 正常加载）
- [x] 备份 fstab 至 `/etc/fstab.bak-20260821`
- [x] 修改 binder 行：`defaults` → `nofail,x-systemd.after=systemd-modules-load.service`
- [x] `systemctl daemon-reload` 并验证生成单元排序（After 含 modules-load;WantedBy 而非 RequiredBy)
- [x] 重启验证正常模式可进入系统
