# OpenClaw本机完整卸载

- 环境：Ubuntu24.04.4 LTS Bandwagon VPS，desmond账户；2026-10-29。
- 用户要求：完整卸载本机OpenClaw。
- 已确认范围：用户选择「备份后完整移除」；包括CLI、用户服务、~/.openclaw工作区/会话/记忆/插件/密钥状态、专用缓存/补全与闲置Nginx文件。共享Node/npm、独立源码仓库及LibreChat配置不动。
- 本次仅本机操作，记录先本地Git保存；不擅自推送新增运维任务。

## 卸载前盘点

- npm安装版本2026.9.2，唯一已核实安装prefix：`~/.nvm/versions/node/v26.8.1`；包目录`lib/node_modules/openclaw`，CLI为该prefix的bin/openclaw链接。
- ~/.openclaw约2.9GB，默认workspace是真目录、非symlink；Git仓库为未创建首个提交状态，13项未提交/未跟踪内容，没有外部worktree。
- 共享Node编译缓存`/var/tmp/openclaw-compile-cache`约536MB，通过.zshenv中的OpenClaw专用export启用；移除该export和派生缓存，不移除Node。
- Gateway已在前一任务停用，无18789/18790监听；Nginx源站点与self-signed cert/key仍属专用残留，没有活动Nginx配置或容器mount引用它们。
- 未发现其他profile、额外npx安装或系统级gateway unit。独立`~/Repos/openclaw-weixin`不是本次安装，不删除。

## 安全边界

- 使用已安装CLI的官方uninstall范围及其所属npm执行remove，不用npx（会下载），不安装、重装、升级或降级OpenClaw。
- 真实备份包含会话、凭据、未提交工作与shell配置，必须留在root受限目录，不入Git。不是法证擦除，用户明确要求保留该备份。
- 官方全量预览只列出user service、~/.openclaw及其workspace；不存在删除家目录或外部业务工作区的计划。
- LibreChat等其他应用中的历史OpenClaw引用/token不修改；卸载不等于清除所有源码、文档、历史日志或共享npm缓存中的字符串。

## 验收与性能

CLI/全局包不存在，fresh shell不再设置专用编译缓存，无user/system unit、进程或18789/18790监听；活跃状态及专用残留路径不存在。Node/npm仍可运行，其他global package名称保持，独立源码仓库仍在，nginx -t及11个原域名双栈health通过，nginx/sing-box PID不变。

只移除未使用服务与本地数据，没有新增SQL/cache/query/outbound/周期任务；延续前一入口关闭任务的网关门禁结论，未对其他服务做restart/loadtest/E2E。

参考：https://docs.openclaw.ai/install/uninstall （实际flags以已安装2026.9.2的help/dry-run再次确认）。
