#!/bin/bash
# TPROXY controlled test with auto-rollback
LOG=/tmp/tproxy-test.log
systemctl start sing-box-tproxy
sleep 2
{
  echo "== $(date +%H:%M:%S) tproxy started =="
  echo "-- dig via 223.5.5.5 (should go through sing-box dns) --"
  dig +time=3 +tries=1 @223.5.5.5 www.taobao.com A +short 2>&1 | head -3
  dig +time=3 +tries=1 @223.5.5.5 www.google.com A +short 2>&1 | head -3
  echo "-- resolved --"
  timeout 5 resolvectl query www.taobao.com 2>&1 | head -2
  timeout 5 resolvectl query www.google.com 2>&1 | head -2
  echo "-- domestic direct --"
  curl -4 -s --max-time 8 -o /dev/null -w "baidu: %{http_code}\n" https://www.baidu.com
  curl -4 -s --max-time 10 "https://myip.ipip.net" 2>&1 | head -1
  echo "-- foreign via proxy --"
  curl -4 -s --max-time 12 -o /dev/null -w "google: %{http_code}\n" https://www.google.com
  curl -4 -s --max-time 12 https://api.ipify.org 2>&1; echo
  echo "-- anthropic --"
  curl -4 -s --max-time 10 -o /dev/null -w "anthropic: %{http_code}\n" https://api.anthropic.com/
  echo "-- sing-box recent errors --"
  journalctl -u sing-box --since "-2min" --no-pager | grep -iE "error|warn|fatal" | tail -10
} > "$LOG" 2>&1

if grep -q "google: 200" "$LOG" && grep -q "baidu: 200" "$LOG"; then
  echo "== RESULT: ALL-PASS, tproxy left ON ==" >> "$LOG"
else
  systemctl stop sing-box-tproxy
  echo "== RESULT: FAIL, tproxy auto-stopped, network restored ==" >> "$LOG"
fi
cat "$LOG"
