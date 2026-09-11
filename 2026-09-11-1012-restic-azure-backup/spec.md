# restic 备份 Linux 桌面 → Azure Blob(WSL 可还原)设计规格

- 日期:2026-09-11 10:12
- 状态:设计已获用户逐节确认(brainstorming + grilling 两轮问答)
- 目标机器:HP/机械革命 笔记本,Ubuntu 26.04 LTS,ext4 `/` 1.9T(已用 1001G),独立空分区 `/data1`,主机名 yaoshi15proseries…

## 1. 背景与目标

用 restic 将本机(home + 系统配置)备份到 Azure Blob Storage,使得:

1. 平时可自动、加密、增量地备份;
2. 机器损坏/更换时,可在 **Windows 11 的 WSL2 Ubuntu** 中完整还原个人环境(home、/etc 自装配置、AI 工具记忆、输入法、证书等);
3. 可再生数据(游戏、容器镜像、缓存、模型、编译产物、工具链)不进备份,控制体积与成本。

### 灾后恢复三要素(缺一即报废,必须牢记)

| 要素 | 存放处 |
|---|---|
| Microsoft 账号(desmondc9@outlook.com,可 `az login` 重建 SAS/Key) | 用户本人 |
| restic 仓库密码 | **1Password + 纸质打印件** |
| 存储账号名 + 容器名(`desmondlinbak26` / `restic-desktop`) | 本 spec + 1Password 条目备注 |

## 2. 范围

### 做

- 新建 Azure 资源组 + 存储账号 + 容器(§4.1)
- restic 白名单式备份(§4.2/§4.3),单仓库单每日快照(方案 A)
- 备份前钩子:manifests + dotfiles 打捞(§4.4)
- root systemd 双 timer:每日备份 + 每周维护(§4.6)
- 手动入口 `backup-now.sh`;首备 seeding 流程(§4.7)
- WSL 还原 runbook(§4.8)与验证演练(§4.9)

### 不做

- 不备份整个 `/`(WSL 有自己的内核/发行版,整根还原会砸坏 WSL)
- 不做 GRS/异地冗余(个人数据,LRS 成本优先)
- 不做冷归档层(restic 增量与 prune 需要随机访问)
- 不删除/改造旧 `desmondc9-linux-backup` git 仓库(停跑 `backup.sh`,留作第二道保险与参考文档)
- 不备份 `/data1`(空分区,890G 可用,2.1M 已用)

## 3. 现状分析(勘探事实,2026-09-11 本机 du/systemctl/az 实测)

### 3.1 磁盘大头(home 共 848G)

| 项 | 体积 | 处置 |
|---|---|---|
| `.local/share/Steam` | 171G | 排除(重下载,存档走 Steam Cloud) |
| `.local/share/containers` | 159G | 排除(podman 镜像层,volumes 实测≈0;compose 定义在 Repos) |
| `.cache` | 135G | 排除(uv 缓存 80G、JetBrains 20G、yarn、浏览器缓存等) |
| `.freetoken` | 55G | 排除(models + venv) |
| `~/Repos` 编译产物 | 54G | 排除(node_modules/.venv/target 等,`**` 模式;`.git`/`.idea` 保留) |
| `windows-vm` | 47G | 排除(VM 磁盘/ISO,用户确认) |
| 工具链(`~/Android .dotnet .nvm .sdkman .m2 .rustup .cargo .gradle .nuget .bun .wine .var go .android .local/share/{wineprefixes,swift-toolchain,pnpm,uv}`) | ~55G | 排除 + 小配置由钩子打捞 |
| 浏览器 profiles(google-chrome×4 + edge + .mozilla) | ~20G | 排除(用户确认,靠账号同步) |
| 通讯(LarkShell 2G、discord 728M、.xwechat 988M) | ~3.7G | 排除(用户确认) |
| `.npm` | 24G | 排除 |
| `.local/share/{JetBrains,Trash,baloo}` | 32.6G | 排除(IDE 缓存/废纸篓/文件索引) |
| `/opt` | 13G | 排除(全部为手动装的应用本体;清单入 manifests) |
| **保留** | **~80G** | Documents 6.8G、Videos 12G、Downloads 9.3G、Pictures、Repos 源码 ~50G、AI 工具目录、其余 dotfiles |

### 3.2 系统侧事实

- `/etc` 仅 15M;自装服务:`sing-box.service`、`sing-box-tproxy.service`、`sing-box-rules-update.timer`、`tailscaled`、`frpc`、`ollama`、samba 等,unit 文件均在 `/etc/systemd/system`
- tailscale 节点状态在 `/var/lib/tailscale`(root-only,700)
- 用户 crontab:acme.sh 续期任务,文件在 `/var/spool/cron/crontabs`
- sunshine 配置实测在 `~/.config/sunshine`(apps.json、sunshine.conf、credentials)
- restic 未安装;`az` CLI 2.90.0 已登录(default-subscription)
- sudo 需要密码 → 自动化必须走 root systemd timer(不经过 sudo)
- 本机已有旧方案 `~/Repos/desmondc9-linux-backup`(git 提交式选择性备份),本方案上线后停用其日常运行

## 4. 方案设计(方案 A:单仓库 + 单每日快照)

### 4.1 Azure 资源

| 资源 | 值 | 说明 |
|---|---|---|
| Resource Group | `rg-desmond-backup`(eastasia) | 专用,不放其他项目资源 |
| Storage Account | `desmondlinbak26` | Standard_LRS,Hot 层;重名则追加随机后缀 |
| Container | `restic-desktop` | restic 仓库 = `azure:restic-desktop:/` |
| 认证 | 容器级 SAS | 权限 `racwdl`(read/add/create/write/delete/list),仅作用于此容器,有效期 2 年;到期前 1 个月在 `/root/restic-env` 注释里有到期日,凭 `az` 随时可重签 |

凭据文件 `/root/restic-env`(chmod 600,root-only,**不在任何备份路径内**):

```bash
export AZURE_ACCOUNT_NAME=desmondlinbak26
export AZURE_ACCOUNT_SAS='<container-sas>'
export RESTIC_REPOSITORY=azure:restic-desktop:/
export RESTIC_PASSWORD_FILE=/root/restic.pw
```

### 4.2 备份路径(include-list + `--one-file-system`)

```
/home/desmond
/etc
/usr/local          # 2.2G 自装工具
/var/lib/tailscale  # 节点身份,还原后免重新认证
/var/spool/cron/crontabs
```

用户原始 9 项排除表(`/proc /sys /dev /run /mnt /media /lost+found /tmp /swapfile`)**全部保留在 exclude 文件中作为防御层**:白名单下它们本就不可达,且 `/proc` 等是独立挂载点被 `--one-file-system` 双重拦截;保留是为了将来有人改回全盘备份时不踩雷。

### 4.3 排除清单(`/etc/restic/excludes.txt`)

```
# ---- 防御层(用户原表,白名单下本就不可达)----
/proc
/sys
/dev
/run
/mnt
/media
/lost+found
/tmp
/swapfile
/var/cache
/var/tmp
/var/lib/snapd
/var/lib/lxcfs

# ---- home:重下载类 ----
/home/desmond/.local/share/Steam
/home/desmond/.local/share/containers
/home/desmond/.cache
/home/desmond/.freetoken
/home/desmond/.npm
/home/desmond/.local/share/uv
/home/desmond/.local/share/JetBrains
/home/desmond/.local/share/Trash
/home/desmond/.local/share/baloo
/home/desmond/.local/share/swift-toolchain
/home/desmond/.local/share/pnpm
/home/desmond/.local/share/wineprefixes
/home/desmond/windows-vm
/home/desmond/.chromium-browser-snapshots
/home/desmond/.vscode-server

# ---- 浏览器 / 通讯(用户确认排除,靠各自同步)----
/home/desmond/.config/google-chrome
/home/desmond/.config/google-chrome-*
/home/desmond/.config/microsoft-edge
/home/desmond/.config/LarkShell
/home/desmond/.config/discord
/home/desmond/.mozilla
/home/desmond/.xwechat
/home/desmond/snap/chromium
/home/desmond/snap/firefox

# ---- 工具链(可重装;小配置由钩子打捞)----
/home/desmond/Android
/home/desmond/.android
/home/desmond/.dotnet
/home/desmond/.nvm
/home/desmond/.sdkman
/home/desmond/.m2
/home/desmond/.rustup
/home/desmond/.cargo
/home/desmond/.gradle
/home/desmond/.nuget
/home/desmond/.bun
/home/desmond/.wine
/home/desmond/.var
/home/desmond/go

# ---- ~/Repos 编译产物与依赖(.git/.idea/.worktrees 保留)----
**/node_modules
**/target
**/.gradle
**/dist
**/build
**/out
**/.venv
**/venv
**/__pycache__
**/.pytest_cache
**/.mypy_cache
**/.ruff_cache
**/.tox
**/.next
**/.nuxt
**/.turbo
**/bin/Debug
**/bin/Release
**/obj
```

注:AI 工具目录(`.claude` 1.4G、`.claude.json*`、`.config/opencode`、`.local/share/opencode` 2.1G、`.codex`、`.cursor`、`.config/superpowers` 1.3G、`.gemini`、`.qwen`、`.kimi` 等)**一律保留**;敏感 dotfiles(`.ssh .gnupg .git-credentials .azure .acme.sh .kube .docker`)也保留——restic 仓库端到端加密,云端只见密文(用户已确认)。

另注:`/opt`、`/usr`(除 /usr/local)、`/var`(除 tailscale 与 crontabs)、`/boot`、`/snap`、`/root` **不在 include-list 中,天然排除**,故不出现在 exclude 文件里——这是白名单方案的语义;exclude 文件只负责"include 路径内部"的裁剪与防御层。

### 4.4 备份前钩子(`/usr/local/bin/restic-pre-backup.sh`,root 执行)

写入 `~/Backups/`(属主 desmond,随备份带走):

- `manifests/`(每次覆盖刷新):
  - `apt-mark-showmanual.txt`、`dpkg-selections.txt`
  - `snap-list.txt`、`flatpak-list.txt`(存在才生成)
  - `podman-images.txt`(root 跑 rootful 清单 + `sudo -u desmond podman images` 各一份)
  - `code-extensions.txt`(`code --list-extensions`,存在才生成)
  - `opt-listing.txt`(`ls /opt`)
  - `system-info.txt`(`uname -a`、`restic version`、时间戳)
  - `last-backup.txt`(状态文件:时间 + 结果)
- `dotfiles/`(存在才拷,`cp -a --parents` 保持相对路径):
  - `~/.m2/settings.xml`
  - `~/.cargo/config.toml`、`~/.cargo/credentials`(及 `.toml` 变体)
  - `~/.gradle/gradle.properties`
  - `~/.sdkman/etc/config`
  - `~/.android/adbkey`、`~/.android/adbkey.pub`、`~/.android/debug.keystore`
  - `~/.dotnet/NuGet/NuGet.Config`、`~/.nuget/NuGet/NuGet.Config`

幂等:每次运行先清空 manifests 再生成;dotfiles 为增量拷贝(存在即覆盖)。

### 4.5 凭据生成

- 仓库密码:`openssl rand -base64 32` → 写 `/root/restic.pw`(chmod 600)→ 用户手工存入 1Password 并打印纸质件
- SAS:`az storage container generate-sas`(容器级,`--permissions racwdl --expiry <now+2y>`),字符串同时抄入 1Password 条目(灾后 WSL 侧直接可用,无需 az)

### 4.6 调度与保留

| 单元 | 时间 | 动作 |
|---|---|---|
| `restic-backup.service`(oneshot)+ `.timer` | 每日 03:00,`Persistent=true` | 钩子 → `restic backup --tag daily <路径>` → `restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 6` |
| `restic-maintenance.service` + `.timer` | 每周日 04:00 | `restic prune` + `restic check --read-data-subset=1/10` |

- 均以 root 运行,`EnvironmentFile=/root/restic-env`,`Nice=19`、`IOSchedulingClass=idle`
- 日志进 journald(`journalctl -u restic-backup`);失败时 systemd Failed 状态可见
- 手动入口:`/usr/local/bin/backup-now.sh` = `systemctl start restic-backup.service` 的薄封装
- 卡死锁处理:`restic unlock`(仅在确认无进程在跑时)写入 runbook

### 4.7 首次 seeding

- 手动 `backup-now.sh`,预计上传 ~60-70G(zstd 压缩后);大陆 → East Asia 实测带宽不定,03:00 窗口 + restic 可中断重跑(已传块不重传)
- 完成后 `restic stats`、`restic snapshots` 留档进 spec 实施记录

### 4.8 WSL 还原 runbook(核心交付物)

目标:全新 Windows 11 + WSL2 Ubuntu(systemd 已启用):

1. 安装 restic(apt 版本 ≥0.16 即可,或官方二进制)
2. 从 1Password 取回:存储账号名、SAS、restic 密码 → 导出四个环境变量(同 §4.1)
3. `restic snapshots` 完整性确认;`restic restore latest --target / --dry-run` 预览
4. `sudo -E restic restore latest --target /`(合并写入 /home/desmond、/etc、/usr/local、/var/lib/tailscale、/var/spool/cron/crontabs;**必须 `-E`**,否则 sudo 丢弃 RESTIC_*/AZURE_* 环境变量)
5. 后处理:
   - `sudo chown -R desmond:desmond /home/desmond`
   - `restic check`(仓库体检)
   - 按 `manifests/` 重装:`xargs sudo apt install -y < apt-mark-showmanual.txt`、`snap install …`、工具链(nvm/sdkman/uv/cargo 等)
   - `sudo systemctl enable --now tailscaled`(节点身份已随 /var/lib/tailscale 回来,免重新登录)
   - sing-box/frpc/ollama 等 unit 随 /etc 回来;`systemctl enable` 按需(WSL2 的 TUN/iptables 能力与真机有差异,tproxy 模式需验证,runbook 有注)
   - 输入法:`~/.local/share/fcitx5` 随 home 整体回来(优于旧仓库的零散拼装),装 fcitx5-rime 后 `fcitx5-remote -r` 重新部署
   - crontab 文件还原到 `/var/spool/cron/crontabs` 后 `chmod 600` + 重启 cron
   - SSH:权限回填 `chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_*`
   - dotfiles 打捞件从 `~/Backups/dotfiles/` 拷回原位( `.m2/settings.xml` 等)
6. 浏览器/微信/Lark:靠各自账号同步重下

### 4.9 验证与演练

1. **排除模式验证**(实现期):`restic backup --dry-run -vv 2>&1 | grep -cE 'node_modules|\.cache|Steam'` 必须为 0;若 restic 版本不支持 `**`,改用官方最新二进制(≥0.16 全支持)
2. **抽样还原比对**(首备后):`restic restore latest:/etc/sing-box --target /tmp/restore-test` → `sudo diff -r /etc/sing-box /tmp/restore-test/etc/sing-box` 必须无差异
3. **timer 生效**:`systemctl list-timers | grep restic` 两行
4. **manifests 非空**:各清单文件行数 > 0
5. **(建议,一次性)WSL 全量演练**:`wsl --import` 一次性发行版走完 §4.8,验证 runbook 可走通

## 5. 关键决策与理由

| 决策 | 理由 | 否决的备选 |
|---|---|---|
| restic + Azure Blob(East Asia LRS Hot) | 加密、去重、增量、官方 Azure 后端;东予权衡延迟成本 | Borg(无原生云后端)、rsync(无快照/加密弱)、TimeShift(仅本机)、GRS(成本×2,个人场景过度) |
| 方案 A 单仓库单快照 | 80G 体量下最简;全局去重;WSL 一条命令还原 | 双仓库分层(过度设计)、多任务多 tag(收益微弱) |
| include-list 而非全盘 `/` | WSL 有自己的内核/发行版,整根还原会砸坏它;"重建环境"语义 | 全盘备份(隐式依赖排除完整性,且会拖入 /usr /var 噪音) |
| root systemd timer | 绕开 sudo 密码;能读 /var/lib/tailscale 与 crontab | 用户级 timer(读不了 root-only 路径)、cron(无依赖/日志管理) |
| 编译产物 `.git`/`.idea`/`.worktrees` 保留 | 源码与未提交工作是真正不可再生数据 | 旧仓库做法(连 .git 一起排除,tar 分卷,笨重) |
| 敏感 dotfiles 纳入 | 仓库端到端加密 + 随机长密码;还原即全量恢复 | 仅靠 1Password 手工管理(易漏) |
| 浏览器/通讯/Lark 排除 | 用户确认靠账号同步 | — |

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| restic 密码丢失 = 备份全废 | 1Password + 纸质双备份(§1 三要素) |
| SAS 2 年到期 | 到期日写入 /root/restic-env 注释 + spec;随时可 `az` 重签 |
| `**` 通配在旧 restic 不生效 | 实现期 `--dry-run` 验证;必要时装官方最新二进制 |
| 大陆 → 东亚上传慢/中断 | 03:00 窗口、可中断重跑、增量小 |
| WSL2 与真机差异(TUN、tproxy、systemd unit 兼容) | runbook 显式标注;§4.9.5 全量演练 |
| 浏览器书签/密码未同步导致丢失 | 用户自担(已确认靠同步);runbook 提醒先检查同步状态 |
| 备份失败无人察觉 | journald + systemd Failed 状态;`last-backup.txt`;建议偶尔 `systemctl list-timers` 巡检 |

## 7. 性能与容量(基线与来源)

- **基线来源**:本机 `du`/`systemctl`/`az` 实测(2026-09-11,机器 yaoshi15proseries);Azure 价格为 East Asia Hot LRS 公开零售价估算(≈$0.0184/GB/月)
- **首备**:~80G 原始(见 §3.1 表),zstd 后预计 60-70G 上传;~$1.5-2/月存储成本 + 少量事务费
- **每日增量**:估计 0.1-2G(home churn 主要来自 AI 工具历史与 Documents)
- **硬限制核对**:Azure Block Blob 单块 ≤4000MiB、单 blob ≤190TiB——远超需求;restic 默认并发即可
- **I/O 影响**:备份在 03:00,`Nice=19` + idle I/O 调度;80G 顺序读对 NVMe 为分钟级
- **性能债**:无(排除即为了不引入"越用越慢"的结构)

## 8. 验收标准

1. `restic backup --dry-run` 文件列表中不出现任何排除模式命中的路径(node_modules/.cache/Steam/工具链/浏览器 profiles 等)
2. 首备完成后 `restic snapshots` 有带 tag 的快照;`restic stats` 体积与预估同量级
3. §4.9.2 抽样还原 `diff -r` 零差异
4. `systemctl list-timers` 显示两个 restic timer;手动 `backup-now.sh` 可跑通并刷新 `last-backup.txt`
5. `~/Backups/manifests/` 各清单非空
6. runbook(§4.8)以独立 Markdown 交付,命令可复制执行
7. (可选)WSL 一次性发行版全量演练走通

## 9. 参考

- restic 官方文档:Azure 后端、过滤模式、forget/prune/check
- 旧方案:`~/Repos/desmondc9-linux-backup/README.md`(停用,留作参考)
- 用户全局约定:`~/.config/opencode/AGENTS.md`(plans 命名、spec.md 规范)

---

**实施记录**(实现阶段回填):首备时间/体积/带宽、演练结果。
