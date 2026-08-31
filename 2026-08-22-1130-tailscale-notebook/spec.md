# tailscale / headscale / DERP 知识库整理 → ~/Notebook — 设计

日期: 2026-08-22 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)

## 背景与目标

`~/plans/` 中 tailscale / headscale / DERP 的组网知识分散在多个按日档案里（主线 [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/)、独立 derper 档案 [../2026-08-19-1430-headscale-custom-derp/](../2026-08-19-1430-headscale-custom-derp/)、双出口档案 [../2026-08-18-2224-tailnet-exit-singbox/](../2026-08-18-2224-tailnet-exit-singbox/)，以及 frp / CF 档案的关联条目）。按日期检索效率低，且其中包含大量硬核排障经验（martian source、derper 四坑、iOS 出口列表空白、VPS 自指出口坑）值得主题化沉淀。

目标：把这些知识按主题重组为 Obsidian 风格知识库放入 `~/Notebook/`，供未来挂载 Obsidian 查看——完全复用 2026-08-21 Sunshine 域、2026-08-22 sing-box 域的既定范式。

## 范围

**In scope:**

- `2026-08-19-1302-sunshine-moonlight-tailnet/` 全部 tailnet 内容（headscale 部署、三节点接入、IPv6 P2P、内嵌 DERP、frp 双链路拓扑）
- `2026-08-19-1430-headscale-custom-derp/` 全部内容（独立 derper 998 部署实体与四坑）
- `2026-08-18-2224-tailnet-exit-singbox/` 的 tailnet 部分（双 Exit Node、headscale 批准流程、iOS suggest-exit-node / NAT64 修复、VPS 自救坑）
- `2026-08-19-1414-cloudflare-zerotrust-removal/` 的 CF DNS 记录清单与灰云原则
- 记忆 `moonlight-sunshine-tailscale-setup` 中的 tailnet 章节（VPS AAAA 裸地址坑、凭据路径）

**Out of scope:**

- sing-box 分流本体（已属 sing-box 域笔记，本域只交叉引用）
- frp 配置本体（留在 `2026-08-19-1420-frp-config-archive/`，本域只交叉引用拓扑关系）
- Sunshine 串流侧视角（已属 Sunshine 域笔记）
- 对原始按日档案做任何删除或改动（证据链原地保留）

## 方案

### 目录结构（镜像既有域范式）

```
~/Notebook/Tailscale-Headscale-DERP/
├── 00-Tailscale-Headscale-DERP-MOC.md   # 总索引 + 体系速览 + 运维速查 + 原始档案
├── 01-架构总览-双链路与双出口.md          # 硬约束、拓扑、节点清单、关键设计决策、与周边设施关系
├── 02-Headscale-控制面部署.md            # nginx/LE、config 关键项、用户/预授权密钥、CLI、policy.hujson
├── 03-节点接入-客户端与P2P打洞.md         # 接入三步、IPv6 P2P 原理、iOS VPN 互斥守则
├── 04-DERP-中继部署.md                  # 998 独立 + 999 内嵌、全部部署实体、四大坑、验证升级
├── 05-Exit-Node-出口节点.md             # 双出口开通流程、iOS 两 bug、VPS 自救坑、客户端守则
├── 06-运维手册与故障速查.md              # 速查命令、救援矩阵、CF DNS 表、健康检查、升级回退
└── 07-深坑清单.md                       # 13 条血泪教训（含跨域索引与红线事故提醒）
```

### 约定（沿用既有域约定）

- YAML frontmatter（title/tags/created/source）+ `[[wikilink]]` 双向链接；source 字段指回 `~/plans` 原始档案，**不复制证据链**
- 文件名数字前缀 + 中文：Obsidian 内排序稳定
- 三方双向跨域链接：新域 MOC ↔ Sunshine MOC ↔ sing-box MOC（对方 MOC 的"相关笔记"行同步改为 wikilink；sing-box 深坑清单中 4 条 tailnet 本体条目加"本体见新 MOC"指针）
- wikilink 歧义规避：`06-深坑清单` 短名在 Sunshine/sing-box 两域已重名，本域深坑笔记命名为 `07-深坑清单`；跨域引用重名笔记一律用路径限定形式 `[[<目录>/<文件名>|别名]]`（表格内 `\|` 转义）
- 机密红线：笔记内不出现任何 token / 密码 / 私钥 / 预授权密钥，敏感值沿用占位符并注明真实位置；凭据只写路径（`~/.bandwagon/credentials.jsonc` 等）；基础设施信息（IP/端口/拓扑）按仓库规则允许保留

## 验收标准

1. 8 个笔记文件齐备，内容覆盖源档案全部 tailnet 主题
2. 全部 wikilink 可解析（vault 内 0 断链，含跨域）；新域不引入新的短名歧义
3. 敏感扫描（rg + gitleaks）无泄漏
4. 本任务在 `~/plans` 归档并 commit；README 任务索引补行
5. `~/Notebook` 作为 git 仓库 commit 新域（push 待用户确认）

## 风险与缓解

- **笔记与线上配置漂移**：笔记注明"线上真实值以 /etc/headscale/ 等为准"，源档案是快照而非线上
- **跨域内容重复漂移**：headscale/DERP/frp 本体只在本域出现，sing-box/Sunshine 域保留引用指针；兄弟域新增内容时优先在本域更新
- **公开仓库泄漏**：~/plans 为公开仓库，归档文件经 gitleaks 扫描后才 commit；~/Notebook 为私有仓库但同一红线标准
