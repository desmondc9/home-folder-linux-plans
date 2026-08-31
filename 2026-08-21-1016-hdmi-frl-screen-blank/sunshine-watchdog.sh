#!/usr/bin/env bash
# Restart Sunshine if its service is "active" but it is not listening (half-dead zombie
# state, e.g. after a boot-time port collision — see moonlight-sunshine memory).
# Never touches a deliberately stopped service.
set -u
UNIT=app-dev.lizardbyte.app.Sunshine.service
PORT=48010

if ! systemctl --user is-active --quiet "$UNIT"; then
    exit 0   # stopped / failed / still activating on purpose — not our business
fi

# 屏幕自愈: Sunshine 走 KMS 抓屏,任何屏幕处于 DPMS off 时显示器枚举可能为空,
# Moonlight 连接即 500/503(2026-08-20 DPMS 闲置关屏事故;2026-08-21 HDMI FRL
# 重训练事故)。Sunshine 运行中就强制屏幕通电。代价:  Sunshine 运行期间无法手动关屏。
if command -v kscreen-doctor >/dev/null 2>&1 && \
   kscreen-doctor --dpms show 2>/dev/null | grep -q ": off"; then
    echo "Sunshine active but a screen is DPMS-off — forcing displays on. State:"
    kscreen-doctor --dpms show 2>/dev/null
    kscreen-doctor --dpms on 2>/dev/null || true
fi

# 捕获自校准: output_name 是枚举序号,顺序会随重启/显示器热插拔翻转(2026-08-21
# 实测: 小米外接屏待机从总线消失后枚举只剩 eDP;上线时可能 HDMI=Monitor 0)。
# 按最近一次启动日志的 "Monitor N is eDP-1" 校准,保证捕获永远落在内屏(connector 140)。
# 枚举在同一进程运行期内稳定,校准后直到下次重启都正确。振荡护栏: 10 分钟内最多校准 2 次。
CONF="$HOME/.config/sunshine/sunshine.conf"
CUR=$(grep -E '^\s*output_name' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' \t')
START_TS=$(systemctl --user show "$UNIT" -p ActiveEnterTimestamp --value 2>/dev/null)
# 只取 "Monitor N" 里的第一个数字: 用 grep -oE "[0-9]+" 会把 "eDP-1" 的 1 也带出来,
# 变成多行变量把 sed 脚本冲坏(2026-08-21 实测: 文件纹丝不动,Sunshine 读到旧值)。
CAL_LOG=$(journalctl --user -u "$UNIT" --since "${START_TS:-yesterday}" --no-pager 2>/dev/null \
          | grep -oE "Monitor [0-9]+ is eDP-1" | tail -1 | sed -nE 's/^Monitor ([0-9]+).*/\1/p')
if [ -n "${CAL_LOG:-}" ] && [ -n "${CUR:-}" ] && [ "$CAL_LOG" != "$CUR" ]; then
    CAL_STATE="$HOME/.cache/sunshine-watchdog-cal"
    now=$(date +%s); ts=0; count=0
    if [ -f "$CAL_STATE" ]; then
        ts=$(sed -n '1p' "$CAL_STATE"); count=$(sed -n '2p' "$CAL_STATE")
    fi
    if [ $((now - ts)) -ge 600 ]; then count=0; fi
    if [ "$count" -lt 2 ]; then
        echo "枚举翻转: 配置 output_name=$CUR,启动日志 eDP-1=$CAL_LOG — 校准并重启 Sunshine"
        # 必须先 stop 再改配置: Sunshine 退出时会用内存配置回写 sunshine.conf,
        # sed 在 restart 之前改会被旧进程退出时的回写覆盖(2026-08-21 实测踩坑)。
        systemctl --user stop "$UNIT"
        sed -i -E "s|^\s*output_name.*|output_name = $CAL_LOG|" "$CONF"
        printf '%s\n%s\n' "$now" $((count + 1)) > "$CAL_STATE"
        systemctl --user reset-failed "$UNIT" 2>/dev/null || true
        systemctl --user start "$UNIT"
    fi
fi

if ss -tln | grep -q ":$PORT "; then
    exit 0   # healthy
fi

# Zombie state: snapshot who (if anyone) holds the port for post-mortem, then restart.
echo "Sunshine active but port $PORT not listening — restarting. Holders at trigger time:"
ss -tlnp | grep ":$PORT " || echo "(port free — sunshine never bound it or dropped its listeners)"
systemctl --user restart "$UNIT"
