# Sunshine/Moonlight 知识库整理 → ~/Notebook — 设计

日期: 2026-08-21 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)

> **补记说明**:本 spec 于 2026-08-31 依据 [implementation.md](implementation.md)、`~/Notebook/Sunshine-Moonlight-串流/` 实际产出与四份源档案**事后补写**,以补齐 `~/CLAUDE.md` 要求的 spec + implementation 双文档。内容均可从上述证据复原,未凭记忆杜撰;无法从证据确定的部分已在文中标注。

## 背景与目标

到 2026-08-21 为止,Sunshine/Moonlight 串流这一个主题的知识已经散落在 `~/plans` 的**四份按日档案**里:

| 档案 | 贡献的知识 |
|---|---|
| [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/) | tailnet 主链路 + frp 备份链路的双冗余网络架构、端口矩阵、配对 |
| [../2026-08-19-1633-sunshine-display-switch/](../2026-08-19-1633-sunshine-display-switch/) | `output_name` 只认数字、显示器切换脚本 |
| [../2026-08-20-2127-sunshine-dpms-off-fix/](../2026-08-20-2127-sunshine-dpms-off-fix/) | RTSP 500/503 根因 = PowerDevil DPMS 关屏杀 KMS 抓屏 |
| [../2026-08-21-1016-hdmi-frl-screen-blank/](../2026-08-21-1016-hdmi-frl-screen-blank/) | HDMI FRL 黑屏、4K@60 相关 |

按日期归档对「做过什么、为什么」很好用,但对「**这个主题现在是什么状态、出问题怎么查**」很差:同一个症状的根因可能横跨三份档案,而档案按时间而非按主题组织。

目标:把这四份档案的**结论层**按主题重组为 Obsidian 风格知识库,放入 `~/Notebook/` 供未来挂载 Obsidian 查看,同时**不动原始按日档案**——证据链留在原地,笔记只做主题化索引与提炼。

**本任务同时是范式试点**:`~/Notebook` 此前不存在,这是第一个域。此处确定的目录结构、frontmatter 约定、wikilink 规则将作为后续域的模板(事实上 [../2026-08-22-1024-singbox-notebook/](../2026-08-22-1024-singbox-notebook/) 与 [../2026-08-22-1130-tailscale-notebook/](../2026-08-22-1130-tailscale-notebook/) 均声明「完全复用本域既定范式」)。

## 范围

**In scope:**

- 上表四份档案中**已确认的结论**:架构、配置、脚本、症状→根因映射、教训
- `~/Notebook/Sunshine-Moonlight-串流/` 的目录结构与文档约定(作为后续域的模板)

**Out of scope:**

- **对四份原始档案做任何删改** —— 证据链原地保留,笔记以 `source` 字段指回
- 复制证据链本身(命令输出、日志片段、排查过程)到笔记里 —— 笔记只放结论
- `~/Notebook` 的 git 化(见「关键决策」)
- Sunshine 之外的域(sing-box / tailnet 当时尚未整理)

## 方案

### 目录结构

```
~/Notebook/Sunshine-Moonlight-串流/
├── 00-Sunshine-Moonlight-串流-MOC.md    # 总索引 + 体系速览 + 运维速查 + 原始档案指引
├── 01-网络架构-Tailnet-与-frp.md        # 双链路、端口表、配对合并
├── 02-Sunshine-主机端配置与工具.md      # 服务形态、output_name、切换/演练脚本
├── 03-屏幕电源与唤醒体系.md             # 三态语义、唤醒 daemon、watchdog、4K@60
├── 04-Moonlight-客户端使用技巧.md       # 配对、OSK、锁屏输密码
├── 05-故障模式诊断手册.md               # 症状 → 根因 → 处置速查表
└── 06-深坑清单.md                       # 血泪教训汇总(按类分区)
```

### 文档约定

- **YAML frontmatter**:`tags` / `created` / `source`,其中 `source` 指回 `~/plans` 的原始档案路径
- **`[[wikilink]]` 双向链接**:笔记之间互链,Obsidian 里可走图谱
- **文件名 = 数字前缀 + 中文**:Obsidian 内排序稳定,MOC 里可读
- **不复制证据链**:笔记只承载结论;要看「怎么查出来的」顺 `source` 回原档案

### 组织原则

按**使用场景**而非按来源档案切分。四份档案里关于「屏幕电源」的内容分散在 08-20 和 08-21 两处,合并进 `03-屏幕电源与唤醒体系.md`;`05-故障模式诊断手册.md` 则是横切所有档案的「症状 → 根因」速查表——这正是按日归档给不了的东西。

## 关键决策

1. **`~/Notebook` 不做 git init** —— 用户当时未要求,且未来可能混入其他域的内容,先不定型。本档案留在 `~/plans` 记录变更。
   *(后续演变:2026-08-22 该目录已 git init 并推送到 `github.com/desmondc9/notebook`(private),见 [../2026-08-22-1155-notebook-readme/](../2026-08-22-1155-notebook-readme/)。)*
2. **文件名用数字前缀 + 中文**,而非纯英文 slug —— Obsidian 侧排序稳定且 MOC 可读性更好。
3. **笔记与档案分工**:`~/plans` 是「按日的证据链」,`~/Notebook` 是「按主题的结论」。两者不互相取代,笔记不复制证据。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 笔记与原始档案随时间脱节 | `source` frontmatter 指回原档案;新任务若修改结论需同步更新对应笔记(后续任务确实这么做了,见下) |
| 笔记里混入机密(token / 密码) | 提交前对四份源档案与产出笔记做 gitleaks / rg 扫描 |
| wikilink 写错导致 Obsidian 图谱断裂 | 产出后逐条校验,要求 0 断链 |

## 验收标准

- [x] `~/Notebook/Sunshine-Moonlight-串流/` 下 **7 个文件**(1 MOC + 6 主题笔记)
- [x] 全部 wikilink **0 断链**
- [x] 每个文件有 `source` frontmatter 指回 `~/plans` 原始档案
- [x] 四份源档案与产出笔记 gitleaks / rg 扫描**无 token / password**
- [x] 四份原始档案未被改动

## 后续演变(补记时观察到,非本任务范围)

- **2026-08-22 [../2026-08-22-0908-kscreen-doctor-crash-loop/](../2026-08-22-0908-kscreen-doctor-crash-loop/) 增补了本域笔记**:`06-深坑清单.md` 新增「systemd 类」分区(第 13–15 条,内文标注「2026-08-22 实测」),`00-MOC` / `03-屏幕电源与唤醒体系` / `05-故障模式诊断手册` 同步更新,`source` 字段增列该档案为第五个来源。
  *(注:implementation.md 记的「15 条」与该分区的 08-22 日期存在出入 —— Notebook 当时尚未 git init,无法从历史判定 08-21 当天的确切条数。这里如实标注,不做推测。)*
- **2026-08-22** 本域范式被 sing-box 与 tailnet 两个域完整复用,`~/Notebook` 完成 git 化并加了纵览 README。

## 参考

- 源档案:见「背景与目标」表格中的四份
- 复用本范式的后续任务:[../2026-08-22-1024-singbox-notebook/](../2026-08-22-1024-singbox-notebook/)、[../2026-08-22-1130-tailscale-notebook/](../2026-08-22-1130-tailscale-notebook/)、[../2026-08-22-1155-notebook-readme/](../2026-08-22-1155-notebook-readme/)
- 相关记忆:`sunshine-knowledge-notebook`
