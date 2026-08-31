# Sunshine/Moonlight 知识库整理 → ~/Notebook

日期: 2026-08-21

## 任务

把 ~/plans 中四个 Sunshine/Moonlight 档案（08-18 tailnet / 08-19 display-switch / 08-20 dpms-off / 08-21 frl-blank）
按主题重组为 Obsidian 风格知识库，放入 ~/Notebook/ 供未来 Obsidian 挂载查看。

## 产出

```
~/Notebook/Sunshine-Moonlight-串流/
├── 00-Sunshine-Moonlight-串流-MOC.md    # 总索引 + 体系速览 + 运维速查
├── 01-网络架构-Tailnet-与-frp.md        # 双链路、端口表、配对合并
├── 02-Sunshine-主机端配置与工具.md      # 服务形态、output_name、切换/演练脚本
├── 03-屏幕电源与唤醒体系.md             # 三态语义、唤醒 daemon、watchdog、4K@60
├── 04-Moonlight-客户端使用技巧.md       # 配对、OSK、锁屏输密码
├── 05-故障模式诊断手册.md               # 症状→根因→处置速查表
└── 06-深坑清单.md                       # 15 条血泪教训
```

- 约定: YAML frontmatter(tags/created/source) + `[[wikilink]]` 双向链接;不复制证据链,证据留在 ~/plans 原始档案,笔记里以 source 字段指回
- 验证: 7 个文件、全部 wikilink 0 断链
- 敏感检查: 四份源档案 gitleaks/rg 扫描无 token/password

## 决策

- ~/Notebook 不做 git init(用户未要求,未来可能混入其他域内容);本档案留在 ~/plans 记录变更
- 文件名带数字前缀 + 中文: Obsidian 内排序稳定、MOC 可读
