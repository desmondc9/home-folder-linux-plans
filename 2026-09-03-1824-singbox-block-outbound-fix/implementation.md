# 实施记录 — sing-box block 出站引用修复

日期: 2026-09-03 | 状态: 已完成并验证

## 任务清单

- [x] 建立反馈回路: `curl -x http://127.0.0.1:10809 → youtube.com` + `bash -c 'echo garbage > /dev/udp/<ip>/443'` + journalctl 错误计数(zsh 无 /dev/udp,必须 bash -c)
- [x] 时间线还原: journalctl/sudo 日志确认 17:17:42 手动 stop → 17:21:17 start(急性故障窗口)
- [x] 定位慢性缺陷: config.json:45 引用已移除的 `block` 出站;`sing-box check` 不校验悬空引用,启动不报错
- [x] 红灯测试(修复前): 1 个 UDP:443 包 → 确定性触发 1 条 `ERROR router: outbound not found: block`
- [x] 准备修复: /tmp/opencode/singbox-fix/config.json(sd 单行替换),`sing-box check` 通过
- [x] HITL 安装(本环境 sudo 走 pam_howdy 交互认证,agent 无法代跑): 用户终端执行
      `sudo cp -a ...bak-20260903-blockfix && sudo install -m 644 ... && sudo systemctl restart sing-box`
- [x] 绿灯验证(修复后, 18:25:46 重启):
  - config 第 45 行 = `"action": "reject"`,服务 active
  - UDP:443 回归测试 → 0 条新 ERROR
  - PROXY→youtube: 200 (1.57s);TPROXY-v4→youtube: 200 (1.49s)
  - 重启后日志无 `outbound not found`

## 关键文件

| 文件 | 说明 |
|---|---|
| `/etc/sing-box/config.json` | 已修复(第 45 行) |
| `/etc/sing-box/config.json.bak-20260903-blockfix` | 修复前备份(保留) |
| `/tmp/opencode/singbox-fix/` | 修复暂存目录(已清理) |

## 性能与容量(Step G)

不触发: 纯系统配置 bug 修复,不涉及代码、SQL、缓存、批处理或容量变化;
唯一可观测收益是消除每日常规错误日志量(当天 7199+ 条)与 QUIC 超时带来的页面加载延迟。

## 经验教训

1. `sing-box check` 不校验 route 规则中 outbound 引用的存在性 —— 升级 sing-box 大版本后,
   引用内置 `block`/`dns` 出站的旧规则只会在运行时逐连接报错,需主动 grep 配置中的遗留引用。
2. 大版本升级(1.11→1.12+)时按官方迁移指引把 `outbound: block/dns` 改写为 `action: reject/hijack-dns`。
3. 非交互 agent 环境下 sudo(pam_howdy)不可用,系统级变更走"备好文件 + 用户一行命令安装"的 HITL 模式。
