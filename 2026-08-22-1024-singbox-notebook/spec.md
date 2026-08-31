# sing-box / tproxy 知识库整理 → ~/Notebook — 设计

日期: 2026-08-22 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)

## 背景与目标

`~/plans/` 中 sing-box 分流网关与 TPROXY 透明代理的知识分散在多个按日档案里（主线档案 [../2026-08-18-2224-tailnet-exit-singbox/](../2026-08-18-2224-tailnet-exit-singbox/)，以及 frp / DERP / redroid 档案中的关联条目）。按日期检索效率低，且其中包含大量硬核排障经验（martian source、TPROXY 回环黑洞、netavark MTU 坑）值得主题化沉淀。

目标：把这些知识按主题重组为 Obsidian 风格知识库放入 `~/Notebook/`，供未来挂载 Obsidian 查看——完全复用 2026-08-21 Sunshine 域的既定范式（[../2026-08-21-1511-sunshine-notebook/](../2026-08-21-1511-sunshine-notebook/)）。

## 范围

**In scope:**

- `2026-08-18-2224-tailnet-exit-singbox/` 全部内容（design / implementation / deploy 快照）——主线
- `2026-08-19-1420-frp-config-archive/` 中与 sing-box 的耦合点（custom-direct 控制面直连行）
- `2026-08-19-1430-headscale-custom-derp/` 的关联（控制面直连豁免）
- `2026-08-20-1252-redroid-android-container/` 中 tproxy 表 100 引发的 netavark MTU 坑
- 记忆 `moonlight-sunshine-tailscale-setup` 中的 sing-box 增补章节（QUIC block 目的、headscale DNS 配合、VPS 出口自救坑）

**Out of scope:**

- headscale / DERP / Sunshine / frp 本体的知识（属于 Sunshine 域笔记和各自档案）
- 对原始按日档案做任何删除或改动（证据链原地保留）

## 方案

### 目录结构（镜像 Sunshine 域范式）

```
~/Notebook/sing-box-分流网关/
├── 00-sing-box-分流网关-MOC.md    # 总索引 + 体系速览 + 运维速查 + 原始档案
├── 01-架构总览-双Exit与分流.md     # 背景、架构图、关键设计决策、与周边设施关系、验收标准
├── 02-sing-box-配置详解.md        # config.json 逐段解读、rule-set、自定义规则、升级流程
├── 03-TPROXY-透明代理机制.md      # nftables/策略路由、防回环、两大修复档案、验证工具
├── 04-DNS-分流与防污染.md         # resolved→223.5.5.5→sing-box 全链路、坑、验证
├── 05-部署与运维手册.md           # 部署清单、服务形态、Exit Node、健康检查/回退/日志
└── 06-深坑清单.md                 # 13 条血泪教训（含跨域 netavark MTU 坑）
```

### 约定（沿用 Sunshine 域既定约定）

- YAML frontmatter（title/tags/created/source）+ `[[wikilink]]` 双向链接；source 字段指回 `~/plans` 原始档案，**不复制证据链**
- 文件名数字前缀 + 中文：Obsidian 内排序稳定
- 双向跨域链接：sing-box MOC ↔ Sunshine MOC（对方 MOC 的"相关笔记"行同步改为 wikilink）
- 机密红线：笔记内不出现任何 UUID / 私钥 / token / 密码，敏感字段沿用占位符并在文中注明真实值位置（`/etc/sing-box/config.json`）；基础设施信息（IP/端口/拓扑）按仓库规则允许保留

## 验收标准

1. 7 个笔记文件齐备，内容覆盖源档案全部主题
2. 全部 wikilink 可解析（vault 内 0 断链，含跨域）
3. 敏感扫描（rg + gitleaks）无泄漏
4. 本任务在 `~/plans` 归档并 commit；README 任务索引补齐（含 08-19 以来缺失的 11 行）

## 风险与缓解

- **笔记与线上配置漂移**：笔记注明"线上真实值以 /etc/sing-box/ 为准"，源档案是快照而非线上
- **公开仓库泄漏**：~/plans 为公开仓库，归档文件经 gitleaks 扫描后才 commit；~/Notebook 本身不入 git
- **索引补行准确性**：11 条缺失索引行按记忆与档案摘要补写，仅一行式主题描述，不展开细节
