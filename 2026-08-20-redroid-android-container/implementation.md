# redroid Android 容器 (droidvm) — 实施记录

时间: 2026-08-19 晚 ~ 2026-08-20 中午 (跨两个 session)

## 任务清单

- [x] 宿主前提: scrcpy/adb 安装, binderfs 挂载 + fstab 持久化, binder_linux 开机加载, /dev/loop* ACL (udev 规则 99-redroid-loop.rules)
- [x] ~/redroid/ 布局 + compose.yml (bridge 网络显式 mtu 1500)
- [x] ~/.local/bin/droidvm 管理命令 (对齐 winvm)
- [x] rootless podman 尝试 → strace 定位 init cgroup FATAL → 放弃,转 rootful
- [x] rootful netavark veth EINVAL → 定位为 tproxy lo 路由 MTU 65536 → compose 固定 mtu
- [x] Android 16 镜像 SF SwiftShader 崩溃 → 降 15.0.0-latest (用户确认)
- [x] Android 15 引导成功, scrcpy 投屏验证
- [x] droidvm spoof (OnePlus 13 PJZ110) — 七分区 build.prop 全量替换,重启验证通过
- [x] 清理 rootless 残留容器/镜像
- [ ] libndk ARM 翻译层 (预留,后续任务)
- [ ] Android 16 换回 (待上游修复 issue #934)

## 关键调试记录

1. **rootless 静默死 (exit 129)**: redroid init 在容器里写不了 kmsg,dmesg 宿主又限权,唯一有效手段是 `strace -f podman run ...` 从宿主侧跟容器内 syscall。看到 init second stage 写 `+memory` 到 cgroup.subtree_control 失败 (EBUSY/ENOENT) 后 abort → reboot("bootloader") → PID namespace 内 reboot = SIGHUP 杀 init = exit 129。
2. **rootful veth EINVAL**: `podman --log-level=debug` 输出 `Using mtu 65536 from default route interface`。宿主 sing-box tproxy 的 table 100 有 `local default dev lo`,netavark 误判 lo 为默认路由接口,65536 > veth 上限 65535。compose.yml 里 `networks.default.driver_opts.mtu: "1500"` 解决。
3. **SF "output buffer not gpu writeable"**: Android 16 镜像 SwiftShader guest 模式 boot 期 RenderEngine shader-cache 预热断言,上游 redroid-doc#934 未修,16.0.0 只有 2025-06-29 一个构建。`debug.sf.prime_shader_cache=0` 只能让崩溃延后,不能根治。
4. **spoof 不生效排查**: `ro.product.*` 由 init 从分区 build.prop 派生,`grep -rln redroid15_x86_64` 全文件系统扫出全部来源。漏一个分区 (如 product 分区的 `/system/product/etc/build.prop`) 就整体不生效。
5. **scrcpy 报 audio encoder 错**: redroid 无 opus,需 `--audio-codec=aac` (已固化进 droidvm screen)。
