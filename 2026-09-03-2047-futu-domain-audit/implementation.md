# 富途端点清单采集与 sing-box 全量代理 — 实施记录

- 日期: 2026-09-03
- 关联: spec.md(本目录) | 产物: `/etc/sing-box/rules/futu.json` + config.json 变更
- 状态: **完成，全部验收通过**

## 最终产物

- `/etc/sing-box/rules/futu.json`: 37 个 `domain_suffix`（用户裁剪后，仅富途自有域名；剔除第三方
  qcloud/my-imcloud/NTP 精确域名与全部 ip_cidr /32）
- `/etc/sing-box/config.json`（备份 `config.json.bak-20260903-futu`）:
  - route: `process_name: [FTNN, NNPython, FTWeb, CrashReporter] → proxy`（置于 custom-proxy 之后）
  - route: `rule_set: futu → proxy`
  - dns: `rule_set: futu → cfdoh`（防污染）
  - experimental: clash_api `127.0.0.1:9090`

## 验收结果

| 验收项 | 结果 |
|---|---|
| 回放断言 37/37 后缀 → proxy（rule_set=futu） | ✅ 37/37 PASS |
| 反向断言（futu/moomoo 相关连接无 direct） | ✅ 无漏网 |
| 实机 FTNN 16.31（含交易）live 断言 | ✅ 全部 chains=proxy，含裸 IP `221.229.52.198:8080`（江苏电信行情线，本会被 geoip-cn 判 direct）经 **process_name** 兜底进 proxy |
| process_name 规则在 TProxy 下生效 | ✅ 实测生效（clash_api 的 process 字段仅展示层不填充，规则匹配正常） |

## 关键发现

1. **双线路接入机制**: FTNN 用 `www.baidu.com/www.google.com/www.cloudflare.com/www.msftncsi.com/www.aliyun.com`
   探测线路，大陆可达时富途 API 域名解析到 CN 优化边缘（观测到 `114.230.198.90` 江苏电信，
   与 EdgeOne `43.175.x` 服务同批域名），不可达时走 EdgeOne 国际。
2. **连接服务器家族**: 行情 `roaconn*/inconn*`、交易 `omsconn*/jpomsconn*`（futuoa.com 及
   futunn.com 下编号百级），运行时数据目录实测 337 个域名，全部塌缩进 37 个主域后缀。
3. **域名来源**: 主二进制无明文域名（加密/下发），`libCoreBiz.so` 内嵌 dot-suffix 域名表
   （`futu88.com`、`ftesop.com` 即从此发现；`future.cc` 为 libstdc++ 路径假阳性已剔除）。
4. **第三方依赖**（已按用户决定移出规则）: 腾讯防水墙 `sg/turing.captcha.qcloud.com`、
   腾讯 IM `shortconn.im.qcloud.com` + `*.my-imcloud.com`、NTP `time1-5.cloud.tencent.com`；
   桌面端由 process_name 兜底覆盖，不影响"字面全量"。

## 偏差与已知事项

- **容器内 GUI 富途**: 三处启动坑已解（`libpulse.so.0` 缺失静默退出、Qt xcb 缺
  `libxcb-shape0`、交易页稳定 SIGABRT——软件渲染无效，原因未深究）。交易链路改为宿主机
  实机验证，效果等价（见验收表）。
- **验证回放位置**: 因 rootless podman(pasta) 不回环宿主 IP 监听端口，回放从容器改为宿主侧
  `127.0.0.1:10809`；路由决策与流量来源无关，规则链一致。
- **用户裁剪影响（手机侧）**: ip_cidr 全移除后，手机若复用 futu.json，裸 IP 行情端点不在
  覆盖范围——按 Q7 决策用 sing-box Android per-app VPN 补齐。
- **行情延迟观察点**: CN 优化行情线（221.229.x:8080）现按 Q3 决策走 proxy；若行情明显
  卡顿/掉线，回来重评"CN 端点直连例外"（规则改回一条 ip_cidr + direct 即可，清单在
  /tmp/opencode/futu-live/diag/ 备份，注意该目录属 tmp，重要结论已录入本文）。

## 性能与容量（AGENTS.md Step G）

路由规则变更，无服务端代码。37 条后缀 + 1 条 process_name 规则，rule-set 前缀树匹配，
开销可忽略；唯一容量相关风险即上述 CN 行情线 proxy 化的延迟，已列观察点。

## 环境清理

- futu-live/verify 容器与镜像、构建目录、431MB 数据目录副本、xhost +local: 已全部撤销。
- 保留: `/tmp/opencode/futu-live/diag/`（23MB: 3 段 pcap + SNI/DNS/IP 提取物，tmp 重启即失）、
  `/tmp/opencode/futu-static/`（静态+社区清单）。

## 附录: v2rayNG 路由规则格式（2026-09-03 追加，手机端复用）

v2rayNG 自定义路由 domain 字段（单行，`domain:` 为子串匹配，子域名全覆盖）：

```
domain:futu.cn,domain:futu.link,domain:futu5.com,domain:futu88.com,domain:futuau.com,domain:futubos.com,domain:futuesop.com,domain:futufin.com,domain:futuhainan.com,domain:futuhk.com,domain:futuhk1.com,domain:futuhk2.com,domain:futuhk8.com,domain:futuhkapp.com,domain:futuhn.com,domain:futuhongkong.com,domain:futuie.com,domain:futulending.com,domain:futulti.com,domain:futunh.com,domain:futuniuniu.com,domain:futunn.com,domain:futunnn.com,domain:futuoa.com,domain:futusg.com,domain:futustatic.com,domain:fututrade.com,domain:fututradehub.com,domain:fututrust.com,domain:fututrustee.com,domain:moomoo.com,domain:moomooapp.com,domain:moomoobull.com,domain:moomoocn.com,domain:moomoocrypto.com,domain:moomooequity.com,domain:moomootrustee.com
```

注意：与 futu.json 同源（37 后缀），同样不含裸 IP 行情端点——v2rayNG 侧字面全量仍需
配合 per-app 代理（Q7 决策）。
