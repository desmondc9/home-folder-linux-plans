# 实施记录

## 任务清单

- [x] Phase 1 证据收集:`lpstat -t/-v`、CUPS error_log、avahi-daemon 状态、`/etc/nsswitch.conf`、`resolvectl`、ARP 表 + /24 ping 扫描定位打印机 IP
- [x] Phase 2 假设验证:mDNS 名称解析失败(getent exit 2) vs 打印机固定 IP 四端口全开 —— 故障点唯一落在 mDNS 解析
- [x] Phase 3 修复:`lpadmin` 切 URI + `cancel -a` 清卡死任务 + `cupsenable` + 设默认
- [x] Phase 4 验证:测试页 job 61 于 35 秒内完成,队列 idle/enabled/默认,无 "Unable to locate"

## 变更表(全部经 CUPS API,无文件级手工编辑)

| 命令 | 作用 |
|------|------|
| `lpadmin -p OfficeJet_Pro_7740_series -v ipp://192.168.31.199/ipp/print` | 核心:device-uri 去 mDNS 化,直连固定 IP |
| `cancel -a OfficeJet_Pro_7740_series` | 清 1 个卡死任务(job 60,用户日历) |
| `lpadmin -d OfficeJet_Pro_7740_series` | 设系统默认打印机 |
| `cupsenable OfficeJet_Pro_7740_series` | 恢复队列 |

注:`cancel -a -p <队列>` 的 `-p` 选项不存在,正确语法是 `cancel -a <队列>`。

## 验证

- `lpstat -v` → `device for OfficeJet_Pro_7740_series: ipp://192.168.31.199/ipp/print`
- `lpstat -t` → `system default destination: OfficeJet_Pro_7740_series`,printer is idle, enabled,accepting requests,无 Unable to locate 报错
- job 61(测试页,1024 字节)14:07:17 提交,轮询 `lpstat -o` 于第 35 秒变空 → completed

## 可迁移经验

1. **"固定了设备 IP" ≠ "队列在用 IP"**——GNOME/KDE 自动发现的打印队列默认用 dnssd/mDNS 服务名(`ipps://…._ipps._tcp.local/`);在打印机上固定 IP 之后必须手动把队列 URI 切过来,否则白固定。这是"反复出问题"类打印故障的头号嫌疑。
2. LAN 固定地址的可靠设备,直连(`ipp://`/`socket://`)永远比 mDNS 可靠;mDNS 只适合"地址会变、随时发现"的场景。WiFi + 消费级路由器环境下 mDNS 组播时好时坏是常态。
3. `ipps://` + 打印机自签证书在 CUPS 会踩证书信任坑(`ssl_verify_result=18`);家用内网用明文 `ipp://IP/ipp/print` 即可,还保留 IPP 状态回报(墨量/双面等);`socket://IP:9100` 是放弃状态回报的最后兜底。
4. **zsh 没有 bash 的 `/dev/tcp`**——端口探测会全部假阴性报 closed,用 `nc -zv` / `curl` 替代。
5. 打印机 mDNS 主机名尾部的十六进制串 = 其 MAC(HP9C7BEF5AF59F → 9c:7b:ef:5a:f5:9f),可在 `ip neigh` 里按 MAC 反查 IP,免开路由器后台。
6. CUPS 排障入口顺序:`lpstat -v`(看 device-uri 用没用 mDNS)→ error_log(`CUPS-Create-Local-Printer` 失败=发现机制问题)→ 直连 IP 端口探测(631/9100/80)定位故障层。
7. 卡死任务在换 URI 后不会自动恢复,需 `cancel -a` 清掉重打。
