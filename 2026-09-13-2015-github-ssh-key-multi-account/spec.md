# GitHub 添加 SSH key 报 "Key is already in use"(公钥全局唯一/双账号隔离)

- 日期:2026-09-13 20:15
- 环境:macOS 26.6.2(MacBook,karina@Mac);GitHub 账号 desmondc9 / karirichen;gh CLI 已登录 karirichen(token 含 `admin:public_key`)
- 类型:本机 SSH 凭据/配置修复(无 repo 代码变更,无 PR)
- 状态:已修复并验证(双路 `ssh -T` 各自问候正确账号)

## 背景

在 karirichen 账号的 GitHub 网页添加 `~/.ssh/id_rsa.pub` 时报
`Key is already in use`,但该账号 Settings → SSH keys 列表为空——
"没有任何 key,却说 key 已被占用"。

## 诊断(diagnosing-bugs:先建反馈环再谈假设)

反馈环一条命令直指占用者(强制用指定 key、禁用 agent 干扰):

```bash
ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com
# → Hi desmondc9! You've successfully authenticated, but GitHub does not provide shell access.
```

问候语形态即判定结论:

- `Hi <user>!` → key 挂在账号 <user> 上
- `Hi <user>/<repo>!` → key 是 <repo> 的 deploy key(账号 SSH 列表不可见,是同款症状的另一常见根因)
- `Permission denied` → key 根本不在 GitHub 上(与 already in use 矛盾,可排除)

## 根因

GitHub 公钥**全局唯一**:一把公钥同一时刻只能挂在一个账号(或一个仓库的
deploy key)上。本机 `id_rsa`(karina@Mac,RSA 2048)早已注册在 **desmondc9**
账号,故 karirichen 添加时报 already in use;karirichen 自己的列表为空,
产生"没占用却报占用"的错觉。机制无 bug,是账号张冠李戴。

## 修复(用户选定:新账号新 key,两把 key 各守一账号)

```bash
ssh-keygen -t ed25519 -C "karirichen@Mac" -f ~/.ssh/id_ed25519_karirichen -N ""
gh ssh-key add ~/.ssh/id_ed25519_karirichen.pub -t "karirichen@Mac"   # 免浏览器
```

`~/.ssh/config` 追加别名(与既有 `Host github.com` 条目同构,含 10808 SOCKS5
代理行;`IdentitiesOnly yes` 防止 agent 乱喂 key):

```
Host github-karirichen
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_karirichen
    IdentitiesOnly yes
    ProxyCommand nc -X 5 -x 127.0.0.1:10808 %h %p
    ServerAliveInterval 30
    ServerAliveCountMax 5
```

既有 `git@github.com`(id_rsa → desmondc9)原样保留,零影响。

## 验证

```bash
ssh -T git@github.com          # → Hi desmondc9!
ssh -T github-karirichen       # → Hi karirichen!
```

## 遗留与教训

- karirichen 的仓库一律用 `git@github-karirichen:owner/repo.git`;已有仓库可
  `git remote set-url origin git@github-karirichen:owner/repo.git` 切换
- 新 key 未设 passphrase,需要时 `ssh-keygen -p -f ~/.ssh/id_ed25519_karirichen` 补加
- 诊断口诀:**报 already in use 先查 key 被谁占用,再谈修复**——网页端账号列表
  看不到 deploy key,`ssh -T` 问候语才是唯一权威信源
- `gh ssh-key add` 后的 signing-key 列举 404 只是缺 `admin:ssh_signing_key`
  scope 的警告,与 authentication key 无关,可忽略
- 同会话后续:本机 `~/plans` 由 home-folder-mac-plans 改追本仓库
  (home-folder-linux-plans,`git remote set-url` + `reset --hard origin/main`,
  原 4 个 mac commits 已 bundle 备份于 `~/plans-mac-plans-backup-20260913.bundle`)
