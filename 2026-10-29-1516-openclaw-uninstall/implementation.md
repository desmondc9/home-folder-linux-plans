# 完整卸载实施记录

- [x] 确认唯一npm安装、数据与workspace路径、用户服务状态、shell专用引用；未读取/打印凭据内容。
- [x] 用户确认2.9GB状态和13项工作区改动需要先备份，再完整移除。
- [x] root受限备份：`/var/backups/openclaw-uninstall/2026-10-29-152509/data.tar.zst`，目录0700、文件0600，约1.3GB。
- [x] SHA256：`04735cc965ae83d59da4a2859c8c4c5675d341de3021c4b2e13b52aaa98337de`。归档含完整状态/workspace、专用小缓存/日志、unit/drop-in、修改前zsh配置和闲置Nginx文件；不含CLI安装包或可再生成的536MB编译缓存。
- [x] 使用tar ACL/xattr/numeric owner与zstd压缩；逐成员核对83,693项元数据、77,707个普通文件的源内容SHA及symlink，压缩完整性通过；耗时104.59秒。没有只凭「归档文件存在」就删除源数据。
- [x] 以desmond身份、原安装Node/CLI执行官方 `uninstall --all --yes --non-interactive`，退出0；service/state/workspace清理成功，macOS app分支在Linux不适用。
- [x] 用安装所属npm/prefix执行global uninstall openclaw并ignore lifecycle scripts，退出0。其他全局包名称集合严格等于卸载前减openclaw，Node/npm保留。
- [x] 只移除.zshrc的OpenClaw Completion两行、.zshenv的OpenClaw编译缓存两行；保留其余shell配置，zsh -n通过。
- [x] 清理专用.service.d、~/.cache/openclaw、/tmp/openclaw和/var/tmp/openclaw-compile-cache；均检查真实目录/owner后删除。
- [x] 清理已停用的Nginx openclaw-tailnet源文件及专用crt/key；无活动引用或Docker mount依赖，nginx -t通过，不需要reload/restart。
- [x] user daemon-reload后，user/system无OpenClaw/clawdbot unit；无相关Node进程，无18789/18790监听，CLI/global package/状态和残留路径均不存在。
- [x] fresh zsh找不到openclaw，专用NODE_COMPILE_CACHE未再设置；Node26.8.1、npm11.19.0正常。老会话若仍继承旧编译缓存变量，可在该会话unset或重新登录，无需重启任何共享服务。
- [x] 独立源码`~/Repos/openclaw-weixin`保留；nginx master123279、sing-box123217不变，11个既有域名/health在IPv4/IPv6上均保持预期。

## 保留与发布限制

保留root专用数据备份、前一次关闭入口的受限备份、独立源码及历史档案；这些不代表仍有可运行OpenClaw安装。没有修改LibreChat部署、其他应用配置、Node/npm版本或业务仓库，没有新增长期服务/定时任务。原始CLI/npm卸载输出只保存在root备份目录的私有日志中，不上传。

不提供自动重装、版本回滚或恢复脚本；备份数据如何复用由用户另行决定，共享shell/业务配置不可整份覆盖后续改动。此记录只含路径、版本、摘要和结果，不含真实token/私钥、会话内容或未提交工作文件内容。
