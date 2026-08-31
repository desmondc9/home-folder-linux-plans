#!/usr/bin/env bash
# screen-wake-daemon.sh — 事件驱动屏幕唤醒 daemon。
#
# 两个职责:
#   1. 后台拉起 screen-wake-httpd.py(:47800 专用唤醒端点)
#   2. 每 2s 轮询 Sunshine/SSH 端口的入站连接,有连接且屏幕 DPMS off → 立即点亮
#
# 覆盖的触发源:
#   - Moonlight 点选电脑(HTTPS 47984 / HTTP 47989)
#   - Moonlight 启动串流(RTSP 48010)
#   - SSH 登录(22,含经 frp 转发进来的)
#   - curl http://<主机>:47800/任意路径
#
# 与 sunshine-watchdog.sh(每分钟兜底)互补: 本 daemon 把唤醒延迟从 ≤70s 压到 ≤3s,
# 消除"客户端在熄屏窗口内连接失败"的竞态。
set -u

# 入站连接: 本机是服务端,服务端口在"本地端口"(sport)一侧,dport 是客户端临时端口,别搞反。
# state connected = 除 LISTEN 外的所有活动状态(含握手/TIME_WAIT),
# 连 Sunshine 秒拒的裸 TCP 也算 —— 连接意图本身就值得唤醒。
WAKE_PORTS='( sport = :47984 or sport = :47989 or sport = :48010 or sport = :22 )'

wake_if_off() {  # $1 = 触发原因
    kscreen-doctor --dpms show 2>/dev/null | grep -q ": off" || return 0
    echo "$(date '+%F %T') 屏幕 off,因 [$1] 点亮"
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity 2>/dev/null || true
    kscreen-doctor --dpms on 2>/dev/null || true
}

# 专用 HTTP 唤醒端点
python3 "$HOME/.local/bin/screen-wake-httpd.py" &
HTTPD_PID=$!
trap 'kill "$HTTPD_PID" 2>/dev/null' EXIT

# 连接轮询(仅当确实有连接且屏幕关着才动作,避免无意义的重训练)
while true; do
    if ss -tn state connected "$WAKE_PORTS" 2>/dev/null | grep -qE ':(47984|47989|48010|22)\s'; then
        wake_if_off "入站连接 (Sunshine/SSH)"
    fi
    sleep 2
done
