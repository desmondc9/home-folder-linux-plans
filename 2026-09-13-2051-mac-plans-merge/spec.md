# mac-plans 整体并入 home-folder-linux-plans

- 日期:2026-09-13 20:51
- 环境:macOS 26.6.2(MacBook,karina@Mac;操作即在本机 ~/plans 上)
- 类型:档案库维护(合并/改写,无系统配置变更)
- 状态:已完成并验证(gitleaks 0 leaks + 推送成功)

## 背景

本机 `~/plans` 于今日由 home-folder-mac-plans 改追本仓库(见
[github-ssh-key-multi-account](../2026-09-13-2015-github-ssh-key-multi-account/)
遗留节)。原 mac 仓库 4 个 commits(全部 2026-07-30 入库)承载 6 个任务档案,
需按本仓库约定改写后并入。源:bundle 备份 `~/plans-mac-plans-backup-20260913.bundle`
(远端 home-folder-mac-plans 保留为冻结归档,不再更新)。

## 改写规则

1. **目录名**:`NNN-topic`(依赖序)→ `YYYY-MM-DD-HHMM-topic`(时间序)。
   日期取原 mac 仓库目录名(homebrew=07-27,其余=07-30);HHMM 取入库 commit
   时间(五个任务 20:27 同批,claude-md-audit 20:35 独立 commit)——mac 档未记
   分钟,五个任务共享 2027,先后以依赖关系为准(README 行序即依赖序)。
2. **文件名**:`design.md` → `spec.md`(本仓库约定名),正文提及同步替换。
3. **头部块**:每个 spec.md 补 `- 日期/环境/类型/状态` 头部行,环境逐条按档案
   内容写明 macOS 细节(机型/代理端口/工具链),满足 2026-09-12 的环境回填约定。
4. **互链**:`[[NNN-topic]]` Obsidian wikilink → 相对链接
   `[topic](./YYYY-MM-DD-HHMM-topic/)`(共 32 处,含 implementation.md 与 006
   目录内的 CLAUDE.md 快照)。
5. **根文件**:mac 仓库 README/LICENSE 不并入(本仓库自有);006 目录内的
   CLAUDE.md 是任务产出快照,随目录保留。

## 目录映射

| 原(mac 仓库) | 新(本仓库) |
|---|---|
| 001-git-clone-proxy | 2026-07-30-2027-git-clone-proxy |
| 002-claude-code-lsp-plugins | 2026-07-30-2027-claude-code-lsp-plugins |
| 003-podman-compose-provider | 2026-07-30-2027-podman-compose-provider |
| 004-homebrew-multiuser-shared | 2026-07-27-2027-homebrew-multiuser-shared |
| 005-java-sdkman-migration | 2026-07-30-2027-java-sdkman-migration |
| 006-claude-md-linux-to-mac-audit | 2026-07-30-2035-claude-md-linux-to-mac-audit |

## 验证

- `rg '\[\['` 六目录零残留;`rg 'design\.md'` 零残留
- gitleaks dir 扫描 0 leaks(提交前)
- README 索引补 6 行(时间位 07-02 之后)+ 引言/命名段说明 Mac 条目与时间戳由来
