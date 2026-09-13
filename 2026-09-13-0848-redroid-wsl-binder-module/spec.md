# redroid Android 容器恢复(本机 WSL · 外置 binder 模块 + GHCR 全烘焙镜像)设计文档

日期:2026-09-13 · 状态:设计已批准,待审阅 · 流程:brainstorming skill(方案对比→分节确认)
- 环境:WSL2 Ubuntu 26.04 @ Win11 物理机 DESKTOP-J7NBNU4(微软内核 6.18.33.2-microsoft-standard-WSL2);原环境为 Kubuntu 26.04 笔记本 yaoshi15pro(离线)

## 背景与目标

恢复 root 的 Android 容器设备用于 APK 调试。原环境在笔记本(`~/redroid/` 全套,见 [../2026-08-20-1252-redroid-android-container/](../2026-08-20-1252-redroid-android-container/spec.md)),笔记本离线不可用;本机 WSL 内核 `CONFIG_ANDROID_BINDER_IPC is not set`(2026-09-13 实测),redroid 无法直接运行。

两项改进(用户指定):①镜像**全烘焙**(libndk 翻译层 + OnePlus 伪装烘焙进镜像,拉下即用,替代笔记本的"构建后离线补丁"流程);②镜像托管 **GHCR 私有包**,跨机器重建一步 `podman pull`。

## 范围

**In scope:**
- `wsl --export` 全量备份(硬前置,用户要求;独立于既有任何备份)
- binder_linux.ko 外置模块:源码树只编模块 + systemd 自加载 + 内核升级自愈钩子
- libndk 从 Google 模拟器镜像(google_apis API 35, x86_64-35_r09)重新提取
- 全烘焙 Containerfile + rootless podman build + push `ghcr.io/desmondc9/redroid15-oneplus`(私有)
- rootful podman 运行时(compose)+ 精简版 droidvm 脚本 + scrcpy(WSLg)

**Out of scope:**
- 自编完整内核换 `.wslconfig kernel=`(方案 A,已否决:全内核替换风险)
- VPS / 笔记本部署(方案 C/B,已否决)
- 旧 data/ 卷迁移(数据在离线笔记本;全新起点,笔记本醒了再说)
- Android 16(上游 SwiftShader 崩溃未修,维持 15)

## 方案设计

### 架构

```
WSL2 Ubuntu 26.04(微软内核不动)
├─ 0. wsl --export 全量备份(硬前置)
├─ 1. binder_linux.ko ← WSL2-Linux-Kernel 源码树(linux-msft-wsl-6.18.33.2 tag)
│      config=/proc/config.gz 解包 + CONFIG_ANDROID_BINDER_IPC=m
│      systemd: boot 时 insmod + mount -t binder → /dev/binderfs;vermagic 不匹配→触发重编
├─ 2. rootful podman 运行 ghcr.io/desmondc9/redroid15-oneplus
│      镜像内烘焙:redroid 15.0.0 + libndk ARM 翻译层 + OnePlus PJZ110 七文件伪装
├─ 3. ~/redroid/{compose.yml,data/} + droidvm(start/stop/restart/status/logs/screen/shell)
└─ 4. adb 127.0.0.1:5555(mirrored 端口共享)+ scrcpy(WSLg)
```

### 关键决策

| 决策 | 理由 |
|---|---|
| 外置 binder 模块而非换内核 | 内核镜像零改动;失败最坏 = 模块卸载即回原状;mirrored 网络/四服务/interop 零暴露 |
| Android 15(`redroid/redroid:15.0.0-latest`) | 16.0.0 SwiftShader guest 模式必崩(上游 issue remote-android/redroid-doc#934),笔记本已实证 |
| 全烘焙(libndk+spoof 进镜像) | 用户指定改进;消除事后补丁状态漂移;GHCR 拉下即用 |
| libndk 本机重新提取(非笔记本拷贝) | 源文件在离线笔记本;dl.google.com 直连友好,配方在 2026-08-20 档案 |
| rootful 运行 / rootless 构建 | rootless 下 Android init 挂 cgroup v2 EBUSY(笔记本实证);构建无需 root |
| bridge 显式 mtu 1500 | 笔记本 netavark 误读 tproxy 表坑的习惯性防御;本机无 tproxy 表,零成本保险 |
| spoof/edit 子命令退役 | 全烘焙后无事后补丁场景 |
| 三层数据流 schema | 不适用(纯基础设施,无 UI/domain/存储层);事件风暴见下(轻量) |

### 事件风暴(轻量)

- **write 维度**(操作者→command→event→后续):wsl --export → 备份 tar 落盘 → 才允许内核模块操作;编模块 → ko 产出 → systemd 加载 → binderfs 可挂;烘焙镜像 → push GHCR → 任何机器 pull 即运行;内核升级(WSL 自动)→ vermagic 失配 → systemd 钩子触发重编 → 模块恢复
- **read 维度**(调试者 view/query):droidvm status/logs/screen/shell;adb logcat/install/dumpsys;scrcpy 投屏

### 失败模式与回滚

| 故障 | 行为 |
|---|---|
| 模块编不出/加载失败 | rmmod + 禁用单元;内核与启动配置零残留;WSL 照常 |
| WSL 内核自动升级 | vermagic 失配 → 钩子重编(源码树与脚本保留在 ~/redroid/kernel/);期间容器仅无法启动,不影响宿主 |
| MODULE_SIG_FORCE 拒载未签名模块 | 实施期先查 config;若中招→本地生成密钥自签(密钥不入库) |
| 镜像构建失败 | 笔记本配方已验证,逐层排查;redroid 基础镜像 + libndk 提取相互独立可分步验证 |
| 容器起不来(cgroup/binder) | droidvm logs 定位;data/ 卷删除 = 恢复出厂,可重试 |
| 全局灾难 | wsl --export 备份 tar 恢复(wsl --import)——最终兜底 |

## 验收标准

1. `wsl --export` 备份 tar 存在且大小合理
2. `binder_linux.ko` 加载 + `/dev/binderfs` 挂载;`wsl --shutdown` 重启后 systemd 自愈加载
3. 容器 `sys.boot_completed=1`,`adb root` 直接成功(root 设备)
4. 七分区伪装 props = OnePlus PJZ110 指纹(`OnePlus/PJZ110/OP5D0DL1:15/AP3A.240617.008/V.1bd19a1-1-2:user/release-keys`)
5. 纯 ARM apk 安装可运行(libndk 生效直接证据)
6. scrcpy 投屏正常(`--audio-codec=aac`,redroid 无 opus)
7. GHCR 私有包:本机 `podman pull` 成功;匿名/他人不可见
8. `droidvm` 全子命令可用;`wm size`=1272x2772、density=450

## 机密红线

PAT 只存本地 podman login 凭据与 `~/.config/github-token-multi-tool/`;模块自签密钥(若需)本地生成;均不入 `~/plans`(gitleaks 把关)。

## 参考

- 原环境全套:[../2026-08-20-1252-redroid-android-container/](../2026-08-20-1252-redroid-android-container/spec.md)(含 libndk 提取配方、spoof 七文件细节、SwiftShader/MTU 坑)
- 备份归档:[../2026-08-20-2032-redroid-backup/](../2026-08-20-2032-redroid-backup/)
- redroid 上游:https://github.com/remote-android/redroid-doc
