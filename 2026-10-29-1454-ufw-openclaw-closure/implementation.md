# 本机执行记录

> 后续用户已授权[完整卸载OpenClaw](../2026-10-29-1516-openclaw-uninstall/implementation.md)。下述「保留安装/数据、可enable恢复」是入口关闭时点的记录；完整卸载后不能再只靠enable原unit恢复。

- [x] 以root ss、服务元数据、headscale选定配置字段核实端口归属，没有打印凭据或完整OpenClaw配置。
- [x] 检查IPv4/IPv6 ts-input优先于UFW；确认只删allow不足以关闭Tailnet监听。
- [x] 用户明确选择关闭gateway服务与Nginx入口，同时移除UFW18789/18790，保留安装和数据。
- [x] 受限备份：`/var/backups/ufw-openclaw/2026-10-29-150122/`，目录0700、文件0600，含原UFW用户规则/配置、原用户unit、Nginx站点副本及恢复元数据；不入Git。
- [x] `systemctl --user disable --now openclaw-gateway.service`；最终inactive、disabled。
- [x] 删除 `allow in on tailscale0 to any port 18789 proto tcp` 和18790同类规则，IPv4/IPv6均删除。
- [x] 移除 `/etc/nginx/sites-enabled/openclaw-tailnet` 链接，保留sites-available源文件及证书；nginx -t后平滑reload，不restart。
- [x] ss核实两个端口均无监听；UFW无18789/18790；原用户unit文件仍在。
- [x] Nginx master PID123279及sing-box PID123217保持不变；11域/health双栈探测通过。
- [x] 保留22/80/443、3478/3479/41641、7000/6001，不擅自停用网络或FRP服务。

## 恢复边界

需要重新使用时，由用户明确授权恢复现有user service的enable/start、原Nginx站点链接并test/reload；无需重装或降级本体。原链接目标与规则在私有备份中可查，不盲目恢复整张防火墙覆盖后续用户修改。Tailscale链会放行tailnet流量，不能把删UFW条目当作永久禁止显式重启服务。

LibreChat旧OpenClaw连接现在不可用；没有为隐藏该入口而修改LibreChat文件、token、Key Vault或任何业务仓库。记录不含原始unit内容、私钥/API key、用户访问IP或token。
