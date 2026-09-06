# 实施记录 — GitHub token 五端配置

## 任务

- [x] 摸底:gh 2.99.0 未登录 / git 无凭证助手 / openclaw GitHub identity 未配置
- [x] 读 wizard skill(template.sh 库 + 编写规程)
- [x] 核实 openclaw CLI 语法(store set 的 --value-file/-stdin 与 --allow-host;config set 的 ref 构建模式)
- [x] 生成向导 ~/.local/bin/github-token-wizard.sh(4 stage),bash -n 通过,chmod +x
- [ ] owner 运行向导(唯一人工步骤:终端里掩码粘贴一次 token)
- [ ] agent 端到端复核(github_identity_status / agent 侧 gh 验证)

## 反馈回路

- wizard 内建:每步 ✓/⚠ 即时反馈,失败项进 SKIPPED 汇总
- 复核命令:`gh auth status`;`github_identity_status`(openclaw 侧);`openclaw config get gateway.controlUi.github.token`(应显示 ref 非明文)

## 步骤与结果

1. 环境摸底(exec + github_identity_status 工具):三处均未配置,gh/git 已装。
2. 方案:终端 wizard(wizard skill 规程),token 只在 owner 终端出现;四 agent 走
   gh+git credential helper,openclaw 走 secrets store + SecretRef。
3. CLI 语法核实后成稿向导:Stage1 建/贴 PAT(浏览器链接预填 repo+workflow scopes)→
   Stage2 store+config(失败不阻塞后续)→ Stage3 gh login+setup-git → Stage4 验证
   (gh api user 显示账号)+ confirm 门控的 gateway 重启。
4. bash -n 通过(shellcheck 未安装);向导属 ephemeral 产物,owner 跑完可删。

## 证据留存

- `bash -n` OK;文件权限 -rwxrwxr-x
- 等待 owner 运行;运行结果回填本节(验收标准见 spec.md)

## 清理

- 向导脚本用后即删(rm ~/.local/bin/github-token-wizard.sh),不留凭证相关脚本

---

## 验收回填(2026-09-03 10:48,owner 跑完向导后 agent 复核)

- [x] owner 运行向导完成;接受了 confirm 门控的 gateway 重启(新 pid 10:47)
- [x] `gh auth status`:已登录 desmondc9,https 协议;token scopes 完整含 repo/workflow
      (owner 复用了既有宽权限 token,未按向导建议建最小权限——可用,但爆炸半径大,
       建议日后换最小 scoped token,向导重跑即可)
- [x] `gh api user` → {"login":"desmondc9","name":"Desmond Chen"}(与 agent 同款 shell 凭证链验证)
- [x] git credential helper → `!/usr/bin/gh auth git-credential`(github.com + gist.github.com),
      四 agent(opencode/kimi/pi/claude)git HTTPS 操作全部继承
- [x] `openclaw config get gateway.controlUi.github.token` → SecretRef(store/default,值已脱敏显示),
      openclaw.json 无明文;gateway 已重启,Control UI GitHub 功能生效
- [x] `github_identity_status`:credentialState unavailable → **available**,account=desmondc9,
      evidence=github-api(agent scope 的 selected=false 仅表示无显式 identity 覆盖,系统级凭证已就绪)

**结论:五端全部打通,验收标准全部满足。**
