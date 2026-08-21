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

if ss -tln | grep -q ":$PORT "; then
    exit 0   # healthy
fi

# Zombie state: snapshot who (if anyone) holds the port for post-mortem, then restart.
echo "Sunshine active but port $PORT not listening — restarting. Holders at trigger time:"
ss -tlnp | grep ":$PORT " || echo "(port free — sunshine never bound it or dropped its listeners)"
systemctl --user restart "$UNIT"
