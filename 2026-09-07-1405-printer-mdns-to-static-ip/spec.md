# 打印机任务卡死 "Unable to locate printer" — mDNS 队列改固定 IP 直连

日期: 2026-09-07
状态: 已修复——队列切换 + 测试页 35 秒完成验证(实体出纸待用户确认)

## 背景

HP OfficeJet Pro 7740(无线多功能一体机),用户已在打印机侧固定 IP(192.168.31.199),但打印"又出问题":任务长时间卡在 `now printing`,`lpstat` 报 `Unable to locate printer "HP9C7BEF5AF59F.local"`。历史完成记录(8/23–8/28 job 56–58)间断成功,典型间歇性故障。

## 根因(证据链)

**打印队列的 device-uri 是 mDNS 服务名而非固定 IP,任务下发时依赖 mDNS 解析,而本机 mDNS 解析时好时坏。用户固定了 IP,但队列从来没用到它。**

1. `lpstat -v`:`device-uri=ipps://HP%20OfficeJet%20Pro%207740%20series%20%5B5AF59F%5D._ipps._tcp.local/` —— dnssd 服务名,GNOME 自动发现建队列时的默认形态。
2. 故障当时 `getent hosts HP9C7BEF5AF59F.local` 失败(exit 2)——mDNS 正处于坏的状态。
3. mDNS 配置链完整:avahi-daemon 运行中、`/etc/nsswitch.conf` hosts 行含 `mdns4_minimal [NOTFOUND=return]`、libnss_mdns 库齐全 → 排除"配置缺失",指向组播(UDP 5353)层面的间歇性问题。本机经 WiFi(wlo1)接入家用路由器(192.168.31.0/24),组播质量不稳定是该网段的常见诱因(推测,非实证)。
4. `resolvectl`:各链路 `-mDNS`(systemd-resolved 侧 mDNS 关闭)——与 nss-mdns→avahi 路径无关,旁证本机 mDNS 生态本就不作为可靠依赖。
5. 打印机本体健康:ARP 表按 MAC `9c:7b:ef:5a:f5:9f` 定位到 192.168.31.199,80/443/631/9100 四端口全开(curl 200 / nc succeeded)。
6. `/var/log/cups/error_log`:`CUPS-Create-Local-Printer` 多次返回 `server-error-device-error` —— GNOME 侧自动建临时队列也在因同一解析问题失败。
7. 顺带记录(非本次根因):`marker-levels=100,100,20,70`(C/M/Y/K)→ 黄墨 20% 低墨警告,黑墨 70%。

### 排除表

| 嫌疑 | 结论 | 证据 |
|------|------|------|
| 打印机离线 / IP 变了 | ❌ | ping 通、四端口全开、MAC 与主机名尾段一致 |
| CUPS 挂了 | ❌ | scheduler running(12:25 起),本地功能正常 |
| 驱动 / PPD 问题 | ❌ | driverless IPP Everywhere + appleraster PPD 完好,换 URI 后即出纸 |
| mDNS 配置缺失 | ❌ | avahi + nsswitch + nss_mdns 库全在;解析仍失败 → 传输层间歇性 |
| 墨水耗尽导致不打印 | ❌ | 卡死发生在"定位打印机"阶段,尚未到打印环节 |

## 解决方案

核心:**队列 device-uri 从 mDNS 服务名改为固定 IP 直连,数据路径彻底去 mDNS 化**。

1. `lpadmin -p OfficeJet_Pro_7740_series -v ipp://192.168.31.199/ipp/print` —— 明文 IPP:避开打印机自签证书在 CUPS 的信任坑(curl 实测 `ssl_verify_result=18`),同时保留 IPP 双向状态回报(墨量等)。
2. `cancel -a OfficeJet_Pro_7740_series` 清卡死任务(含用户 14:02 排的日历,需重打)。
3. `cupsenable` + `lpadmin -d` 恢复队列并设为系统默认(原状态 "no system default destination")。
4. 残留的 GNOME 自动创建失败队列 `HP_OfficeJet_Pro_7740_series_5AF59F` 属 CUPS 临时队列,清任务后自行消失。

## 验收标准

- [x] `lpstat -v` → `ipp://192.168.31.199/ipp/print`
- [x] 测试页 job 61 提交(14:07:17)后 35 秒内完成(轮询 `lpstat -o` 至空)
- [x] 队列 idle + enabled,已设为系统默认
- [x] `lpstat -t` 无 "Unable to locate printer"
- [ ] 用户确认测试页实体出纸(机械层面,留待用户)

## 风险与缓解

- **未来改打印机 IP**:一条命令更新 `lpadmin -p OfficeJet_Pro_7740_series -v ipp://新IP/ipp/print`;打印机侧同时更新 DHCP 静态租约。
- **打印机深睡后 IPP 响应慢**:CUPS 默认重试兜底;极端情况下可退到 `socket://192.168.31.199:9100`(放弃墨量回报换最高兼容性)。
- **黄墨 20%**:近期需要更换墨盒。
- **Notebook 同步**:已检查 `~/Notebook/` 无打印机/外设对应域;单次事件暂不立新域,若打印机/外设问题再现或档案积累,再按 Notebook 惯例建域(MOC + 编号笔记 + README 依赖图)。

## 参考

- 相关环境:家 LAN 192.168.31.0/24,打印机 HP OfficeJet Pro 7740(MAC 9c:7b:ef:5a:f5:9f,主机名 HP9C7BEF5AF59F)
- 队列:`OfficeJet_Pro_7740_series`,driverless(IPP Everywhere),PPD 在 `/etc/cups/ppd/OfficeJet_Pro_7740_series.ppd`
