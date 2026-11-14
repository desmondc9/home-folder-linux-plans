# 实施记录:OpenCode 全局 AGENTS.md 审计与跨机器修复

执行时间: 2026-11-14 11:58–12:03 · 主机: brave-goose-1 · 操作者: opencode 会话(经用户确认"有问题就修复")

## 1. 审计过程(只读)

| 检查 | 结果 |
|---|---|
| 全文通读(287 行) | 结构/编码健康,无实体损坏,无 openclaw/claude 残留 |
| `rg -i 'openclaw|\.claude|claude code|ccw'` | 零命中 |
| `rg '&lt;|&gt;|&amp;|\r$'` | 零命中(软链转实体未引入损坏) |
| 引用文件存在性 | `~/docs/network-access-china.md`、`~/.azure-devops/credentials.jsonc` 缺失;其余 3 个 docs + Repos/plans/Backups 存在 |
| `ss -tln | rg 10809` | 无监听 → 追查 |
| `uname -r` = `6.8.0-149-generic`、无 `/mnt/c` | **本机非 WSL2,是原生 Linux** |
| `curl -x 127.0.0.1:10809 api.ipify.org` | 立即拒绝(端口无监听) |
| `curl google.com/generate_204` 直连 | **204**;出口 IP=本机 eth0(95.169.0.65)→ 本机不受 GFW 约束 |
| `pgrep sing-box` | 本机跑 sing-box 1.14.4,但为服务端角色(2026-10-29 迁移后) |
| 9-20 审计备份目录 | 找到 `network-access-china.md`,SHA-256 与 MANIFEST 一致 |

## 2. 修复执行

```bash
# ① 恢复文档(校验和验证)
cp -p ~/plans/2026-09-20-1542-opencode-global-agents-audit/backup-2026-09-20-154641/network-access-china.md \
      ~/docs/network-access-china.md
sha256sum ~/docs/network-access-china.md   # e3b47d5a…142ba ✓
```

② `~/.config/opencode/AGENTS.md` 网络章节段尾追加 **Machine scope** 句(GFW/10809 仅限墙内 sing-box 客户端机器;探测命令;拒绝则直连)。

③ Kanban 第 4 条改为条件式(PAT 在则读,不在则问用户,禁止翻找)。

## 3. 验证

- `~/docs/*.md` 引用 4/4 存在;AGENTS.md 实体文件完好。
- 恢复文件 SHA-256 与 9-20 MANIFEST 逐字节一致。

## 4. 备注

- 根因是**同一份指令文件跨机器共享**(WSL2 桌面 ↔ Linux 服务器),后续给 AGENTS.md 增加机器特定断言(端口/凭据路径)时,应默认写成条件式或先探测。
- 审计过程中 harness 因读取 9-20 备份目录而加载了旧版 AGENTS.md 作为上下文指令——历史备份,已按现行文件为准处理。
- 本机 sing-box 为服务端角色;如哪天需要本机走代理出口,需另配客户端入站,与本任务无关。
