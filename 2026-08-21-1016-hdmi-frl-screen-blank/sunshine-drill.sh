#!/usr/bin/env bash
# sunshine-drill.sh — 串流可用性演练:主动制造锁屏/熄屏/崩溃等状态,
# 每个状态下强制 Sunshine 重启探测,验证 KMS 抓屏是否可用。
# 用法: sunshine-drill.sh   (约 4 分钟;期间 Sunshine 会多次重启,串流会断)
set -u
UNIT=app-dev.lizardbyte.app.Sunshine.service
PASS=0; FAIL=0

probe() {  # 重启 Sunshine 强制编码器/显示器探测,返回 PASS/FAIL
    systemctl --user reset-failed "$UNIT" 2>/dev/null
    systemctl --user restart "$UNIT" 2>/dev/null
    sleep 12
    if journalctl --user -u "$UNIT" --since "-15 s" --no-pager | grep -q "Found connector ID"; then
        echo PASS
    else
        echo FAIL
    fi
}

report() {  # $1=场景名 $2=结果
    printf "%-44s %s\n" "$1" "$2"
    [ "$2" = PASS ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
}

wait_dpms_on() {  # 等 watchdog 把屏幕救回来,最多 100s
    for _ in $(seq 1 20); do
        kscreen-doctor --dpms show 2>/dev/null | grep -q ": off" || return 0
        sleep 5
    done
    return 1
}

echo "=== Sunshine 串流可用性演练 $(date '+%F %T') ==="

r=$(probe); report "S0 基线(未锁屏,屏幕亮)" "$r"

loginctl lock-session; sleep 3
r=$(probe); report "S1 锁屏状态" "$r"

kscreen-doctor --dpms off
for _ in $(seq 1 6); do sleep 2; kscreen-doctor --dpms show 2>/dev/null | grep -q ": off" && break; done  # dpms off 异步生效,最多等 12s
s=$(journalctl --user -u "$UNIT" --since "-15 s" --no-pager | grep -c "Found connector ID")
if kscreen-doctor --dpms show | grep -q ": off"; then report "S2a 手动熄屏已被制造(检测正确)" PASS; else report "S2a 手动熄屏已被制造(检测正确)" FAIL; fi
if wait_dpms_on; then report "S2b watchdog ≤100s 自动救回屏幕" PASS; else report "S2b watchdog ≤100s 自动救回屏幕" FAIL; fi
r=$(probe); report "S2c 救回后 Sunshine 探测可用" "$r"

systemctl --user kill -s SIGKILL "$UNIT" 2>/dev/null
sleep 3
ok=FAIL
for _ in $(seq 1 20); do
    if systemctl --user is-active --quiet "$UNIT" && ss -tln | grep -q ":48010 "; then ok=PASS; break; fi
    sleep 5
done
report "S3a 崩溃后 ≤100s 服务自动恢复" "$ok"
r=$(probe); report "S3b 恢复后 Sunshine 探测可用" "$r"

echo "=== 结果: $PASS PASS / $FAIL FAIL ==="
echo "剩最后一步人工验证: 现在从 iPad/Android 用 Moonlight 连一次,应即连即通。"
[ "$FAIL" -eq 0 ]
