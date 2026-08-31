# redroid Android 备份 — 设计文档

日期:2026-08-20

## 背景与目标

`~/redroid` 的 redroid Android 15 容器(rootful podman)已配置到可用状态(OnePlus PJZ110 伪装 + berberis ARM64 翻译层)。用户要求:(1) 先从 Android 中卸载 NicovApp;(2) 然后完整备份,以便系统被弄坏时可回滚到当前干净状态。

## 现状分析

- 镜像:`localhost/redroid15-oneplus:latest`,手工烘焙(Containerfile + rebuild-nb.sh 打 spoof/翻译层补丁),重建成本高,**必须备份**。rootless 与 rootful 两端各有一份,已核实 Id 一致(`7e3576254546…`)——注意 `podman save|load` 后 repo digest 会不同,只有 image Id(config blob)能用于跨存储比对。
- 数据:`./data` bind-mount 到容器 /data,内含 root 700 权限目录,打包/恢复都需 sudo + `tar -p`。
- 构建材料:compose.yml / Containerfile / rebuild-nb.sh / libndk/,用户目录直接可读。
- 容器内唯一第三方 app 为 NicovApp(com.superrhino.rarering),本次先卸载再备份。

## 方案

1. 构建材料:普通 tar → `backups/build-2026-08-20.tar.gz`。
2. 镜像:rootless 端 `podman save | zstd`(无需 sudo;已验证与 rootful 同 Id)→ `backups/redroid15-oneplus-2026-08-20.tar.zst`。
3. /data:`backup-data.sh`(sudo)流程 = 校验镜像 Id → `podman exec redroid stop` 停 Android 运行时 → `podman stop` → root `tar -p` → 重启。
4. 恢复说明:`backups/README-2026-08-20.md`,分"回滚 /data"与"整体重建"两场景。

## 关键决策与坑

- **redroid init 不响应 SIGTERM**(实测 10s 与 120s 宽限均超时转 SIGKILL)。SIGKILL 下 ext4 日志一般可恢复,但为降低 SQLite 半写风险,脚本先 `podman exec redroid /system/bin/stop` 停 framework/zygote 等主要写入方。
- **备份文件名必须带时分**(`date +%F-%H%M`):本次同日第二次备份覆盖了第一版 295M 的 data 包。虽属预期(第一版含待卸载的 nico),但静默覆盖是隐患,已改。
- tar 对 `*.socket` 的 warning 无害(运行套接字,开机重建)。
- 卸载 nico 后 data 备份 295M→9.5M:app 本体 129M(原 apk 仍在 ~/Downloads)+ 解压的 oat/split + 运行时数据,已逐项核实无其他用户数据丢失(该 Android 当天新建,除 nico 外无第三方 app,/sdcard 与系统设置完好)。

## 验收标准

- [x] nico 卸载干净(pm、`/data/app`、`/data/data` 均无残留)
- [x] 镜像备份可 `podman load`(save 管道零错误,Id 与运行中容器一致)
- [x] data 备份含完整系统应用数据(2633 条目,`data/data|app|system|misc` 齐全)
- [x] 恢复 README 随备份存放;脚本可复用、同日多次不覆盖
