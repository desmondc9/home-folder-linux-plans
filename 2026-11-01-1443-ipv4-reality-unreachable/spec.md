# iPhone/iPad IPv4 无法连接 sing-box REALITY 的诊断

- 环境：Bandwagon VPS (Ubuntu 24.04.4, IPv4 104.194.83.82 / IPv6 2607:8700:5500:7bd3::2)，sing-box 1.14.4 + Nginx stream 443 复用（2026-10-29 迁移）；客户端 iPhone/iPad Shadowrocket（节点 Bandwagon-VS，vs.signal-align.com:443）。
- 日期：2026-11-01，时区 +08:00。
- 症状：同一节点，手机走 IPv6（240e: 电信）完全正常，走 IPv4“连不上”。
- 结论（一句话）：**服务器配置无任何问题；是本 VPS 的 IPv4 在“美国→中国大陆电信”方向被线路侧单向丢包（SYN-ACK 回不去），即 IPv4 出口 IP 已被墙（单向黑洞模式），IPv6 不受影响。**

## 证据链（Phase 1 只读取证）

1. DNS 三家解析器（本机/1.1.1.1/8.8.8.8）A/AAAA 均正确：vs → CNAME bandwagon → A 104.194.83.82 / AAAA 2607:...::2，灰云。
2. 双栈 443 监听、UFW 放行均正常；stream 日志里大量来自 240e:（本机电信 IPv6）的 REALITY 成功连接（含单连接 ~512MB 吞吐），说明配置/凭据/分流完全正常。
3. 当天 stream 日志中，来自公网 IPv4 且成功完成握手的来源全部为海外/云扫描器（195.178.110.x 约 4700 条、47.x、49.51、66.132、143.244、192.81 等），**没有一个中国大陆消费级 IPv4 成功过**。
4. 判决实验（用户配合重试 + 180s tcpdump `tcp port 443 and ip`）：
   - 手机 IPv4（114.92.99.221，上海电信）的 SYN **到达了服务器**（窗口内 19 个 SYN，含客户端重传）；
   - 服务器**每次都在 eth0 上发出 SYN-ACK**（tcpdump 出站可见），并按 1s/2s/4s… 重传（内核等不到 ACK）；
   - 客户端也在重传 SYN（说明它也没收到 SYN-ACK）；
   - 双向重传直到超时，**三次握手从未完成，0 个数据包**——nginx 用户态根本没见过这些连接（stream 日志中该 IP 零条目）。
5. sing-box 日志中的 `flow mismatch`/`mux connection closed` 报错经 error.log 时间戳比对全部对应 **IPv6** 来源（Shadowrocket 部分子连接开了 mux 且不带 flow），与 IPv4 故障无关；IPv6 主流量（vision+flow）一直成功。

## 根因判定的排除过程

- 排除服务器 443/IPv4 监听问题：海外 IPv4 客户端同端口大量成功。
- 排除 UFW/防火墙丢弃：被 UFW 拦会有 [UFW BLOCK] 内核日志，443 无任何记录；且 SYN 已到达、SYN-ACK 已出网卡。
- 排除 DNS/客户端配置：同一 URI 在 IPv6 完全成功；IPv4 的 SYN 精确到达本机。
- 排除 MTU/MSS：握手包极小，不涉及分片。
- 剩下唯一成立解释：**回程方向（VPS→中国大陆电信）对 104.194.83.82 的流量被选择性丢弃**。去程（客户端 SYN）能到、回程（SYN-ACK）到不了，是 GFW 单向丢包式 IP 封锁的典型表现；IPv6 国际链路未受影响，故 240e: 一切正常。

## 可选处置（按代价从低到高）

1. **维持 IPv6 使用**（现状已可用）：手机蜂窝与支持 IPv6 的 WiFi 均正常；确保路由器/运营商开启 IPv6。
2. **Bandwagon 后台付费换 IPv4**（一次性费用）：新 IPv4 大概率恢复大陆直连；被墙与端口无关，换端口无效。
3. **加中转**：在未被封的入口（如香港小鸡）做 stream/TCP 中转或换用可过 CDN 的协议；引入新设施，超出本次范围。
4. 顺带优化（与本次故障无关）：Shadowrocket 该节点设置里建议关闭“多路复用(mux)”——mux 子连接不带 flow 会被服务端按 vision 预期拒绝，产生日志噪音并可能造成部分 App 间歇失败。

## 后续观察

- 复测方式：`sudo tcpdump -i eth0 -nn 'tcp port 443 and ip'` 抓包看大陆 IPv4 是否仍是“SYN 到、SYN-ACK 无回应”；或直接看 stream-access.log 是否开始出现大陆 IPv4 条目。
- 换 IP 后 vs/bandwagon 的 DNS A 记录需要同步更新（AAAA 不变）；Cloudflare 仍是灰云 DNS-only。
