# VSCode Settings Sync 报 "OS keyring is not available" — 根因分析与修复

- 日期:2026-09-01
- 环境:Kubuntu 26.04(resolute)+ KDE Plasma 6 + Wayland;kwallet6 6.24.0-0ubuntu1(ksecretd + kwalletd6 拆分架构);VSCode 1.135.0(.deb,apt 源)

## 现象

VSCode Settings Sync 弹错:
`You're running in a KDE environment but the OS keyring is not available for encryption. Ensure you have kwallet running.`
并指向 https://code.visualstudio.com/docs/configure/settings-sync#_troubleshooting-keychain-issues

## 排查过程(systematic-debugging)

1. **系统层全部正常**:
   - kwalletd6(pid 随 session 启动)注册 `org.kde.kwalletd{,5,6}`,`/modules/kwalletd6` 提供 `org.kde.KWallet`;
   - 新架构下 `org.freedesktop.secrets` 由 **ksecretd**(kwallet6 包内新守护进程,PAM 登录启动)持有;
   - `isEnabled`=true,`isOpen(kdewallet)`=true,钱包文件活跃;
   - python-gi libsecret roundtrip(store/lookup/clear)全部成功 → **Secret Service 链路健康**。
2. **VSCode 侧**:对照 `--verbose` trace,默认配置下
   `[EncryptionMainService] Encryption is available: false` → in-memory 回退。
   源码(1.135.0)链路:`safeStorage.isEncryptionAvailable()`(Chromium os_crypt)失败;`getSelectedStorageBackend()`=kwallet 系 → 弹出 KDE 版错误文案。
3. **决定性证据**(journalctl --user):google-chrome-beta 同日同样失败:
   - `freedesktop_secret_key_provider.cc:777 Existing KWallet password is empty. Generating a new one.`
   - `freedesktop_secret_key_provider.cc:809 KWallet writePassword failed with code: -1`
   - 同秒 kwalletd6 日志 `"Can't find session /org/freedesktop/secrets/session/1"`
4. **D-Bus 复刻复现**:`open`→有效句柄 ✓、`hasFolder "Chrome Keys"`→true ✓、
   `writePassword`→ **-1 ✗**,同时 kwalletd6 打出同一条 "Can't find session"。

## 根因

kwallet 6.24 把 Secret Service(`org.freedesktop.secrets`)拆给新进程 ksecretd,但
kwalletd6 的经典 `org.kde.KWallet.writePassword` 内部仍引用只存在于 ksecretd 侧的
secrets session → **KWallet API 的密码写入全部失败(-1)**。
Chromium 系(VSCode/Electron、Chrome)在 KDE 桌面默认选 KWallet 后端 → os_crypt 密钥
无法持久化 → `isEncryptionAvailable()`=false → Settings Sync 报 keyring 不可用。

上游状态:`apt-cache policy kwallet6` 无修复版本(6.24.0-0ubuntu1 唯一候选)。

## 修复方案

强制 VSCode 走健康的 Secret Service(ksecretd)路径:`~/.vscode/argv.json` 增加
`"password-store": "gnome-libsecret"`(VSCode 官方 troubleshooting 文档推荐做法)。

## 验收标准

- 测试实例(独立 user-data-dir)`--verbose` 下 trace 显示
  `[EncryptionMainService] Encryption is available: true` 且
  `[SecretStorageService] using persisted storage`;
- 仅靠 argv.json(不带 CLI 参数)同样生效;
- 正式窗口重启后 Settings Sync 不再弹错、可正常同步。

## 已知副作用

- 加密密钥后端切换后,旧密钥加密的存量 secrets 解密失败会被 VSCode 自动清除 →
  Settings Sync 需**一次性重新登录**。
- Chrome/Edge/Chromium 同受此 bug 影响(Chrome-beta 日志证实);浏览器侧同样可加
  `--password-store=gnome-libsecret`,但会引起 cookie/密码重加密,代价自担,本次未动。
