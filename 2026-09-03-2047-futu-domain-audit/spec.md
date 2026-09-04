# 富途牛牛(FTNN) 端点清单采集与 sing-box 全量代理分流

- 日期: 2026-09-03 20:47
- 类型: 调查 + 本机网络配置变更（无项目代码改动）
- 状态: 完成（验收 37/37 + 实机含交易全量 proxy 通过，见 implementation.md）

## 背景与目标

宿主机（Ubuntu 26.04, Wayland）上运行富途牛牛官方 Linux 桌面版（`/opt/FTNN`），其流量经本机
sing-box（1.13.19，系统服务，TProxy 模式）分流。目标：摸清 FTNN 后台 HTTP/socket 协议使用的
全部域名与 IP 端点，做成 sing-box 规则，使富途流量**字面意义全量走 proxy**。

## 环境事实（2026-09-03 实测）

| 项 | 事实 |
|---|---|
| 客户端 | 官方 Linux 版 v16.30（运行中），Downloads 已备 16.31 deb |
| 进程树 | `FTNN`(主)、`FTWeb`(CEF/Chromium)、`NNPython`、`CrashReporter` |
| 已知端点 | `api.futunn.com`（CrashReporter cmdline）；活跃连接全为裸 IP：`43.153.233.178:443`、`43.145.30.28:443`、`43.145.32.151:443`（腾讯云国际）+ `221.229.52.198:8080`（江苏电信，疑似 CN 加速行情线）；四者均无 PTR |
| FTNN 主二进制 | grep 不到任何 futu 域名字符串 → 域名加密/运行时下发，静态提取需扫全部资源文件 |
| sing-box | TProxy 入站 7896 + mixed 10809；nftables 仅劫持 `lo`/`tailscale0`（podman 桥接流量**不**被劫持）；DNS 已劫持；`final: proxy`；geosite-cn/geoip-cn → direct；clash_api 未开 |
| 自定义规则 | `/etc/sing-box/rules/custom-{direct,proxy}.json`（v2 source rule-set），在 geosite-cn 之前匹配 |
| 漏网机制 | 漏采的富途域名只有命中 geosite-cn/geoip-cn 才会错走 direct——验收盯这个 |
| 工具 | tcpdump/mitmproxy/7z/podman 5.7(docker 别名) 齐备，tshark 缺（容器内装） |

## 决策记录（三轮 grill 问答，用户逐条确认）

| # | 决策 |
|---|---|
| Q1 | 做**域名清单**（可移植、手机 sing-box 复用）；手机端字面全量由 per-app VPN 补齐 |
| Q2 | 采集手段 = 被动多源：SNI 抓包 + DNS 抓包 + 静态 strings 提取 + 社区清单交叉验证；**跳过 mitmproxy**（要域名不要内容） |
| Q3 | **字面全量 proxy**，CN 加速端点也不预留直连例外 |
| Q4 | 用 podman 容器做测试与验证（环境纯净） |
| Q5 | 新建独立 `/etc/sing-box/rules/futu.json`（域名 + 观测到的 /32），config 注册 |
| Q6 | 开启 clash_api（绑 127.0.0.1）作为观测台 |
| Q7 | 宿主机侧叠加 `process_name: [FTNN, NNPython, FTWeb, CrashReporter]` 兜底规则（TProxy 下实测有效才保留） |
| Q8 | 容器角色 = 验证回放（逐域名 curl 经 mixed 入站，clash_api 断言出站=proxy）+ 反向断言无 direct 漏网 |
| Q9 | 交互式采集覆盖标准 = 登录/自选/个股行情/资讯/模拟交易/设置全点一遍 |
| Q10/13 | 全部验证通过后一次性变更 config + 重启 sing-box 一次，备份 `config.json.bak-*-futu` |
| Q11 | 动态采集在 podman 容器内跑 GUI 版 FTNN 16.31（X11 socket 挂载走 XWayland）；拷贝宿主 431MB 数据目录继承登录态（掉登录则容器内重登）；采集期间退出宿主 FTNN；容器内无中文输入法可接受；采集后宿主升级 16.31 对齐版本 |
| Q12 | 容器抓取与宿主互不干扰：容器流量不经 tproxy，tcpdump 伴生容器抓包 |

## 术语表（glossary）

- **API 域名端点**: 有 DNS 域名的 HTTPS/HTTP 服务（登录、行情 API、资讯、CDN、遥测）。域名规则可覆盖。
- **裸 IP 行情端点**: API 动态下发的行情推送长连 TCP 服务器，无 PTR、IP 会漂移。域名规则天然不可覆盖，靠 ip_cidr /32 + process_name 兜底。
- **CN 加速端点**: 大陆运营商机房（如江苏电信 8080）的加速接入。按 Q3 决策同样走 proxy。
- **字面全量 proxy**: FTNN 全部进程的一切出站流量（无论域名/IP/端口）均经 proxy 出站，无 direct 例外。
- **验证回放**: 在干净容器中按采集清单逐条发起请求，经 mixed 入站进 sing-box，用 clash_api 断言路由结果的验收方法。

## 执行阶段

1. [x] 静态提取: podman 容器内解包 16.31 deb + FTAPI4JS 7z，rg 全量扫域名/IP
2. [x] 社区已知清单交叉验证（web 检索）
3. [x] 容器动态采集: 构建镜像 → 拷数据目录 → 退宿主 FTNN → GUI 会话点全功能 + tcpdump（SNI+DNS）
4. [x] 会话后二次静态扫容器内数据目录（运行时下发的 server list）
5. [x] 合并生成 `/etc/sing-box/rules/futu.json`（v2 格式，对齐 custom-proxy.json）
6. [x] 宿主机一次性变更: 备份 → clash_api + futu.json 注册(route+dns) + process_name 规则 → 重启
7. [x] 容器验证回放 + clash_api 断言（含反向断言：富途相关 IP 无 direct）
8. [x] 宿主 FTNN 升级 16.31 + 实机全功能复点，clash_api 确认全走 proxy
9. [x] 收尾: implementation.md 记录最终清单与结论

## 验收标准

1. futu.json 覆盖：静态提取 ∪ 动态采集 ∪ 社区清单 三源合并，无未解释差异
2. 回放断言：清单内每个域名经 mixed 入站测一轮，clash_api 显示出站=proxy，通过率 100%
3. 反向断言：clash_api 连接历史中富途相关 IP/域名无一走 direct
4. 实机确认：宿主 16.31 版 FTNN 全功能操作后，其全部连接出站=proxy（含 221.229.x 等裸 IP 端点）

## 风险与缓解

- 容器 GUI 掉登录 → 用户容器内重登（已确认可接受）
- `process_name` 规则在 TProxy 场景可能不生效 → 实测，无效则移除，域名+/32 清单仍生效
- 行情裸 IP 漂移导致 /32 失效 → process_name 兜底（若生效）；否则依赖 final=proxy + 反向断言定期复核
- 字面全量 proxy 可能使 CN 加速行情线变慢/失效 → 用户明确接受（Q3），若后续行情异常可再评估例外

## 性能与容量说明

本任务为网络配置调查与路由规则变更，不涉及数据库/服务端代码，AGENTS.md Step G 性能门不触发。
唯一容量相关点：futu.json 规则条目约 30–60 条，rule-set 匹配为内存哈希/前缀树，性能影响可忽略。
