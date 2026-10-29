# UFW端口审计与OpenClaw入口关闭

- 环境：Bandwagon VPS，Ubuntu 24.04.4 LTS，104.194.83.82 / 2607:8700:5500:7bd3::2；2026-10-29。
- 范围：用户要求核实3478/41641用途，并确认停止/禁用OpenClaw gateway、停用18790 Nginx入口、删除18789/18790 UFW放行；保留本体、配置与数据。不升级/降级/卸载OpenClaw，不修改LibreChat部署。
- 本次仅本机操作；档案先本地Git记录，不自动推送新的运维任务。

## 实测端口归属与建议

| 端口 | 进程/用途 | 结论 |
|---|---|---|
| TCP22 | sshd | 保留，管理通道 |
| TCP80 | nginx，HTTP到HTTPS跳转 | 可选关闭，但会失去HTTP跳转；当前证书DNS-01不依赖80。本次不改 |
| TCP443 | nginx stream，Web及sing-box REALITY共享 | 保留 |
| UDP3478 | headscale，启用的embedded DERP region999的STUN | 当前在用，不按闲置删除 |
| UDP3479 | derper，独立DERP的STUN | 当前在用；要精简一套需同时审阅DERP配置及客户端下发，不能盲删规则 |
| UDP41641 | tailscaled，WireGuard加密直连/打洞 | 建议保留；关闭可能退化为DERP中继 |
| TCP7000 | frps控制连接 | 与6001一起仅在不需要FRP时考虑关闭，检查时有1条现存FRP连接 |
| TCP6001 | frps的Windows SSH映射 | 用户未要求停用FRP，本次保留 |
| TCP18789 | OpenClaw用户服务gateway | 经用户确认停用 |
| TCP18790 | Nginx的OpenClaw WSS入口 | 经用户确认停用 |

## 重要防火墙边界

IPv4/IPv6 INPUT都先跳入ts-input，再进入UFW。当前ts-input直接ACCEPT tailscale0，也直接ACCEPT UDP41641。因此仅删除UFW条目不等于真正关闭Tailnet访问或41641端口；本次通过停服务/取消Nginx listener实际消除18789/18790监听，没有改Tailscale链或ACL。

OpenCode不在openclaw-gateway的cgroup内，关闭gateway不会连带终止本次操作进程。LibreChat对应OpenClaw端点会不可用，这是用户确认后的预期结果，其他端点/应用未修改。

## 验收

- gateway inactive/disabled，安装/数据保留。
- 无IPv4/IPv6 TCP18789/18790监听，无对应UFW条目。
- nginx -t成功且仅reload，nginx master与sing-box PID不变。
- 11个既有HTTPS名称/health在IPv4/IPv6上保持预期结果。
- 其他防火墙规则、Headscale/Tailscale/DERP/FRP未修改。

## 性能与容量

触发gateway入口变更门禁，结论为只移除不用的监听和服务，没有新DB/cache/query/出站调用/周期任务；Nginx其他路由及共享443配置不变。验证是有界健康探测，不运行应用E2E/压测。
