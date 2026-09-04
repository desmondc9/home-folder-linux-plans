# sing-box 代理故障诊断与修复 — QUIC block 出站引用失效

- 日期: 2026-09-03
- 主题: youtube.com 等被代理网页无法浏览
- 诊断方法: diagnosing-bugs skill (反馈回路 → 复现 → 假设 → 验证 → 修复)

## 症状

2026-09-03 17:17–17:37 期间,浏览器无法打开 youtube.com 等需走代理的网页;
sing-box 日志持续刷 `ERROR router: outbound not found: block`(当天 08:30 起 7199+ 次)。

## 根因(两个独立问题叠加)

### 1. 急性故障(已自愈): 手动停止服务

17:17:42 用户在 pts/5 手动执行 `sudo systemctl stop sing-box.service` +
`stop sing-box-tproxy.service`,17:21:17 才重新 start。
**17:17:42–17:21:17 之间全部代理流量黑洞** —— 这是"youtube 打不开"的直接原因。
(用户已确认是本人操作,目的性操作,非遗漏。)

### 2. 慢性缺陷(本次修复): 引用已移除的内置 `block` 出站

`/etc/sing-box/config.json:45` 原为:

```json
{ "network": "udp", "port": 443, "outbound": "block" },
```

内置 `block` 出站在 sing-box 1.12+ 已被移除(1.11 引入规则动作 `action: reject` 替代),
当前版本 1.13.19(2026-08-18 apt 安装)。后果:

- 所有 QUIC/HTTP3(UDP:443)连接匹配该规则时逐条报 `outbound not found: block`,被黑洞超时而非快速拒绝;
- Chrome 的 HTTP/3 请求超时后才回落 TCP,页面/视频卡顿;重启服务后用户 17:37 重试仍异常与此有关;
- `sing-box check` **不校验**悬空的 outbound 引用,配置能正常启动,问题只在运行时暴露 —— 这就是 8 月 19 日换 1.13 配置后一直没被发现的原因。

## 已排除的假设

| 假设 | 结论 | 证据 |
|---|---|---|
| DNS 污染 | 排除 | 日志显示 cfdoh(经代理)解析 youtube 得到干净的 142.251.x.x |
| vless 服务器故障 | 排除 | mixed 入站经 vless 出站 curl youtube 200 |
| nftables/tproxy 规则异常 | 排除 | sing-box-tproxy 17:21:20 正常加载;tproxy v4/v6 路径 curl 均 200 |

## 修复

```diff
-      { "network": "udp", "port": 443, "outbound": "block" },
+      { "network": "udp", "port": 443, "action": "reject" },
```

备份: `/etc/sing-box/config.json.bak-20260903-blockfix`

## 验收标准

1. 向 UDP:443 发包不再产生 `outbound not found` ERROR(修复前 1 包→1 ERROR,修复后 1 包→0 ERROR)
2. 经 mixed 入站(127.0.0.1:10809)curl https://www.youtube.com 返回 200
3. 经 tproxy(本机直出,v4/v6)curl https://www.youtube.com 返回 200
4. 重启后日志无 `outbound not found`

## 遗留跟进

- `/etc/sing-box/android/config.json:105` 存在同样的 `"outbound": "block"` 引用
  (手机端配置,主服务不受影响——`-C /etc/sing-box` 不递归子目录;下次更新手机配置时需同步改为 `action: reject`)。
