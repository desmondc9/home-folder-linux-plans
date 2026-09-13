# 实施记录:alidns 传输切换 UDP → DoH

日期:2026-09-13 · 对应 [spec.md](./spec.md)

## 任务清单

- [x] Phase 1 取证:读 `~/docs/network-access-china.md` 定位服务与配置;clash API `/connections` 证实 bilibili 全部 direct;扫描 5 个轮转日志(约 50MB)提取错误分布
- [x] Phase 2 对照:`exchange failed ... context deadline exceeded` 仅命中 alidns(UDP)服务的域名;cfdoh(DoH/TCP)零卡死
- [x] Phase 3 单变量修复:备份 → `alidns` `type: udp` → `type: https` → `sing-box.exe check` 通过
- [x] Phase 4 验证:提权重启服务(UAC);浸泡 6 分钟 636/636 <500ms、0 失败;代理/分流回归通过
- [x] 文档同步:`~/docs/network-access-china.md` 注明 DoH 变更与备份名

## 变更文件

| 文件 | 变更 |
|---|---|
| `C:\Users\Desmond\Apps\sing-box\config.json` | dns.servers[alidns]: `type: udp` → `type: https`(server 仍为 223.5.5.5;sing-box 默认 path=/dns-query,与既有 cfdoh 写法一致) |
| `C:\Users\Desmond\Apps\sing-box\config.json.bak-20260913-alidns-doh` | 变更前备份 |
| `~/docs/network-access-china.md` | sing-box 服务段落补记 DoH 变更缘由 |

## 验证方式

```powershell
# 配置校验(WSL 里直接跑 Windows exe)
/mnt/c/Users/Desmond/Apps/sing-box/sing-box.exe check -c 'C:\Users\Desmond\Apps\sing-box\config.json'
# 提权重启(UAC):sc.exe stop/start sing-box → 确认新进程 CreationDate
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='sing-box-service.exe'\" | Select ProcessId,CreationDate"
```

```bash
# 浸泡统计(清洗 ANSI 后):延迟分布 / 失败数 / bilibili 域名交换数
sed -E 's/\x1b\[[0-9;]*m//g' logs/sing-box-service.err.log | grep "dns: exchanged" \
  | grep -oE "\[[0-9]+ ([0-9.]+m?s)\]" | awk -F'[][ ]' '{t=$3; ms=(t~/ms/)?$3+0:($3+0)*1000;
  print (ms>2000?"SLOW":(ms>500?"mid":"fast"))}' | sort | uniq -c
# 回归:代理出口 IP + bilibili 直达延迟
curl -s -x http://127.0.0.1:10809 https://api.ipify.org   # → 104.194.83.82
curl -s -o /dev/null -w "%{time_namelookup}s\n" https://www.bilibili.com
```

## 备注(可迁移经验)

1. **TUN 分流排查先看实时连接再翻日志**:clash API `/connections` 的 `chains` 字段一步证实"是否走错出口";卡顿类问题再回日志找 `exchange failed`/耗时分布。
2. **sing-box info 日志的连接 ID 可全链路追凶**:同一 `[id elapsed]` 串起 inbound→dns→outbound;日志带 ANSI 色码,管道处理前先 `sed` 清洗。
3. **裸 UDP:53 上游是脆弱点**:对照组 DoH(TCP)同环境零故障——国内 DNS 上游一律用 DoH(`https://223.5.5.5/dns-query`,证书带 IP SAN 免 bootstrap)。
4. **短 TTL 域名是 DNS 故障的放大镜**:CDN/大厂域名 TTL 常 ≤10s,任何 DNS 抖动最先在其业务上显形;bilibili 卡顿应第一时间怀疑 DNS 而非分流。
5. **WSL 里运维 Windows 服务**:`powershell.exe Start-Process -Verb RunAs` 触发 UAC(用户需点确认,`-Wait` 会卡到超时,别带);查服务真实重启时间用 `Get-CimInstance Win32_Process` 的 CreationDate(sc query 不给)。
6. **Tailscale MagicDNS 与 sing-box TUN 双劫持 DNS**:tailscaled 竞速把查询放大 ×4-8 并产生 `bad rdata` 畸形包噪音;修传输层可止血,除根需 `--accept-dns=false`(已登记为下一个变量)。
