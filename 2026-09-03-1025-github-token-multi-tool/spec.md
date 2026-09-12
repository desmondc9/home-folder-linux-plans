# GitHub token 五端配置(openclaw + opencode/kimi/pi/claude)

- 日期: 2026-09-03
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)
- 状态: 向导已生成待运行(owner 在终端粘贴一次 token 即完成;token 不经聊天)

## 背景与目标

owner 要求配置一个 GitHub token,使 openclaw 与四个 coding agent(opencode / kimi code /
pi / claude)都能使用。现状:gh 2.99.0 已装未登录;git 无 credential helper;
openclaw 侧 GitHub identity 未配置(doctor #12 + 本档案 Follow-up #2 的遗留)。

## 关键决策与理由

| 决策 | 理由 |
|---|---|
| 终端 wizard 收 token(掩码 read -rs),拒绝聊天传递 | 凭证永不进入聊天记录/agent transcript;wizard skill 正是此场景设计 |
| 四 agent 共用 gh + `gh auth setup-git` | coding agent 的 GitHub 操作都走 shell 里的 gh/git;凭证助手一次配置全局生效,无需给每个 agent 单独配 |
| openclaw 侧走 secrets store + SecretRef | 与 09-02 既定模式一致:openclaw.json 不落明文;`--allow-host api.github.com/github.com` 限定替换面 |
| classic PAT(repo+workflow),链接预填参数 | 对 agent 场景最简单可靠;fine-grained 也可(向导里有说明) |

## 最终配置快照(wizard 运行后达成)

```
~/.local/bin/github-token-wizard.sh        # 一次性向导,跑完可删
secrets store: GITHUB_TOKEN (kind=secret, allow-host: api.github.com, github.com)
openclaw.json: gateway.controlUi.github.token → SecretRef(store/GITHUB_TOKEN)
gh: auth login --with-token + auth setup-git (git credential helper → gh)
生效: gateway 重启后 Control UI GitHub 功能可用
```

## 排障知识点(复用价值)

- `openclaw secrets store set --kind secret --value-file - --allow-host <host> <NAME>` 支持stdin
  管道喂值;`config set <path> --ref-provider default --ref-source store --ref-id <NAME>` 为
  ref 构建模式(帮助示例即此形态)。
- 四 agent 共享认证的正确层次:gh keyring + git credential helper(过程级),不要靠 export
  GH_TOKEN 环境变量(systemd 环境/非交互 shell 不会继承 rc 文件的 export)。

## 验收标准

- wizard 内: `gh api user` 返回账号;`gh auth status` 显示 token scopes
- agent 侧(待 wizard 完成后复核): `github_identity_status` 变 configured;任一 agent
  `gh api user` / `git ls-remote` 私有仓可达

## Follow-ups

- owner 运行向导后由 agent 做端到端复核 + 本档案 implementation 补验收记录
- token 到期前在 GitHub 续期后重跑向导即可(各处写入均为幂等 upsert)
