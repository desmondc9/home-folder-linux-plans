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
- [x] libndk ARM 翻译层 (berberis 后端, 烘焙进镜像, ARM64 ELF 实机执行验证通过)
- [ ] Android 16 换回 (待上游修复 issue #934)

## ARM 翻译层实施记录 (2026-08-20 下午)

1. **官方镜像只配了框架没带库**: redroid 15 的 `ro.dalvik.vm.native.bridge=libnb.so`、`ro.enable.native.bridge.exec=1`、abilist 都配好了,但 `/system/lib64/arm64` 等目录全空。
2. **来源选择**: zhouziyang/libndk_translation 预编译包只到 Android 14。改用 Google 官方模拟器镜像 `sys-img/google_apis/x86_64-35_r09.zip` (API 35 = Android 15, 版本严格对齐;default/AOSP 标签的镜像不含翻译层,必须 google_apis)。
3. **提取**: zip 里的 system.img 是 GPT 磁盘 (第二分区偏移 4096 扇区 + 1MB 填充才是 ext4);debugfs 免 root 提取:`/system/lib64/arm64/*`、`/system/lib64/libndk_translation*.so` + `libnbaio/libnblog`、`/system/bin/arm64/*`、`/system/bin/ndk_translation_program_runner_binfmt_misc_arm64`、`/system/etc/binfmt_misc/*`、`/system/etc/init/ndk_translation.rc`,补 `libnb.so → libndk_translation.so` 符号链接 (redroid 约定名)。
4. **berberis**: 首次实机执行 ARM64 ELF 报缺 `libberberis_exec_region.so` —— API 35 的翻译后端是 berberis,补提取这一个文件即可,依赖链其余全是标准库。
5. **烘焙而非挂载**: `podman build` (Containerfile: FROM 15.0.0 + ADD libndk.tar,tar 时 `--owner=0 --group=0`) → `podman create/mount` 离线对 7 个 build.prop 打伪装补丁 → `podman commit` 为 `localhost/redroid15-oneplus:latest`。**全程 rootless**,导入 rootful 用 `podman save | sudo podman load`。一键脚本 `~/redroid/rebuild-nb.sh`。
6. **镜像内路径 ≠ 设备路径**: 设备上 `/odm` → `/vendor/odm`、`/system_ext` → `/system/system_ext`,离线补丁要用真实路径。
7. **abilist 收窄**: 翻译层只有 64 位,spoof 时同步把 `ro.*.product.cpu.abilist` 的 armeabi-v7a/armeabi 去掉,防止 32 位 ARM-only 应用装上却跑不起来。
8. **验证**: 手工构造最小 ARM64 静态 ELF (write+exit),经 binfmt → ndk runner → berberis 完整链路执行成功输出 `ARM64-OK`。berberis 对 ELF 头有严格校验 (必须有节区头、e_shstrndx 合法、禁 W+E 段)。

## 关键调试记录

1. **rootless 静默死 (exit 129)**: redroid init 在容器里写不了 kmsg,dmesg 宿主又限权,唯一有效手段是 `strace -f podman run ...` 从宿主侧跟容器内 syscall。看到 init second stage 写 `+memory` 到 cgroup.subtree_control 失败 (EBUSY/ENOENT) 后 abort → reboot("bootloader") → PID namespace 内 reboot = SIGHUP 杀 init = exit 129。
2. **rootful veth EINVAL**: `podman --log-level=debug` 输出 `Using mtu 65536 from default route interface`。宿主 sing-box tproxy 的 table 100 有 `local default dev lo`,netavark 误判 lo 为默认路由接口,65536 > veth 上限 65535。compose.yml 里 `networks.default.driver_opts.mtu: "1500"` 解决。
3. **SF "output buffer not gpu writeable"**: Android 16 镜像 SwiftShader guest 模式 boot 期 RenderEngine shader-cache 预热断言,上游 redroid-doc#934 未修,16.0.0 只有 2025-06-29 一个构建。`debug.sf.prime_shader_cache=0` 只能让崩溃延后,不能根治。
4. **spoof 不生效排查**: `ro.product.*` 由 init 从分区 build.prop 派生,`grep -rln redroid15_x86_64` 全文件系统扫出全部来源。漏一个分区 (如 product 分区的 `/system/product/etc/build.prop`) 就整体不生效。
5. **scrcpy 报 audio encoder 错**: redroid 无 opus,需 `--audio-codec=aac` (已固化进 droidvm screen)。
