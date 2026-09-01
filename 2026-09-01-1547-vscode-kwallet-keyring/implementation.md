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

## 回退

删除 argv.json 中该行并重启 VSCode 即恢复默认 detect 行为(kwallet bug 未修复前会复发);
git 侧删除 ~/.gitconfig 的 [credential] 段或 helper 行;浏览器侧从各 .desktop 的 Exec
移除 `--password-store=gnome-libsecret`。
