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

## 回退

删除 argv.json 中该行并重启 VSCode 即恢复默认 detect 行为(kwallet bug 未修复前会复发)。
