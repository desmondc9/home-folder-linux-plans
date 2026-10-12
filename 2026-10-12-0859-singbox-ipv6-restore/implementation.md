# 实施与验证

对应 [spec.md](spec.md)。仅归档配置差异与证据，不保存含 UUID 等凭据的完整运行配置。

## 已应用变更

- 文件: `D:\Desmond\Apps\sing-box\config.json`。
- 删除 DNS 的 AAAA reject 规则。
- `dns.strategy`: `prefer_ipv4` → `prefer_ipv6`。
- `route.rules` 第 4 项增加 `{"action":"resolve","strategy":"prefer_ipv6"}`，不指定 server，沿用 DNS 分流选择。
- 使用 sing-box 1.14.2 执行配置 check，退出码 0。
- 核实 NSSM 注册参数为上述 D 盘配置；目录中的旧服务 XML 指向 C 盘，不能用来判断当前服务配置。
- 普通权限重启失败后恢复原配置；随后通过 Windows UAC 提权应用配置、重启服务并清理系统 DNS 缓存。服务状态 Running。
- 成功应用前备份: `D:\Desmond\Apps\sing-box\config.json.bak-20261012-085941-ipv6`。

## 自动测试证据

- 修改前: `nslookup -type=AAAA api6.ipify.org` 经 `fdfe:dcba:9876::2` 返回 Query refused。
- 修改后: 同一查询返回 `2607:f2d8:1:3c::4`。
- TUN 与本机 HTTP 代理 `127.0.0.1:10809` 访问 api6.ipify.org 均成功，出口 `2607:8700:5500:7bd3::2`。
- HTTP 代理访问 api4.ipify.org 成功，出口 `104.194.83.82`；api64.ipify.org 返回上述 IPv6 出口。
- test-ipv6.com 的 ipv6、ipv4、ds 三个 `/ip/` 端点均成功，ds 使用 IPv6。

## 用户 Chrome 验证

| 测试 | 结果 | 时间 | 地址族 |
|---|---|---|---|
| IPv4 DNS record | ok | 1.257s | IPv4 |
| IPv6 DNS record | ok | 1.295s | IPv6 |
| Dual Stack DNS record | ok | 1.271s | IPv6 |
| Dual Stack DNS and large packet | ok | 1.236s | IPv6 |
| IPv6 large packet | ok | 1.370s | IPv6 |
| ISP DNS server uses IPv6 | ok | 1.653s | IPv6 |
| IPv4 Service Provider | ok / ASN 25820 | 1.214s | IPv4 |
| IPv6 Service Provider | ok / ASN 25820 | 1.194s | IPv6 |

当前测试未发现 IPv6 大包传输问题。IPv6 故障回退与 AX6000 长期稳定性仍待验证。

## 回滚

将上述备份复制回 config.json，执行 sing-box check，并以管理员权限重启 `sing-box` 服务。备份包含真实凭据，仅保存在原机器，不入库。

## Notebook 检查

检查 WSL 中相关 sing-box/Tailscale 域笔记的 AAAA、AX6000、ipv4_only 引用，未发现匹配项。本次更新 plans 档案及历史记录关联。
