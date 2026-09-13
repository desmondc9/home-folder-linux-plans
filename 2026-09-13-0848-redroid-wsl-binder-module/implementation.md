# redroid on WSL(binder 模块 + GHCR 全烘焙)实施计划

> **For agentic workers:** 按任务顺序执行;步骤 `- [ ]` 追踪。执行环境:本机 WSL Ubuntu 26.04;**Task 1(wsl --export)由用户在 Windows 侧执行且会终结 WSL 会话**——之后按本计划从 Task 2 恢复(ledger/spec 均持久)。

**Goal:** 本机 WSL 跑起 root 的 Android 15 容器(调试 APK),镜像全烘焙托管 GHCR 私有包,微软内核零改动。

**Architecture:** 外置 binder_linux.ko(源码树只编模块 + systemd 自愈加载)→ rootful podman 运行 `ghcr.io/desmondc9/redroid15-oneplus`(烘焙:libndk 翻译层 + OnePlus PJZ110 伪装)→ droidvm 管理 + scrcpy(WSLg)。

**Tech Stack:** microsoft/WSL2-Linux-Kernel(linux-msft-wsl-6.18.33.2)/ podman(rootless 构建 + rootful 运行)/ redroid 15.0.0 / ghcr.io

**Spec:** [spec.md](spec.md)

## Global Constraints

- **备份硬前置**:Task 1 完成前禁止任何内核模块 insmod/构建产物加载操作(构建/下载可先行)
- **微软内核零改动**:不写 `.wslconfig kernel=`、不替换 `/mnt/c/…/kernel` 文件;一切内核侧动作只有 insmod/rmmod binder_linux.ko
- **机密红线**:PAT、模块自签密钥(若需)不入任何 git 跟踪文件;commit 前 gitleaks
- **镜像固定 `redroid/redroid:15.0.0-latest`**(16.0.0 SwiftShader 必崩,上游 #934)
- libndk 配方以 [../2026-08-20-1252-redroid-android-container/implementation.md](../2026-08-20-1252-redroid-android-container/implementation.md) 为准(文件清单与提取命令照抄,不重新发明)

---

### Task 1: wsl --export 全量备份 `[用户执行,Windows 侧]`

**Files:**
- Create: `D:\WSL-backups\ubuntu-26.04-20260913.tar`(默认位置,可改)

- [ ] **Step 1: AI 查发行版名**:Windows 侧 `wsl -l -v` 确认本 WSL 的注册名(预期 Ubuntu-26.04 之类,写入报告)
- [ ] **Step 2: 用户在 Windows PowerShell(普通权限即可)执行**(会终止本 WSL,会话终结属预期):

```powershell
mkdir D:\WSL-backups -Force
wsl --shutdown
wsl --export <Step1查到的名字> D:\WSL-backups\ubuntu-26.04-20260913.tar
```

- [ ] **Step 3: 验证**:tar 存在、大小与 `\\wsl$\…` 使用量同量级(GB 级);保留策略 = 保留最近 1 份
- [ ] **Step 4: 用户重开 opencode 会话,从 Task 2 继续**

### Task 2: binder_linux.ko 模块构建

**Files:**
- Create: `~/redroid/kernel/`(WSL2-Linux-Kernel 源码树常驻,~2GB)
- Create: `~/redroid/kernel/binder_linux.ko`(产物)
- Create: `~/redroid/kernel/build-module.sh`(可重复构建脚本)

**Interfaces:**
- Produces: `binder_linux.ko`(Task 3 加载;vermagic 必须匹配 `uname -r`)

- [ ] **Step 1: 验源码 tag**:`git ls-remote --tags https://github.com/microsoft/WSL2-Linux-Kernel 'linux-msft-wsl-6.18.33*'`;命中 6.18.33.2 用之,否则取最近 6.18.33.x 并记录
- [ ] **Step 2: clone**(浅克隆 + tag,~10 分钟,GitHub 直连或 10809 代理)
- [ ] **Step 3: config 准备**:`zcat /proc/config.gz > .config`;`scripts/config -m ANDROID_BINDER_IPC -m ANDROID_BINDERFS`;`make olddefconfig`;同时 rg 检查 `MODULE_SIG_FORCE`(开启则记录,Task 3 需自签)
- [ ] **Step 4: 模块编译**:`make modules_prepare && make M=drivers/android modules`(需 build-essential/libssl-dev 等,先装);产物 `drivers/android/binder_linux.ko` 拷至 `~/redroid/kernel/`
- [ ] **Step 5: 验证**:`modinfo vermagic` 与 `uname -r` 一致;`sudo insmod` → `lsmod | grep binder`;`sudo mount -t binder binder /dev/binderfs` → `ls /dev/binderfs` 出现 binder-control;`sudo rmmod binder_linux` 卸载成功(可逆性证明)
- [ ] **Step 6: build-module.sh 固化**(clone+config+build 全流程,供内核升级后重跑)

### Task 3: systemd 自愈加载单元

**Files:**
- Create: `/etc/systemd/system/binder-module.service`(sudo)
- Modify: `/etc/fstab` 或 unit 内 mount(挂 /dev/binderfs)

**Interfaces:**
- Consumes: Task 2 的 ko 与 build-module.sh
- Produces: 开机自加载 + 内核升级自愈(验收 2)

- [ ] **Step 1: 写 unit**:`ExecStartPre` 检查 `modinfo vermagic` 匹配当前 `uname -r`,失配则后台触发 `build-module.sh` 并 exit 1(下次 boot 重试);`ExecStart`= insmod + `mount -t binder binder /dev/binderfs`;`RemainAfterExit=yes`;`Before=podman.service`(若有)
- [ ] **Step 2: enable + start**;`wsl --shutdown` 重启后验证自愈(用户配合一次重启)
- [ ] **Step 3: MODULE_SIG_FORCE 若中招**:本地 `openssl genrsa` 自签 + `scripts/sign-file`,密钥仅存 `~/redroid/kernel/`(不入 git)

### Task 4: libndk 翻译层提取

**Files:**
- Create: `~/redroid/libndk/system/…`(文件树)
- Create: `~/redroid/libndk.tar`

**Interfaces:**
- Produces: `libndk.tar`(Task 5 ADD 进镜像;文件清单严格照抄笔记本 implementation.md)

- [ ] **Step 1: 下载 Google 模拟器镜像** `x86_64-35_r09.zip`(dl.google.com,笔记本档案有完整 URL)→ `/tmp/`
- [ ] **Step 2: 按档案配方提取 ndk_translation 文件树**(清单在 2026-08-20 implementation.md,照抄路径与权限)
- [ ] **Step 3: 打包 libndk.tar**(tar 结构与笔记本一致,镜像内解到 /system 对应位置)

### Task 5: 全烘焙 Containerfile + rootless 构建

**Files:**
- Create: `~/redroid/Containerfile`
- Create: `~/redroid/compose.yml`(先写好,Task 7 用)

**Interfaces:**
- Consumes: libndk.tar(Task 4)
- Produces: `localhost/redroid15-oneplus:latest`(Task 6 推 GHCR;Task 7 也可直接本地跑)

- [ ] **Step 1: Containerfile**:`FROM redroid/redroid:15.0.0-latest` + `ADD libndk.tar /` + **烘焙期 sed 七文件 OnePlus PJZ110 伪装**(七文件清单与 sed 模式照抄笔记本档案,build 期执行而非事后)+ ENV 注明烘焙指纹
- [ ] **Step 2: `podman build`**(rootless;拉基础镜像走 sing-box 分流自动代理)→ `podman images` 见 localhost/redroid15-oneplus
- [ ] **Step 3: 烘焙自检**:起一次性容器 `getprop ro.product.model` = PJZ110 无需事后补丁(容器未挂 binder 也能验 props?若不能,移 Task 7 验收 4)

### Task 6: GHCR 私有包推送

**Files:**
- Create: 无新文件(PAT 用 `~/.config/github-token-multi-tool/` 现有 token)

**Interfaces:**
- Consumes: localhost 镜像(Task 5)
- Produces: `ghcr.io/desmondc9/redroid15-oneplus:{latest,<date>}`(私有)

- [ ] **Step 1: 验 PAT 权限**:`write:packages`(gh api user 后查 token scopes;缺则请用户补 token,绝不入库)
- [ ] **Step 2: `podman login ghcr.io`**(用户名 desmondc9 + PAT)
- [ ] **Step 3: tag 双标签 + push**(ghcr 走 sing-box 国外分流,无需手工代理;~2GB,耐心)
- [ ] **Step 4: 私有性验证**:匿名 `curl -s https://ghcr.io/v2/desmondc9/redroid15-oneplus/tags/list` 拒绝(401/404);本机 `podman pull` 成功

### Task 7: 运行时 + droidvm + 全量验收

**Files:**
- Create: `~/.local/bin/droidvm`
- Create: `~/redroid/data/`(卷)
- Modify: `~/redroid/compose.yml`(启用)

**Interfaces:**
- Consumes: GHCR 镜像(或本地等价)、Task 3 的 binderfs

- [ ] **Step 1: rootful podman 就绪**:`sudo podman info` 可用(必要时 `sudo podman system init`);compose:bridge 显式 mtu 1500、`/dev/binderfs:/dev/binderfs` 挂载、gpu=guest、1272x2772@450、restart:no、adb 发布 127.0.0.1:5555
- [ ] **Step 2: droidvm 脚本**(start/stop/restart/status/logs/screen/shell;podman 子命令走 sudo,adb/scrcpy 不用)
- [ ] **Step 3: 验收 8 条逐一打勾**(spec 验收标准 1-8;ARM apk 用任一纯 arm64-v8a 包,如 Termux F-Droid 版)
- [ ] **Step 4: 档案回填 + README + commit + gitleaks**

## 回退总开关

```bash
sudo systemctl disable --now binder-module.service; sudo rmmod binder_linux  # 内核侧归零
sudo podman compose -f ~/redroid/compose.yml down                            # 容器归零
# 终极:wsl --import 恢复 Task 1 备份
```
