# redroid Android 备份 — 实施记录

日期:2026-08-20

- [x] 勘察:rootful 容器运行中;data 365M;镜像 2.08G;rootless/rootful 各一份镜像
- [x] 备份构建材料 → `backups/build-2026-08-20.tar.gz`(20M)
- [x] rootless `podman save | zstd` → `backups/redroid15-oneplus-2026-08-20.tar.zst`(772M)
- [x] 写 `backup-data.sh`(sudo 停→打包→启);首跑发现 rootful digest ≠ rootless digest → 改用 image Id 比对(内容指纹),确认两端一致
- [x] 应用户要求先卸载 nico:`adb uninstall com.superrhino.rarering`,验证 pm//data/app//data/data 无残留
- [x] 重跑备份 → `backups/data-2026-08-20.tar.gz`(9.5M,覆盖首版 295M 含 nico 备份)
- [x] 核实体积缩水原因(nico 129M apk + oat/split/运行数据;该机当天新建无其他三方 app,/sdcard 完好)
- [x] 脚本加固:文件名带 `%H%M` 防覆盖;停机前 `podman exec redroid stop` quiesce(redroid init 实测不响应 SIGTERM)
- [x] 写 `backups/README-2026-08-20.md` 恢复说明(场景 A 回滚 data / 场景 B 整体重建)

## 备份产物(~/redroid/backups/)

| 文件 | 大小 |
|------|------|
| `redroid15-oneplus-2026-08-20.tar.zst` | 772M(镜像,Id `7e3576254546…`) |
| `build-2026-08-20.tar.gz` | 20M(重建材料全套) |
| `data-2026-08-20.tar.gz` | 9.5M(卸载 nico 后的 /data) |
| `README-2026-08-20.md` | 恢复步骤 |
| `../backup-data.sh` | 复用脚本:`sudo ~/redroid/backup-data.sh` |

## 遗留/建议

- 镜像与 data 备份建议异地再存一份(移动硬盘/VPS)。
- 原 nico apk 保留在 `~/Downloads/NicovApp_qudao_home.apk`,需要时可 `adb install` 重装。
