# implementation — IPv6 断网排查与客户端免疫层

对应 [spec.md](./spec.md)。本任务为排查/加固型，无代码仓库变更；变更对象为 Windows 宿主机与路由器配置。

## 变更文件表（含回滚）

| # | 对象 | 变更 | 回滚 |
|---|---|---|---|
| 1 | `C:\Users\Desmond\Apps\sing-box\config.json` | ① `dns.strategy`: `prefer_ipv4` → `ipv4_only`；② `dns.rules` 首插 `{"query_type":"AAAA","action":"reject"}`（reject 比 strategy 可靠：strategy 不影响客户端 AAAA 应答，实测仅 reject 生效） | 备份 `config.json.bak-20260917-ipv4only`（两处改动**之前**的原始状态）直接回拷；或手改两处。改后需管理员重启服务：UAC 运行 `C:\Users\Desmond\Apps\sing-box\restart-elevated.ps1` |
| 2 | Windows Wi-Fi DNS | 静态 `223.5.5.5` + `fdfe:dcba:9876::2`（v4 查询经 TUN 被 hijack-dns 接管、按 ipv4_only 应答；原 DHCP 下发 192.168.31.1 走 `192.168.0.0/16` 排除规则绕过 sing-box，是真 AAAA 泄漏源之一） | `Set-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -ResetServerAddresses` |
| 3 | Windows Tailscale | `tailscale set --accept-dns=false`（MagicDNS 100.100.100.100 不经 TUN，其上游返回真 AAAA，泄漏源之二） | `tailscale set --accept-dns=true`（会恢复泄漏路径，除非已删 #1 的 reject） |
| 4 | 路由器侧 | 仅 API 读取与 `set_wan6` off→on 软切换（未改配置）；现场新增 `set-dns.ps1` / `restart-elevated.ps1` 两个辅助脚本 | 无需回滚；脚本可留作工具 |

诊断期临时改动（当日已自然失效/被覆盖）：`/etc/resolv.conf` 未动；sing-box 服务经历一次正确提权重启（09:50）。

## 小米路由器 API 备忘（RA72 1.0.122 实测）

- **无需认证**：`/cgi-bin/luci/api/xqsystem/init_info`（型号/SN/绑定状态）
- **登录**（管理密码本档不存，见 spec 风险节）：
  1. GET `/cgi-bin/luci/web`，从页面 JS 提取静态 `key` 与设备 MAC `deviceId`（页面内明文）
  2. `nonce = "0_<deviceId>_<unixts>_<rand>"`；`password = sha1(nonce + sha1(明文密码 + key))`
  3. POST `/cgi-bin/luci/api/xqsystem/login`（username=admin, logtype=2）→ `rsp.url` 内取 `;stok=`
  4. 之后一律 `/cgi-bin/luci/;stok=<stok>/api/...`
- **有用端点**：`xqnetwork/ipv6_status`（WAN/PD/LAN v6 全量自检）、`xqnetwork/wan_info`、`xqnetwork/set_wan6`（wanType: off/native）、`misystem/topo_graph`（mesh 拓扑）、`misystem/status`（设备清单）
- 旧教程的 `login_key` 端点在本固件返回 401，勿再走弯路

## 验证记录（2026-09-17）

- 11:10 路由器冷启 → RA ~100s 到达：siteprefixes 出现 `240e:389:a53e:d10::/64`，SLAAC×2 + DHCPv6×1 地址，默认路由 via 主路由 fe80::d635
- 宿主 `ping -6 2400:3200::1` 2/2 通 12ms（真实 RTT；对照假应答指纹见下）
- `curl -4` baidu/bilibili/taobao 200；经 VPS google 200；sing-box 日志 v6 dial 错误清零
- 免疫层生效验证：`nslookup -type=AAAA` 经 fdfe:dcba:9876::2 → Query refused；`GetHostAddresses` 无 v6

## 可迁移经验（教训）

1. **TUN 代理会吞掉 v6 故障的表现**：TUN 本地完成 TCP 握手 → 应用层 Happy Eyeballs 失效 → "IPv6 黑洞"呈现为"国内站打不开而代理的国外站正常"。凡 TUN + 分流架构，v6 断连的首发症状在浏览器里是反直觉的
2. **WSL mirrored 模式取证陷阱**：经 TUN 的 `ping -6` 可能被 gvisor 栈**假应答**（指纹：RTT ~1.5ms、ttl=64、与日志 dial 失败并存）——不能作证据；WSL `tcpdump` 抓不到组播（RA/RS 全盲）；`rdisc6` 发 RS 无响应。客户端侧权威判据是 Windows 的 `siteprefixes` / `Get-NetRoute '::/0'` / `GetHostAddresses`
3. **小米 RA 服务挂死的判别**：路由器 API 自检 v6 全绿 + 客户端 DHCPv6 能拿地址 + NDP 通，但 siteprefixes 空 = odhcpd 的 RA 半死；`set_wan6` 软切换救不活，冷启后 RA 需等 ~100s，别过早下结论
4. **Windows 侧 AAAA 泄漏的三个入口**要一起堵：网卡静态 DNS（绕过 TUN 的物理/路由器路径）、Tailscale MagicDNS（不经 TUN）、Windows DoH（`netsh dns show global` 查）；只改 sing-box `strategy` 对客户端 AAAA 应答**无效**，必须 `query_type: AAAA → reject` 规则
5. **WSL 里提权 Windows 服务**：`sc.exe stop/start` 不提权会**静默失败**（查询照常返回 RUNNING，极具迷惑性）；`Start-Process -Verb RunAs` 在 bash 超时被杀后 UAC 点击无效——先落 `.ps1` 再弹 UAC，bash 侧给足超时并轮询产物文件
6. **多网卡 Windows 的 DNS 是并行竞速**：任一网卡的 DNS（含断开的 Ethernet、Tailscale）都可能抢先应答真 AAAA——排泄漏要 `Get-DnsClientServerAddress` 全量看
