# restic → Azure Blob 备份系统 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本机(Ubuntu 26.04)建立 restic → Azure Blob(East Asia)每日自动备份,可在大陆环境 seeding ~80G,并在 Windows 11 WSL2 Ubuntu 中按 runbook 完整还原。

**Architecture:** 单仓库单每日快照(方案 A)。脚本与文档的源文件放 git 仓库 `~/Repos/desmondc9-restic-azure-backup`,由 `install.sh` 安装到系统路径(`/etc/restic/excludes.txt`、`/usr/local/bin/*.sh`、`/etc/systemd/system/restic-*.{service,timer}`)。root systemd 双 timer(每日备份 + 每周维护)绕开 sudo 密码。凭据仅存 `/root`(不进备份树)。

**Tech Stack:** restic(≥0.16,apt 或官方二进制)、az CLI 2.90.0(已登录 desmondc9@outlook.com)、bash、systemd。

**Spec:** `~/plans/2026-09-11-1012-restic-azure-backup/spec.md`(本计划从 spec 立论,执行者须先读 spec)

## Global Constraints

- **sudo 需要密码**:每个 task 开始先 `sudo -v`(15 分钟缓存过期即重新跑一次);涉及 root 的命令一律显式 `sudo` / `runuser`
- **网络**:GitHub 下载失败时先 `export http_proxy=http://127.0.0.1:10809 https_proxy=http://127.0.0.1:10809`(AGENTS.md 网络节);Azure `az` 直连即可
- **命名(不可改)**:RG `rg-desmond-backup`;存储账号 `desmondlinbak26`(重名则 `desmondlinbak26<两位随机>` 并回填 spec);容器 `restic-desktop`;仓库 `azure:restic-desktop:/`
- **路径(不可改)**:凭据 `/root/restic-env`、密码 `/root/restic.pw`(均 chmod 600,绝不出现在备份 include 路径);排除表 `/etc/restic/excludes.txt`;钩子 `/usr/local/bin/restic-pre-backup.sh`;手动入口 `/usr/local/bin/backup-now.sh`
- **保留策略(不可改)**:`--keep-daily 14 --keep-weekly 8 --keep-monthly 6`;维护 `prune` + `check --read-data-subset=1/10`
- **备份 include 路径(不可改)**:`/home/desmond /etc /usr/local /var/lib/tailscale /var/spool/cron/crontabs`,加 `--one-file-system`
- **状态文件**:`~/Backups/last-backup.txt`(注:spec §4.4 原写 manifests/last-backup.txt,因钩子每次清空 manifests 会误删,改放上一级——此为已批准的微调)
- **systemd unit 中 restic 路径**:`/usr/bin/restic`(apt 安装);若 Task 1 走官方二进制装到 `/usr/local/bin/restic`,Task 6 的 unit 内容用该路径
- 用户手动动作(执行者提醒,不代做):把 restic 密码与 SAS 存入 1Password + 打印密码纸质件

## 接口/产物清单(跨 task 依赖)

| 产物 | 定义处 | 消费处 |
|---|---|---|
| `/root/restic-env`(4 个 export:AZURE_ACCOUNT_NAME、AZURE_ACCOUNT_SAS、RESTIC_REPOSITORY、RESTIC_PASSWORD_FILE) | Task 3 | Task 3/4/7/8 的所有 restic 命令 |
| `/root/restic.pw`(单行 base64) | Task 3 | 同上(经 RESTIC_PASSWORD_FILE) |
| `/etc/restic/excludes.txt` | Task 4 | Task 4/6/7 |
| `/usr/local/bin/restic-pre-backup.sh` | Task 5 | Task 6 的 ExecStartPre |
| systemd 单元名 `restic-backup.service` / `restic-backup.timer` / `restic-maintenance.service` / `restic-maintenance.timer` / `restic-backup-failed.service` | Task 6 | Task 6/7;`backup-now.sh` |
| git 仓库 `~/Repos/desmondc9-restic-azure-backup` | Task 1 | 所有 task 的 commit |

---

### Task 1: 版本库脚手架 + restic 安装与 `**` 通配验证

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/README.md`(先占位,Task 9 完整化)
- Create: `~/Repos/desmondc9-restic-azure-backup/.gitignore`

**Interfaces:**
- Produces: git 仓库路径(后续所有 task 在此 commit);`restic` 可执行文件路径(Task 6 unit 引用)

- [ ] **Step 1: 建仓并初始化**

```bash
mkdir -p ~/Repos/desmondc9-restic-azure-backup && cd ~/Repos/desmondc9-restic-azure-backup
git init -b main
printf '%s\n' '# local test artifacts' 'testrepo/' '*.log' > .gitignore
cat > README.md <<'EOF'
# desmondc9-restic-azure-backup

restic → Azure Blob(East Asia)备份系统。源文件仓,经 install.sh 安装到系统路径。
Spec: ~/plans/2026-09-11-1012-restic-azure-backup/spec.md
EOF
git add -A && git commit -m 'scaffold repo'
```

- [ ] **Step 2: 安装 restic(apt 优先)**

```bash
sudo -v && sudo apt-get update && sudo apt-get install -y restic
restic version
```

Expected: 版本 ≥ 0.16(记下确切版本号,写进本文件末尾实施记录)。

- [ ] **Step 3: 若 apt 版本 < 0.16,改用官方二进制**

```bash
# 仅在 Step 2 版本 < 0.16 时执行(GitHub 需代理则先 export,见 Global Constraints)
cd /tmp && curl -LO https://github.com/restic/restic/releases/download/v0.17.3/restic_0.17.3_linux_amd64.bz2
bunzip2 restic_0.17.3_linux_amd64.bz2 && sudo install -m 755 restic_0.17.3_linux_amd64 /usr/local/bin/restic
restic version   # 确认 /usr/local/bin/restic 优先命中
```

- [ ] **Step 4: `**` 通配验证(决定 Task 4 的排除模式可用性)**

```bash
cd "$(mktemp -d)" && export RESTIC_REPOSITORY="$PWD/testrepo" RESTIC_PASSWORD_FILE=/dev/null
echo testpw > pw && export RESTIC_PASSWORD_FILE="$PWD/pw"
restic init
mkdir -p a/node_modules b/c/node_modules keep
touch a/node_modules/x b/c/node_modules/x keep/x a/target
restic backup . --dry-run -vv 2>&1 | grep -E 'node_modules|target' | wc -l   # 期望 0
restic backup . --exclude '**/node_modules' --exclude '**/target' --dry-run -vv 2>&1 | grep -cE 'node_modules|/target'   # 期望 0;若非 0 → 记录,Task 4 改用逐层 glob
unset RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
```

Expected: 两次计数均为 0(第二次证明 `**` 生效)。

- [ ] **Step 5: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add -A && git commit -m 'verify restic install and ** glob support' --allow-empty
```

---

### Task 2: Azure 资源组 + 存储账号 + 容器

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/azure-refs.txt`(记录资源 ID/端口,含 SAS 之外的元数据;SAS 本身**绝不**写入此仓)

**Interfaces:**
- Produces: RG `rg-desmond-backup`、账号 `desmondlinbak26`、容器 `restic-desktop`(Task 3 生成 SAS 时消费账号/容器名)

- [ ] **Step 1: 创建资源组与存储账号**

```bash
az group create --name rg-desmond-backup --location eastasia
az storage account create --name desmondlinbak26 --resource-group rg-desmond-backup \
  --location eastasia --sku Standard_LRS --kind StorageV2 --access-tier hot \
  --min-tls-version TLS1_2
```

Expected: `id` JSON 返回;若重名(StorageAccountAlreadyTaken),改 `desmondlinbak26<两位随机>` 重试,并把最终名回填 spec §4.1 与本计划 Global Constraints。

- [ ] **Step 2: 创建容器(用 account key——auth-mode login 需要数据面 RBAC 角色,Owner 不够,别走)**

```bash
KEY=$(az storage account keys list -n desmondlinbak26 -g rg-desmond-backup --query '[0].value' -o tsv)
az storage container create --account-name desmondlinbak26 --name restic-desktop \
  --account-key "$KEY"
```

Expected: `"created": true`。

- [ ] **Step 3: 验证 + 记录**

```bash
az storage account show --name desmondlinbak26 --resource-group rg-desmond-backup \
  --query '{name:name,location:location,sku:sku.name,tier:accessTier}' -o table
{ echo "# azure resources ($(date -Is))"; az storage account show -n desmondlinbak26 -g rg-desmond-backup --query id -o tsv; } > ~/Repos/desmondc9-restic-azure-backup/azure-refs.txt
```

- [ ] **Step 4: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add azure-refs.txt && git commit -m 'provision rg/storage/container (eastasia LRS hot)'
```

---

### Task 3: 凭据生成(SAS + restic 密码 + /root 文件)

**Files:**
- Create: `/root/restic-env`(root-only)
- Create: `/root/restic.pw`(root-only)
- Create: `~/Repos/desmondc9-restic-azure-backup/docs/recovery.md`(三要素说明,**不含**实际密钥值)

**Interfaces:**
- Produces: `/root/restic-env` 内容为 4 行 export(Task 3/4/7/8 的每个 root restic 命令前 `source` 它)

- [ ] **Step 1: 生成容器级 SAS(2 年)**

```bash
KEY=$(az storage account keys list -n desmondlinbak26 -g rg-desmond-backup --query '[0].value' -o tsv)
END=$(date -u -d '+2 years' '+%Y-%m-%dT%H:%MZ')
SAS=$(az storage container generate-sas --account-name desmondlinbak26 --name restic-desktop \
  --permissions racwdl --expiry "$END" --account-key "$KEY" --https-only -o tsv)
echo "SAS expires: $END  (length ${#SAS})"
```

Expected: SAS 长度 > 100,以 `?sv=` 开头。**不回显完整 SAS 到终端日志之外**。

- [ ] **Step 2: 生成密码与 /root 文件**

```bash
sudo -v
openssl rand -base64 32 | sudo tee /root/restic.pw >/dev/null && sudo chmod 600 /root/restic.pw
sudo tee /root/restic-env >/dev/null <<EOF
# restic Azure 凭据 — root only,不进备份树
# SAS 到期日: $END  (到期前重签:见 docs/recovery.md)
export AZURE_ACCOUNT_NAME=desmondlinbak26
export AZURE_ACCOUNT_SAS='$SAS'
export RESTIC_REPOSITORY=azure:restic-desktop:/
export RESTIC_PASSWORD_FILE=/root/restic.pw
EOF
sudo chmod 600 /root/restic-env
sudo ls -l /root/restic-env /root/restic.pw   # 期望两行均 -rw------- root root
```

- [ ] **Step 3: 初始化远端仓库(连通性验证)**

```bash
sudo -E bash -c 'source /root/restic-env && restic init && restic snapshots'
```

Expected: `created restic repository` 且 snapshots 列表为空报错(`restic snapshots` 空仓库时 exit 1 并提示 no snapshot data,属正常——连通即成功)。若网络失败重试一次,仍失败则按 Global Constraints 检查代理。

- [ ] **Step 4: recovery.md(三要素文档,不含密钥值)**

```bash
mkdir -p ~/Repos/desmondc9-restic-azure-backup/docs
cat > ~/Repos/desmondc9-restic-azure-backup/docs/recovery.md <<'EOF'
# 灾后恢复三要素(缺一即报废)

1. Microsoft 账号 desmondc9@outlook.com(az login / portal,可重签 SAS)
2. restic 仓库密码:1Password 条目「restic desmondlinbak26」+ 纸质打印件
3. 存储账号 desmondlinbak26 / 容器 restic-desktop(East Asia)

## SAS 续签(到期前 1 个月)
KEY=$(az storage account keys list -n desmondlinbak26 -g rg-desmond-backup --query '[0].value' -o tsv)
az storage container generate-sas --account-name desmondlinbak26 --name restic-desktop \
  --permissions racwdl --expiry $(date -u -d '+2 years' '+%Y-%m-%dT%H:%MZ') \
  --account-key "$KEY" --https-only -o tsv
# 更新 /root/restic-env 的 AZURE_ACCOUNT_SAS 行 + 1Password 副本
EOF
```

- [ ] **Step 5: 用户手动动作(提醒,不代做)**

提示用户:① 打开 1Password 新建条目 `restic desmondlinbak26`,存入 `/root/restic.pw` 内容与 SAS 字符串;② 打印密码纸质件。未完成前**不要**删除任何本机旧备份渠道。

- [ ] **Step 6: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add docs/recovery.md && git commit -m 'credentials setup + recovery doc (values in 1Password only)'
```

---

### Task 4: 排除表落盘 + dry-run 断言

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/excludes.txt`(源)
- Create: `/etc/restic/excludes.txt`(安装目标,install.sh 在 Task 9;本 task 先直接落盘)

**Interfaces:**
- Produces: `/etc/restic/excludes.txt`(Task 6 unit 的 `--exclude-file` 消费;Task 7 首备消费)

- [ ] **Step 1: 写源文件(内容 = spec §4.3 全文)**

```bash
cd ~/Repos/desmondc9-restic-azure-backup
cat > excludes.txt <<'EOF'
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
EOF
```

- [ ] **Step 2: 落盘到 /etc/restic/**

```bash
sudo -v && sudo mkdir -p /etc/restic && sudo install -m 644 excludes.txt /etc/restic/excludes.txt
```

- [ ] **Step 3: dry-run 断言一:排除项零命中**

```bash
sudo -E bash -c 'source /root/restic-env && restic backup --dry-run -vv --one-file-system \
  --exclude-file /etc/restic/excludes.txt \
  /home/desmond /etc /usr/local /var/lib/tailscale /var/spool/cron/crontabs' \
  2>&1 | tee /tmp/dryrun.log | grep -cE 'node_modules|/\.cache/|Steam|/containers/|\.freetoken|windows-vm|\.npm/|/go/'
```

Expected: `0`。若非 0:检查对应行拼写;若 `**` 系失效(Task 1 Step 4 已有先兆),把 `**/X` 改写为 `/home/desmond/Repos/*/X` + `/home/desmond/Repos/*/*/X` 两层并重跑。

- [ ] **Step 4: dry-run 断言二:必含项在场**

```bash
grep -cE '/\.ssh/|/\.claude/|/\.config/opencode|sing-box|/Documents/' /tmp/dryrun.log
```

Expected: > 0(每类至少一行;`/etc/sing-box`、`~/.ssh`、AI 工具目录、Documents 必须出现)。同时记录 `grep -c '^' /tmp/dryrun.log` 总行数到实施记录。

- [ ] **Step 5: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add excludes.txt && git commit -m 'exclude list from spec 4.3, dry-run verified'
```

---

### Task 5: 备份前钩子(manifests + dotfiles 打捞)

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/restic-pre-backup.sh`(源)
- Create: `/usr/local/bin/restic-pre-backup.sh`(安装目标)
- Test: 手工运行 + 断言(本仓无测试框架,shell 检查即测试)

**Interfaces:**
- Produces: `~/Backups/manifests/*.txt`(10 类清单)、`~/Backups/dotfiles/**`(打捞件)——随备份带走;`~/Backups/last-backup.txt` 由 systemd 写(Task 6)

- [ ] **Step 1: 写脚本**

```bash
cd ~/Repos/desmondc9-restic-azure-backup
cat > restic-pre-backup.sh <<'EOF'
#!/usr/bin/env bash
# 备份前钩子:刷新 manifests + 打捞被排除工具链里的小配置。root 运行。
set -euo pipefail
DEST=/home/desmond/Backups
M="$DEST/manifests"; D="$DEST/dotfiles"
mkdir -p "$M" "$D"
rm -rf "$M"; mkdir -p "$M"

{ echo "# generated $(date -Is) on $(hostname)"; uname -a; restic version; } > "$M/system-info.txt"
apt-mark showmanual          > "$M/apt-mark-showmanual.txt"
dpkg --get-selections        > "$M/dpkg-selections.txt"
snap list                    > "$M/snap-list.txt"
command -v flatpak >/dev/null 2>&1 && flatpak list > "$M/flatpak-list.txt" || true
command -v podman   >/dev/null 2>&1 && podman images > "$M/podman-images-root.txt" || true
runuser -u desmond -- podman images > "$M/podman-images-desmond.txt" 2>/dev/null || true
runuser -u desmond -- bash -lc 'command -v code >/dev/null 2>&1 && code --list-extensions' > "$M/code-extensions.txt" 2>/dev/null || true
ls /opt > "$M/opt-listing.txt"
chown -R desmond:desmond "$M"

salvage() {  # $1 = 绝对路径,存在则拷入 dotfiles 保持相对路径
  if [ -f "$1" ]; then
    mkdir -p "$D/$(dirname "${1#/}")"
    cp -a "$1" "$D/${1#/}"
    echo "salvaged: $1"
  fi
}
salvage /home/desmond/.m2/settings.xml
salvage /home/desmond/.cargo/config.toml
salvage /home/desmond/.cargo/credentials
salvage /home/desmond/.cargo/credentials.toml
salvage /home/desmond/.gradle/gradle.properties
salvage /home/desmond/.sdkman/etc/config
salvage /home/desmond/.android/adbkey
salvage /home/desmond/.android/adbkey.pub
salvage /home/desmond/.android/debug.keystore
salvage /home/desmond/.dotnet/NuGet/NuGet.Config
salvage /home/desmond/.nuget/NuGet/NuGet.Config
chown -R desmond:desmond "$D" 2>/dev/null || true
exit 0
EOF
```

- [ ] **Step 2: shellcheck + 安装 + 试跑**

```bash
shellcheck restic-pre-backup.sh    # 无输出 = 通过(shellcheck 未装则 sudo apt-get install -y shellcheck)
sudo -v && sudo install -m 755 restic-pre-backup.sh /usr/local/bin/restic-pre-backup.sh
sudo /usr/local/bin/restic-pre-backup.sh
```

- [ ] **Step 3: 断言**

```bash
wc -l ~/Backups/manifests/*.txt        # 各文件行数 > 0(code-extensions 允许为空——code CLI 可能不在 PATH)
ls ~/Backups/dotfiles/home/desmond/.m2/ 2>/dev/null; ls ~/Backups/dotfiles/home/desmond/.sdkman/etc/ 2>/dev/null
stat -c '%U' ~/Backups/manifests/system-info.txt   # desmond
```

Expected: 清单非空;至少 `.m2/settings.xml`、`.sdkman/etc/config` 两个打捞件存在(勘探确认过这两个存在);manifests 属主 desmond。

- [ ] **Step 4: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add restic-pre-backup.sh && git commit -m 'pre-backup hook: manifests + dotfile salvage'
```

---

### Task 6: systemd 单元(每日备份 + 每周维护 + 失败标记)

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/systemd/restic-backup.service`
- Create: `~/Repos/desmondc9-restic-azure-backup/systemd/restic-backup.timer`
- Create: `~/Repos/desmondc9-restic-azure-backup/systemd/restic-maintenance.service`
- Create: `~/Repos/desmondc9-restic-azure-backup/systemd/restic-maintenance.timer`
- Create: `~/Repos/desmondc9-restic-azure-backup/systemd/restic-backup-failed.service`
- Create(安装目标): `/etc/systemd/system/` 下同名 5 个文件

**Interfaces:**
- Consumes: `/root/restic-env`(Task 3)、`/etc/restic/excludes.txt`(Task 4)、`/usr/local/bin/restic-pre-backup.sh`(Task 5)
- Produces: `restic-backup.service` 等单元名(Task 7 的 backup-now.sh 消费)

- [ ] **Step 1: 写 5 个单元文件**

```bash
mkdir -p ~/Repos/desmondc9-restic-azure-backup/systemd && cd ~/Repos/desmondc9-restic-azure-backup/systemd
cat > restic-backup.service <<'EOF'
[Unit]
Description=restic daily backup to Azure Blob
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/root/restic-env
Nice=19
IOSchedulingClass=idle
ExecStartPre=/usr/local/bin/restic-pre-backup.sh
ExecStart=/usr/bin/restic backup --tag daily --one-file-system \
  --exclude-file=/etc/restic/excludes.txt \
  /home/desmond /etc /usr/local /var/lib/tailscale /var/spool/cron/crontabs
ExecStartPost=/usr/bin/restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 6
ExecStartPost=/bin/sh -c 'echo "OK $(date -Is)" >> /home/desmond/Backups/last-backup.txt'
OnFailure=restic-backup-failed.service
EOF

cat > restic-backup.timer <<'EOF'
[Unit]
Description=restic daily backup at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > restic-maintenance.service <<'EOF'
[Unit]
Description=restic weekly prune + integrity check
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/root/restic-env
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/restic prune
ExecStartPost=/usr/bin/restic check --read-data-subset=1/10
OnFailure=restic-backup-failed.service
EOF

cat > restic-maintenance.timer <<'EOF'
[Unit]
Description=restic maintenance Sundays 04:00

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > restic-backup-failed.service <<'EOF'
[Unit]
Description=mark restic backup/maintenance failure

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "FAIL $(date -Is)" >> /home/desmond/Backups/last-backup.txt'
EOF
```

(若 Task 1 走了官方二进制:把两个 service 里的 `/usr/bin/restic` 全部替换为 `/usr/local/bin/restic`。)

- [ ] **Step 2: 安装 + 生效**

```bash
sudo -v
sudo install -m 644 restic-backup.service restic-backup.timer restic-maintenance.service \
  restic-maintenance.timer restic-backup-failed.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer restic-maintenance.timer
systemctl list-timers | grep restic
```

Expected: 两行 timer,`restic-backup.timer` 下次触发明天 03:00,`restic-maintenance.timer` 下个周日 04:00。

- [ ] **Step 3: 单元文件静态校验**

```bash
systemd-analyze verify /etc/systemd/system/restic-backup.service /etc/systemd/system/restic-maintenance.service
```

Expected: 无输出(无错误)。

- [ ] **Step 4: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add systemd/ && git commit -m 'systemd units: daily backup + weekly maintenance timers'
```

---

### Task 7: 手动入口 + 首备 seeding

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/backup-now.sh`(源)
- Create: `/usr/local/bin/backup-now.sh`(安装目标)

**Interfaces:**
- Consumes: `restic-backup.service`(Task 6)
- Produces: 远端首个 `daily` tag 快照;`~/Backups/last-backup.txt` 首行 OK

- [ ] **Step 1: 写手动入口**

```bash
cd ~/Repos/desmondc9-restic-azure-backup
cat > backup-now.sh <<'EOF'
#!/usr/bin/env bash
# 手动触发一次 restic 备份(走 systemd,与定时任务同路径)
set -euo pipefail
sudo -v
sudo systemctl start --no-block restic-backup.service
echo "started; tail with: journalctl -u restic-backup.service -f"
EOF
chmod +x backup-now.sh && sudo install -m 755 backup-now.sh /usr/local/bin/backup-now.sh
```

- [ ] **Step 2: 首备 seeding(手动,长任务)**

```bash
backup-now.sh
journalctl -u restic-backup.service -f    # 盯到 "snapshot <id> saved";中断无妨,重跑 backup-now.sh 续传
```

Expected: 首备 ~80G 原始数据,上传(压缩后估 60-70G)随大陆→东亚带宽数十分钟到数小时;结束出现 `snapshot ... saved` 与 forget 输出。

- [ ] **Step 3: 结果断言 + 记录**

```bash
sudo -E bash -c 'source /root/restic-env && restic snapshots && restic stats --mode raw-data'
cat ~/Backups/last-backup.txt    # 末行 "OK <时间>"
```

把 `restic stats` 的 Total Size(压缩后)与 Total Restore Size 写进本文件末尾实施记录。

- [ ] **Step 4: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add backup-now.sh && git commit -m 'manual entry + seeding done'
```

---

### Task 8: 抽样还原演练(spec §4.9.2)

**Files:**(无新文件,验证型 task)

**Interfaces:**
- Consumes: Task 7 的首个快照

- [ ] **Step 1: 还原 /etc/sing-box 到临时目录并比对**

```bash
sudo -v
sudo rm -rf /tmp/restore-test && mkdir -p /tmp/restore-test
sudo -E bash -c 'source /root/restic-env && restic restore latest:/etc/sing-box --target /tmp/restore-test'
sudo diff -r /etc/sing-box /tmp/restore-test/sing-box && echo IDENTICAL
sudo rm -rf /tmp/restore-test
```

Expected: `IDENTICAL`(diff 无输出)。若 diff 报权限导致读取失败,先 `sudo` 已覆盖——不应出现。

- [ ] **Step 2: 顺带验证一个 home 路径(AI 工具记忆)**

```bash
sudo rm -rf /tmp/restore-test && mkdir -p /tmp/restore-test
sudo -E bash -c 'source /root/restic-env && restic restore latest:/home/desmond/.config/opencode --target /tmp/restore-test'
diff -r ~/.config/opencode /tmp/restore-test/opencode >/dev/null 2>&1; echo "exit=$? (0=identical, 1=有 churn 属正常,2=结构异常需查)"
sudo rm -rf /tmp/restore-test
```

Expected: exit 0 或 1(备份后配置仍在变化属正常);exit 2 需排查。

---

### Task 9: RUNBOOK.md + install.sh + README 完整化

**Files:**
- Create: `~/Repos/desmondc9-restic-azure-backup/RUNBOOK.md`
- Create: `~/Repos/desmondc9-restic-azure-backup/install.sh`
- Modify: `~/Repos/desmondc9-restic-azure-backup/README.md`

**Interfaces:**
- Consumes: 前面所有 task 的产物(安装源清单)
- Produces: `install.sh`(重建机器时一键重装本地件;凭据仍按 recovery.md 手工恢复)

- [ ] **Step 1: RUNBOOK.md(WSL 还原手册,命令可复制)**

```bash
cd ~/Repos/desmondc9-restic-azure-backup
cat > RUNBOOK.md <<'EOF'
# WSL2 Ubuntu 还原手册(spec §4.8)

前提:Windows 11 + WSL2 Ubuntu(systemd 已启用:`/etc/wsl.conf` 含 `[boot]\nsystemd=true`)。

## 1. 装 restic 并取回凭据
sudo apt-get update && sudo apt-get install -y restic
# 从 1Password 条目「restic desmondlinbak26」取三样:账号名、SAS、仓库密码
mkdir -p ~/.restic-restore && printf '%s' '<仓库密码>' > ~/.restic-restore/pw && chmod 600 ~/.restic-restore/pw
export AZURE_ACCOUNT_NAME=desmondlinbak26
export AZURE_ACCOUNT_SAS='<SAS>'
export RESTIC_REPOSITORY=azure:restic-desktop:/
export RESTIC_PASSWORD_FILE=$HOME/.restic-restore/pw

## 2. 体检与预览
restic snapshots
restic restore latest --target / --dry-run   # 预览

## 3. 还原(必须 -E,否则 sudo 丢弃环境变量)
sudo -E restic restore latest --target /
# 写入 /home/desmond /etc /usr/local /var/lib/tailscale /var/spool/cron/crontabs

## 4. 后处理
sudo chown -R desmond:desmond /home/desmond
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_* && chmod 644 ~/.ssh/*.pub 2>/dev/null
restic check

# 按 manifests 重装(清单在 ~/Backups/manifests/)
xargs sudo apt-get install -y < ~/Backups/manifests/apt-mark-showmanual.txt
awk 'NR>1{print $1}' ~/Backups/manifests/snap-list.txt | xargs -r -n1 sudo snap install
# 工具链重装:nvm/sdkman/uv/rustup …(对照 ~/Backups/manifests/system-info.txt)
# dotfiles 打捞件拷回:cp -a ~/Backups/dotfiles/home/desmond/.m2/settings.xml ~/.m2/ 等按需

sudo systemctl enable --now tailscaled   # 节点身份已随 /var/lib/tailscale 回来,免重新认证
# sing-box / frpc / ollama:sudo systemctl enable --now sing-box sing-box-tproxy …
#   ⚠ WSL2 TUN/tproxy 能力与真机有差异:先 systemctl status 看报错再启用 tproxy 模式

# 输入法:sudo apt install fcitx5-rime && fcitx5-remote -r  # 配置已随 home 回来
# crontab:sudo chmod 600 /var/spool/cron/crontabs/* && sudo systemctl restart cron

## 5. 浏览器/微信/Lark:靠各自账号同步重下(未同步的书签密码自行承担)
EOF
```

- [ ] **Step 2: install.sh(源→系统路径,幂等)**

```bash
cat > install.sh <<'EOF'
#!/usr/bin/env bash
# 幂等安装:源文件 → 系统路径。在仓库根目录运行。
set -euo pipefail
cd "$(dirname "$0")"
sudo -v
sudo mkdir -p /etc/restic
sudo install -m 644 excludes.txt /etc/restic/excludes.txt
sudo install -m 755 restic-pre-backup.sh /usr/local/bin/restic-pre-backup.sh
sudo install -m 755 backup-now.sh /usr/local/bin/backup-now.sh
sudo install -m 644 systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer restic-maintenance.timer
echo "installed. timers:"; systemctl list-timers | grep restic
EOF
chmod +x install.sh
./install.sh
```

Expected: 安装输出 + 两行 timer(与 Task 6 一致,幂等重装无害)。

- [ ] **Step 3: README 完整化**

```bash
cat > README.md <<'EOF'
# desmondc9-restic-azure-backup

restic → Azure Blob(East Asia)备份系统:单仓库、每日 03:00 root timer、
保留 14d/8w/6m、周日 04:00 prune+check。详见 spec 与 RUNBOOK.md。

- `excludes.txt` — 排除表(spec §4.3)
- `restic-pre-backup.sh` — manifests + dotfiles 打捞钩子
- `systemd/` — 5 个单元文件
- `backup-now.sh` — 手动入口(`/usr/local/bin/backup-now.sh`)
- `install.sh` — 幂等安装到系统路径
- `docs/recovery.md` — 灾后恢复三要素 + SAS 续签
- `RUNBOOK.md` — WSL2 还原手册

Spec: ~/plans/2026-09-11-1012-restic-azure-backup/spec.md

## 日常
backup-now.sh                     # 手动备份
journalctl -u restic-backup -f     # 看进度
cat ~/Backups/last-backup.txt     # OK/FAIL 状态
sudo -E bash -c 'source /root/restic-env && restic snapshots'
EOF
```

- [ ] **Step 4: Commit**

```bash
cd ~/Repos/desmondc9-restic-azure-backup && git add -A && git commit -m 'runbook + installer + readme'
```

---

### Task 10: 文档回填与收尾

**Files:**
- Modify: `~/plans/2026-09-11-1012-restic-azure-backup/spec.md`(实施记录节)
- Modify: `~/plans/2026-09-11-1012-restic-azure-backup/implementation.md`(本文件勾选 + 实施记录)

- [ ] **Step 1: 回填实施记录**(restic 版本、dry-run 文件数、`restic stats` 两个体积、seeding 耗时、Task 8 比对结果)到 spec 末尾「实施记录」节与本文件末尾。

- [ ] **Step 2: 提醒用户完成 1Password + 纸质件**(若 Task 3 Step 5 未做)。

- [ ] **Step 3: plans 仓提交**

```bash
cd ~/plans && git add 2026-09-11-1012-restic-azure-backup/ && git commit -m 'restic-azure-backup: implementation plan + backfilled results'
```

- [ ] **Step 4: 可选演练(建议,一次性)**:`wsl --import` 临时发行版走 RUNBOOK.md 全流程;完成后删除临时发行版,结果记入实施记录。

---

## 实施记录(执行时回填)

- restic 版本:
- dry-run 文件总数 / 排除断言:
- 首备:原始 __ G / 压缩上传 __ G / 耗时 __
- Task 8 比对:sing-box __ / opencode exit=__
- WSL 演练(可选):__
