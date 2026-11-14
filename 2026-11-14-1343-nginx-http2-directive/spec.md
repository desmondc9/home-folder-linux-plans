# nginx vhost http2 指令现代化（1.28.3 deprecation 清理）

- 环境: Bandwagon VPS，nginx 1.24.0 → 1.28.3（2026-11-14 12:00 批量升级引入 deprecation 警告）
- 日期: 2026-11-14
- 状态: 完成。6 个 vhost（auth-local-edge×3 块、books×2、derp、headscale、rakazo、reading×2，共 10 处）全部改为 `listen 127.0.0.1:14443 ssl proxy_protocol;` + 独立 `http2 on;` 行（≥1.25.1 语法）。**勘误（2026-11-14 审查时更正）：ntfy/headscale-new 并非"新写法未动"，其 vhost 文件已于 11-14 12:00 维护中被整体删除（sites-available/enabled 均无）**。
- 关联: rakazo vhost 源文件经 PR 落库（desmondc9/rakazo-deploy#8/#9，staged live 文件与 repo 版本 diff 逐字节一致）

## 执行方式（no-NOPASSWD 模式第二次实践）

agent（无 root）：sed 生成 6 个补丁文件到 staging + diff 逐文件人工核对 + 写幂等 apply 脚本（备份→安装→nginx -t→reload，ERR trap 自动还原备份）；用户终端 `sudo bash /tmp/opencode/nginx-http2-fix/apply.sh` 执行（备份留存 `/tmp/opencode/nginx-http2-fix/backup-20261114-134709/`）。

## 验证

- `nginx -t` 零警告（此前 11 条 deprecation）
- 公网可达的 4 个 vhost 全部 HTTP/2 + 预期码：auth 307 / derp 200 / headscale 405（API 根正常）/ rakazo 200
- live 文件 `listen` 行零 http2 残留；`http2 on;` 每个原 server block 一处

## 顺带查明的事实（重要机器知识）

**ntfy / books / reading 三个子域是公网 NXDOMAIN**（dns.google 权威确认）——它们没有公网 DNS 记录，靠 tailnet（headscale MagicDNS）等内部途径解析访问；nginx 里保留其 vhost 是为 tailnet 流量经 14443 入口时按 SNI 命中。此前会话中 librechat.signal-align.com 在本机同样不解析。排查"某子域连不上"时先分类：公网记录（auth/derp/headscale/rakazo/apex）vs 内部记录（ntfy/books/reading/librechat），再决定用外部 DoH 还是 tailnet 视角验证。
