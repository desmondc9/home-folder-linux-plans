# Tailnet 双 Exit Node + sing-box 分流网关

**状态**: 生产可用(2026-08-19) · 设计文档: [design.md](design.md) · 实施记录: [implementation.md](implementation.md)

## 架构一句话

笔记本(Kubuntu 26.04)同时是 tailnet Exit Node 和 sing-box 分流网关:tailnet 客户端(iPad/Android)选它为出口时,国内网站直连家宽,国外网站经 VLESS+Reality 到 bandwagon VPS;笔记本自身流量也走同一套分流。VPS(brave-goose-1)作为第二出口(全局美国 IP,兜底)。

## 自启动行为

| 服务 | 自启动 | 依赖 | 说明 |
|---|---|---|---|
| `sing-box.service` | ✅ enabled | 无 | 主分流引擎,监听 7896(tproxy)/10809(mixed) |
| `sing-box-tproxy.service` | ✅ enabled | `After=tailscaled.service` | 加载 nftables 规则+策略路由;**不**强依赖 tailscaled,即使 tailscale 未启动也会加载规则(规则只拦 tailscale0,接口不存在时自然落空,不影响本机上网) |

**关键结论**:两个服务都随系统自动启动,**不开 tailscale 也不影响本机上网**——TPROXY 规则只作用于 tailscale0 接口的流量,接口不存在时规则不命中任何包,本机流量正常直连。

## 软件升级

### sing-box 本体

```bash
# 1. 查当前版本
sing-box version

# 2. 下载新版(走本机 10809 代理,或临时 export https_proxy=http://127.0.0.1:10809)
curl -fSL -o /tmp/sing-box-new.deb "https://github.com/SagerNet/sing-box/releases/download/vX.Y.Z/sing-box_X.Y.Z_linux_amd64.deb"

# 3. 备份配置后升级
sudo cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%F)
sudo dpkg -i /tmp/sing-box-new.deb

# 4. 校验配置兼容性(新版本可能有弃用字段)
sudo sing-box check -c /etc/sing-box/config.json

# 5. 重启并验证
sudo systemctl restart sing-box
curl -x http://127.0.0.1:10809 -s https://api.ipify.org   # 应显示 VPS IP
curl -x http://127.0.0.1:10809 -s https://myip.ipip.net  # 应显示家宽 IP
```

**注意**:sing-box 1.12+ 对配置格式有破坏性变更(如 `default_domain_resolver` 必填、rule-set 版本升级),升级前务必 `sing-box check`,失败时对照 [迁移文档](https://sing-box.sagernet.org/migration/) 调整。

### 分流规则(rule-set)

sing-box 配置里已声明 `update_interval: "7d"` 自动更新,**无需手动干预**。手动强制更新:

```bash
# 重启 sing-box 会重新拉取远程 rule-set
sudo systemctl restart sing-box

# 验证日志里看到 "updated rule-set geosite-cn" 等
journalctl -u sing-box --since "-1min" | grep "updated rule-set"
```

### 自定义规则(用户维护)

编辑后重启生效:

```bash
# 强制直连(国内网站例外)
sudo vim /etc/sing-box/rules/custom-direct.json

# 强制走代理(国外网站例外)
sudo vim /etc/sing-box/rules/custom-proxy.json

# 格式:domain(精确)/domain_suffix/domain_keyword/ip_cidr 数组
# 示例:把 openai.com 强制走代理
# {"domain_suffix": ["openai.com"]}

sudo systemctl restart sing-box
```

## 日常运维

### 健康检查

```bash
# 服务状态
systemctl is-active sing-box sing-box-tproxy tailscaled

# 本机分流验证
curl -4 -s https://api.ipify.org          # 应显示 104.194.83.82(VPS)
curl -4 -s https://myip.ipip.net          # 应显示 114.92.x 家宽

# tailnet 出口验证(iPad/Android)
# Exit Node 选笔记本 → myip.ipip.net 应显示家宽,google.com 应可访问
```

### 故障回退

```bash
# 一键摘掉流量劫持(本机立即恢复直连)
sudo systemctl stop sing-box-tproxy

# 完全停用分流(回到无 sing-box 状态)
sudo systemctl disable --now sing-box sing-box-tproxy
sudo rm /etc/systemd/resolved.conf.d/singbox-dns.conf
sudo systemctl restart systemd-resolved
```

### 日志排查

```bash
# sing-box 主日志
journalctl -u sing-box -f

# tproxy 规则加载
journalctl -u sing-box-tproxy -f

# tailscale 连接
journalctl -u tailscaled -f
```

## 已知限制

- **tailnet 客户端经笔记本出口的 v4-only 国外域名不可达**(如 ipv4.google.com)——iOS 客户端对"笔记本出口"特定路径不应用 v4 默认路由,已穷举 TPROXY/REDIRECT/内核 TUN 均无效。**Workaround**:遇此类网站临时切 Exit Node 到 `brave-goose-1`(VPS,v4 正常),用完切回笔记本。详见 [design.md](design.md) 已知限制节。
- 笔记本睡眠/关机时,客户端出口失效 → 切 VPS 出口或 None。

## 文件清单

| 路径 | 作用 |
|---|---|
| `/etc/sing-box/config.json` | sing-box 主配置(源文件在 `sing-box-deploy/`) |
| `/etc/sing-box/tproxy.nft` | nftables TPROXY 规则(含 redirect_nat 链) |
| `/etc/sing-box/rules/custom-{direct,proxy}.json` | 用户自定义分流规则 |
| `/etc/systemd/resolved.conf.d/singbox-dns.conf` | 系统 DNS 指向 223.5.5.5(经 sing-box 分流) |
| `/etc/sysctl.d/99-exit-node.conf` | IP 转发持久化 |
| `/etc/default/tailscaled` | tailscaled 配置(含 `TS_USERSPACE=false`) |
| `sing-box-deploy/` | 所有配置文件的源仓库(含沙盒测试脚本),部署到 `/etc/sing-box/` 前先在这里修改 |
