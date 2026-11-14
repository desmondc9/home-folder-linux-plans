# OpenCode 全局 AGENTS.md 审计与跨机器修复(第二次)

日期: 2026-11-14 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 前置任务: [2026-09-20-1542-opencode-global-agents-audit](../2026-09-20-1542-opencode-global-agents-audit/)(第一次审计,WSL2 机器)、[2026-11-14-1152-claude-code-removal](../2026-11-14-1152-claude-code-removal/)(AGENTS.md 由软链转实体文件的来源)

## 背景

Claude Code 清理后,`~/.config/opencode/AGENTS.md`(原 `~/.claude/CLAUDE.md` 软链,已转实体文件,47473 字节)成为 opencode 唯一全局指令源。用户要求体检并修复问题。

## 审计结论

**内容本身健康**:无 openclaw/claude code 残留引用(当日清理后已干净)、无 HTML 实体/编码损坏、V2 指引(AGENTS.md 优先、CLAUDE.md 兼容回退)正确。

**发现 2 个悬空引用,根因是指令文件跨机器共享**——同一份内容在 WSL2 桌面机(DESKTOP-J7NBNU4)与原生 Linux 服务器(brave-goose-1)间同步,而两个被引用资源只存在于桌面机:

| 引用 | 桌面机 | 本机(brave-goose-1) |
|---|---|---|
| `~/docs/network-access-china.md` | 存在 | **缺失**(已从 9-20 审计备份恢复) |
| `~/.azure-devops/credentials.jsonc` | 存在 | **整个 `~/.azure-devops/` 不存在** |
| `127.0.0.1:10809` 本地代理 | Windows 宿主 sing-box mixed 入站 | **连接拒绝**(本机 sing-box 是服务端角色,见 2026-10-29 迁移) |

本机网络实测:Google 直连 204,出口 IP 为本机 eth0(95.169.0.65)——**本机不受 GFW 约束,"中国大陆网络"章节对本机不适用**。

## 修复内容

1. **恢复 `~/docs/network-access-china.md`**:从 9-20 审计备份复制,SHA-256 与当年 MANIFEST 记录一致(`e3b47d5a…142ba`),字节无损。
2. **AGENTS.md 网络章节追加「Machine scope」**:明确 GFW 约束与 10809 代理仅适用于墙内有本地 sing-box 客户端的机器(WSL2 桌面);直连出口的服务器不需要;不确定时用 `curl -x http://127.0.0.1:10809 --max-time 5 https://api.ipify.org` 探测,拒绝则直连,不重试死端口。
3. **AGENTS.md Kanban 第 4 条改为条件式**:PAT 在则直接读(不问用户、不打印、不提交);不在则问用户,不得四处翻找凭据。

## 验收标准

- [x] AGENTS.md 中全部 `~/docs/*.md` 引用逐一验证存在(4/4 OK)
- [x] 恢复的 network-access-china.md SHA-256 与 9-20 MANIFEST 一致
- [x] 两处措辞修改后文件其余内容零改动(edit 精确替换)
- [x] 本机身份判定有实证:内核 `6.8.0-149-generic`(非 WSL2)、无 `/mnt/c`、10809 拒绝连接、Google 直连 204、出口 IP=本机 eth0

## 测试计划

无自动化测试(纯文档任务)。人工验证 = 上表验收标准逐条核对,已全部通过。

## 性能与容量(性能与容量)

性能门未触发:仅文档与本地指令文件变更,无运行时路径、查询、缓存、外部调用、迁移或数据处理负载。

## 回退

AGENTS.md 两处措辞:删去「Machine scope」句 / 恢复原第 4 条文本(备份在本 plans 目录同日 git 历史与 `~/plans` 仓库中)。文档恢复:删除 `~/docs/network-access-china.md` 即回到删除前状态。
