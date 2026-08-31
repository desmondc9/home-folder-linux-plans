# sing-box / tproxy 知识库整理 → ~/Notebook — 实施记录

日期: 2026-08-22 · 设计: [spec.md](spec.md)

## 任务清单

- [x] 通读源档案：`2026-08-18-2224-tailnet-exit-singbox/`（design/implementation/README/deploy 全部实体）+ frp / DERP / redroid 档案的关联条目 + 记忆 `moonlight-sunshine-tailscale-setup` 增补章节
- [x] 参照 `2026-08-21-1511-sunshine-notebook/` 确定结构与约定（frontmatter + wikilink + 证据链留 plans）
- [x] 写入 `~/Notebook/sing-box-分流网关/` 7 个笔记（MOC + 6 主题）
- [x] 跨域链接：Sunshine MOC "相关笔记"行改为 `[[00-sing-box-分流网关-MOC]]`
- [x] 验证 wikilink：vault 内 13 个链接全部可解析，0 断链
- [x] 敏感扫描：rg 无 UUID/私钥/token/密码命中；gitleaks v8.30.1（新装 `~/.local/bin/gitleaks`）扫描通过
- [x] 本档案（spec.md + implementation.md）归档
- [x] README 任务索引补齐：新增本行 + 08-19 以来缺失的 11 行（dockur / headscale-custom-derp / sunshine-display-switch / redroid / redroid-backup / sunshine-dpms-off-fix / windows11-vm-backup / hdmi-frl / binderfs-race / sunshine-notebook / kscreen-doctor）

## 产出

```
~/Notebook/sing-box-分流网关/          (未 git init, 与 Sunshine 域同约定)
├── 00-sing-box-分流网关-MOC.md
├── 01-架构总览-双Exit与分流.md
├── 02-sing-box-配置详解.md
├── 03-TPROXY-透明代理机制.md
├── 04-DNS-分流与防污染.md
├── 05-部署与运维手册.md
└── 06-深坑清单.md
```

## 验证

| 项 | 结果 |
|---|---|
| 笔记文件数 | 7/7 ✅ |
| wikilink 断链 | 0（域内 7 + 跨域 Sunshine 6 全部解析）✅ |
| 敏感信息 | 无（`<VLESS-UUID>`/`<REALITY-PUBLIC-KEY>` 占位符沿用源档案约定，真实值位置已注明）✅ |
| gitleaks | `gitleaks dir` 工作区 0 泄漏 ✅ |

## 决策与备注

- **~/Notebook 不做 git init**：沿用 Sunshine 域决策（未来可能混入其他域内容）；变更记录留在本 ~/plans 档案
- **跨域双向链接**：sing-box MOC ↔ Sunshine MOC 用 wikilink 互指，替换原纯文本 plans 路径（路径保留在"原始档案"节）
- **tproxy 域与 Sunshine 域边界**：headscale/DERP/frp 本体知识不搬入本域，仅在笔记中引用（"与周边基础设施的关系"节）——避免两域笔记内容重复漂移
- **README 索引缺口**：08-19 之后各任务只归档了目录、未更新索引表（含 sunshine-notebook 自身），本次一并补齐 11 行
- 迁移教训可复用：下次整理其他域（如 headscale/DERP、redroid）照抄本范式即可——已写入记忆 `singbox-notebook`
