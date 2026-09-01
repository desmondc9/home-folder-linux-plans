# 实施记录

## 变更

`~/.vscode/argv.json` 增加带注释的配置项(2026-09-01):

```jsonc
	// 2026-09-01: Kubuntu 26.04 kwallet6 6.24 regression — kwalletd6's KWallet-API
	// writePassword always fails (-1, "Can't find session /org/freedesktop/secrets/session/1")
	// because the Secret Service half moved to ksecretd. Chromium/Electron default-detects
	// KWallet on KDE and then can't persist its os_crypt key → VSCode Settings Sync errors
	// "OS keyring is not available". Force the libsecret/Secret Service backend (ksecretd),
	// which works. Remove when kwallet writePassword is fixed upstream.
	"password-store": "gnome-libsecret",
```

## 验证

- [x] A/B 对照(独立 user-data-dir + `--verbose`,单变量):
  - 默认(detect→kwallet):`Encryption is available: false` → in-memory
  - `--password-store=gnome-libsecret`:`true` → persisted
- [x] 仅 argv.json(无 CLI 参数):`true` → persisted
- [ ] 用户重启正式 VSCode 后 Settings Sync 恢复(需用户操作,预期首次需重新登录账号)

## 复现/诊断命令存档

```bash
# KWallet 写入失败复现(返回 -1,同秒 journal 出现 Can't find session)
busctl --user call org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet \
  open sxs kdewallet 0 vscode-debug-test
busctl --user call org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet \
  writePassword issss <handle> "Chrome Keys" "Chrome Safe Storage" "x" vscode-debug-test

# Secret Service 链路健康检查
busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
  org.freedesktop.Secret.Service ReadAlias s default

# journal 证据
journalctl --user | rg -i 'kwallet|ksecret|os_crypt'

# VSCode 加密状态 trace(独立实例,避免影响正式窗口)
code --user-data-dir /tmp/vsctest --disable-extensions --verbose --skip-release-notes \
  --skip-welcome 2>&1 | rg 'EncryptionMainService|SecretStorageService'
```

## 后续变更(2026-09-01 下午)

### git http 凭据(替代坏掉的 ksshaskpass 持久化)

- 新增 `~/.local/bin/git-credential-secretservice`(python3-gi + Secret Service,语义对齐
  contrib/git-credential-libsecret,schema `org.git.Password`)
- `git config --global credential.helper` 指向上述脚本(GitHub 仍走原有的
  `credential.https://github.com.helper = !gh auth git-credential`,URL 条件配置不受影响)
- 验证:approve→fill(仅 host 也能返回 username+password)→reject→fill 失败,全链路通过
- 已知异常:写入 ~/.gitconfig 的 `[credential]` 段曾在约 30 秒内被外部进程移除一次
  (16:03,mtime 悖论,未抓到元凶);重写后 md5 canary 观察 8+ 分钟无复发。若日后再现
  凭据失忆,先 `rg -A1 '^\[credential\]$' ~/.gitconfig` 检查该段是否还在。

### 浏览器(Chrome stable/beta、Edge、PWA 快捷方式)

- 12 个 .desktop 文件(`~/.local/share/applications/` 下 5 个主快捷方式 + 7 个
  `chrome-*-Default.desktop` PWA)的全部 Exec 行追加 `--password-store=gnome-libsecret`
- `kbuildsycoca6` + `update-desktop-database` 重建缓存
- A/B 验证(chrome-beta headless + 临时 profile):
  - control:复现 `freedesktop_secret_key_provider.cc:777/809` 两条错误
  - 加 flag:零错误
- 注意:Chrome 日后新生成/改写 PWA .desktop 时不会带该 flag,需重新补;
  snap 版 chromium 走 portal(ksecretd 持有 portal 后端),理论上不受影响
- 用户需完全退出浏览器(含后台进程)后重启;现有登录态本就在每次重启时丢失,
  切换后需最后再登录一轮,之后稳定

## 上游跟踪与修复落地 runbook(2026-09-01 建)

三层机制:

1. **systemd user timer**(永久):`kwallet-upstream-watch.timer` 每日 10:17±15m 跑
   `~/.local/bin/kwallet-upstream-watch`,状态写
   `~/.local/state/kwallet-upstream-watch/state.json`(bugs 523878/510038 状态 +
   上游 tag + 本机 apt candidate),有变化 → notify-send 桌面提醒。
   bugs.kde.org / invent.kde.org 国内直连可达,已留 127.0.0.1:10809 代理兜底。
2. **kimi 分析 agent**(每日 11:07±10m,`kwallet-upstream-agent.timer`,永久):
   `~/.local/bin/kwallet-upstream-agent` 先刷新状态,与 `last-agent-state.json` 快照
   比较——**无变化直接退出(零 token)**;有变化则经 `zsh -ic 'ccw --provider=kimi
   -p ...'` 无头跑一次纯分析任务(只读文件、不执行命令),结论追加到
   `agent-verdicts.log` 并 notify-send,kimi 的 stderr 留在 `last-kimi-stderr.log`。
   (原 Claude 会话内 durable cron 已删,避免烧 Claude 额度;ccw 的密钥只在
   ~/.zshrc,脚本不复制。)
3. 基线(2026-09-01):两 bug UNCONFIRMED,上游 tag v6.29.0,本机 6.24.0-0ubuntu1。
   E2E 已验证:跳过路径 + 伪造快照触发真实 kimi 分析,结论与通知均正常。

### 修复落地 runbook(上游出修复后)

1. 用户终端执行(交互式 sudo 用 `!` 前缀):
   `sudo apt update && sudo apt install kwallet6`,然后**注销重登**(ksecretd/kwalletd 由
   PAM 拉起,换版本必须重启会话)。
2. 本机复测(应返回 `i 0` 且 journal 无 "Can't find session"):
   ```bash
   H=$(busctl --user call org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet open sxs kdewallet 0 fix-verify | awk '{print $2}')
   busctl --user call org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet writePassword issss "$H" "Chrome Keys" "fix-verify-probe" "x" fix-verify
   journalctl --user -n 5 --no-pager | rg 'Can.t find session'
   busctl --user call org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet removeEntry issss "$H" "Chrome Keys" "fix-verify-probe" fix-verify
   ```
3. 通过后撤除绕过:
   - 删 `~/.vscode/argv.json` 中 password-store 行(含注释块)
   - `sd -- '--password-store=gnome-libsecret' ''` 清理 `~/.local/share/applications/`
     下 5 个浏览器主 .desktop + chrome-*-Default.desktop PWA(注意 Chrome 可能新生成
     不带 flag 的 PWA 文件,清理时以 rg 实际命中为准)
   - `kbuildsycoca6` + `update-desktop-database`
   - **git helper 建议保留**:Ubuntu 本就不编译 git-credential-libsecret,该 helper
     独立于本 bug 有长期价值;如坚持还原,删 `~/.gitconfig` 的 [credential] 段即可
     (GitHub 的 gh auth 条目从未动过)。
4. 重启 VSCode/浏览器验证:Settings Sync 正常、浏览器重启后登录态保持
   (撤 flag 后首轮可能又需重登一次——密钥换回 kwallet 后端)。
5. 更新本档案 + memory(kwallet-624-writepassword-regression),可停用 timer:
   `systemctl --user disable --now kwallet-upstream-watch.timer`。

## 回退

删除 argv.json 中该行并重启 VSCode 即恢复默认 detect 行为(kwallet bug 未修复前会复发);
git 侧删除 ~/.gitconfig 的 [credential] 段或 helper 行;浏览器侧从各 .desktop 的 Exec
移除 `--password-store=gnome-libsecret`。
