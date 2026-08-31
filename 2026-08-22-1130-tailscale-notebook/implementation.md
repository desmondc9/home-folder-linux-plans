# tailscale / headscale / DERP 知识库整理 → ~/Notebook — 实施记录

日期: 2026-08-22 · 设计: [spec.md](spec.md)

## 任务清单

- [x] 通读源档案：`2026-08-19-1302-sunshine-moonlight-tailnet/`（design+implementation）、`2026-08-19-1430-headscale-custom-derp/`（design+implementation 含全部配置实体）、`2026-08-18-2224-tailnet-exit-singbox/`（design+README+implementation 的 tailnet 部分）、`2026-08-19-1420-frp-config-archive/`、`2026-08-19-1414-cloudflare-zerotrust-removal/` 关联条目 + 记忆 `moonlight-sunshine-tailscale-setup`
- [x] 参照 `2026-08-21-1511-sunshine-notebook/`、`2026-08-22-1024-singbox-notebook/` 确定结构与约定（frontmatter + wikilink + 证据链留 plans + 机密红线）
- [x] 写入 `~/Notebook/Tailscale-Headscale-DERP/` 8 个笔记（MOC + 7 主题）
- [x] 跨域链接：Sunshine MOC / Sunshine 01 / sing-box MOC 的"相关笔记"行加新 MOC wikilink；sing-box 深坑清单 #7/#8/#12/#13 加"本体见新 MOC"指针
- [x] 验证 wikilink：vault 内 126 个链接全部可解析、0 断链；新域 0 新歧义（既有的 15 条 `[[06-深坑清单]]` 短名歧义为 Sunshine/sing-box 域内既有现象，Obsidian 同目录优先解析，行为正确，未动）
- [x] 敏感扫描：rg 无 UUID/私钥/token/密码/authkey 值命中；gitleaks v8.30.1 `dir .` 0 泄漏（Notebook 工作区 104KB）
- [x] 本档案（spec.md + implementation.md）归档
- [x] README 任务索引补行
- [x] `~/Notebook` commit（新域 8 笔记 + 跨域链接更新；push 待用户确认）
- [x] `~/plans` 归档 commit + push（本 commit）

## 产出

```
~/Notebook/Tailscale-Headscale-DERP/     (私有 git 仓库 github.com/desmondc9/notebook 内)
├── 00-Tailscale-Headscale-DERP-MOC.md
├── 01-架构总览-双链路与双出口.md
├── 02-Headscale-控制面部署.md
├── 03-节点接入-客户端与P2P打洞.md
├── 04-DERP-中继部署.md
├── 05-Exit-Node-出口节点.md
├── 06-运维手册与故障速查.md
└── 07-深坑清单.md
```

## 验证

| 项 | 结果 |
|---|---|
| 笔记文件数 | 8/8 ✅ |
| wikilink 断链 | 0（全 vault 126 个链接全部解析，含跨域与路径限定形式）✅ |
| 新引入歧义链接 | 0（15 条既有 `06-深坑清单` 短名歧义未新增）✅ |
| 敏感信息 | 无（预授权密钥只记命令不记值；凭据只写路径；占位符沿用源档案约定）✅ |
| gitleaks | Notebook 工作区 0 泄漏 ✅ |

## 决策与备注

- **域命名**：用用户原话三关键词 `Tailscale-Headscale-DERP`，目录与 MOC 同名
- **笔记数为 MOC+7（比既有两域多 1）**：headscale 控制面、节点接入、DERP、出口节点四个主题各自独立成文后仍多出"运维手册"，内容量不允许并入深坑清单
- **frp 本体不搬入**：沿用 singbox-notebook 决策（frp 配置实体留在 `2026-08-19-1420-frp-config-archive/`），本域只在架构总览与深坑清单交叉引用
- **Notebook git 状态与既有档案的说法差异**：`2026-08-22-1024-singbox-notebook/spec.md` 写"~/Notebook 不入 git"，该决策已于同日被用户要求推翻（初始导入 commit 9d08edc，private github.com/desmondc9/notebook，经 10809 代理 push）；本档案如实记录当前状态
- **迁移教训可复用**：下次整理其他域（如 redroid、Wine）照抄本范式即可——已写入记忆 `tailnet-notebook`
