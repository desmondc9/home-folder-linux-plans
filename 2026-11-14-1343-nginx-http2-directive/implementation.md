# implementation — nginx vhost http2 现代化（机器档案）

1. 摸底：`grep -n http2 sites-enabled/*` → 6 文件 10 处同款（`listen 127.0.0.1:14443 ssl http2 proxy_protocol;`，每 server block 一处，可安全逐处插入 `http2 on;`）；ntfy/headscale-new 不在改动集（后经审查确认：其 vhost 已于当日 12:00 被删除，见 2026-11-14-1408-nginx-config-audit 勘误）；查明 `auth` 符号链接实指 `sites-available/auth-local-edge`（曾致直接读 `sites-available/auth` 误报不可读）
2. 生成：sed 统一变换 → staging 6 文件；逐文件 diff 人工核对；staged rakazo 与 repo PR 版本 diff 逐字节一致
3. repo 侧：Issue #8 → worktree → PR #9（nginx/rakazo.conf + plans）→ CI 绿 → squash 合并 34862ad
4. 机器侧：apply.sh（备份→安装→nginx -t→reload，ERR trap 自动还原）由用户终端 sudo 执行 → ALL DONE，备份留存 backup-20261114-134709/
5. 验证：nginx -t 零警告；auth 307 / derp 200 / headscale 405 / rakazo 200 全 HTTP/2；listen 行零 http2 残留、`http2 on;` 每原 block 一处
6. 收尾：Issue #8 验收评论、worktree 清理、本档案 + README 索引、gitleaks 零泄漏推送

附：验证中初测 ntfy/books/reading 连接失败 → 排查为公网 NXDOMAIN（dns.google 权威确认），系 tailnet 内部解析域名，非本次变更影响——分类结论已写入 spec.md「顺带查明的事实」。
