# OpenClaw Gateway 无法启动修复(stale systemd unit)

- 日期:2026-09-06 21:05
- 类型:本机服务修复(无 repo 代码变更,无 PR)
- 状态:已修复并验证(gateway status --deep 全绿)

## 背景

`curl -fsSL https://openclaw.ai/install.sh | bash` 安装 v2026.9.2 后报
`Gateway is not running`,`openclaw gateway status --deep` 显示 systemd user service
disabled + inactive,connectivity probe ECONNREFUSED。

## 根因(systematic-debugging 四阶段)

1. `~/.config/systemd/user/openclaw-gateway.service` 是 4 月 12 日的旧版残留
   (v2026.4.11,指向 nvm node v24.12.0 路径,mode 664,内联 NOTION_API_KEY/
   OLLAMA_API_KEY/代理变量)
2. 今天的 install.sh 只更新了 CLI,没有覆盖/启用 service
3. `openclaw gateway install --force` 被权限检查拦截:unit 文件 group-writable(664)

## 修复步骤

```bash
chmod go-w ~/.config/systemd/user/openclaw-gateway.service{,.bak}
openclaw gateway install --force        # 重新生成 unit:新路径、密钥运行时加载、16007M heap
systemctl --user enable --now openclaw-gateway.service
```

## 验证

- Runtime: running, Connectivity probe: ok, dashboard HTTP 200, 18789 监听
- unit 重装后 inline secrets 警告消失

## 遗留(当时未处理)

- PATH 含 nvm 目录的 cosmetic 警告(建议 `openclaw doctor` 交互式处理)
- `agents.defaults.heartbeat.agentId` 未设置 → 心跳禁用(用户配置选择,保持不动)
- 日志另有 volcengine ark-code-latest 400 错误(模型配置问题,见下一条目处理)
