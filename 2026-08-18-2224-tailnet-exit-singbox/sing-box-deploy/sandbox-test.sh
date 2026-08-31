#!/bin/bash
# 沙盒内执行:加载 nft + 策略路由,启动 sing-box,全链路测试
set -x

# 1. nftables + 策略路由
nft -f /deploy/tproxy.nft || { echo "== NFT-FAIL =="; exit 1; }
ip rule add fwmark 1 lookup 100 || { echo "== RULE-FAIL =="; exit 1; }
ip route add local 0.0.0.0/0 dev lo table 100 || { echo "== ROUTE-FAIL =="; exit 1; }
ip -6 rule add fwmark 1 lookup 100
ip -6 route add local ::/0 dev lo table 100

# 2. DNS 指向 223.5.5.5(应被 TPROXY 劫进 sing-box 分流解析)
echo 'nameserver 223.5.5.5' > /etc/resolv.conf

# 3. sing-box 启动
mkdir -p /etc/sing-box/rules
cp /deploy/config.json /etc/sing-box/config.json
cp /deploy/rules/*.json /etc/sing-box/rules/
sing-box run -c /etc/sing-box/config.json > /tmp/singbox.log 2>&1 &
SBPID=$!
for i in $(seq 1 40); do
  grep -q "sing-box started" /tmp/singbox.log 2>/dev/null && break
  if grep -q "FATAL" /tmp/singbox.log 2>/dev/null; then
    echo "== SINGBOX-FATAL =="; tail -20 /tmp/singbox.log; kill $SBPID 2>/dev/null; exit 1
  fi
  sleep 1
done
sleep 2

echo ""
echo "===== TESTS ====="
echo "-- 1. DNS 劫持(dig 走 resolv.conf=223.5.5.5) --"
dig +time=4 +tries=1 www.taobao.com +short
dig +time=4 +tries=1 www.google.com +short
echo "-- 2. 国内直连 --"
curl -4 -s --max-time 10 -o /dev/null -w "baidu: %{http_code}\n" https://www.baidu.com
curl -4 -s --max-time 10 "https://myip.ipip.net"
echo "-- 3. 国外走代理 --"
curl -4 -s --max-time 12 -o /dev/null -w "google: %{http_code}\n" https://www.google.com
IPFY=$(curl -4 -s --max-time 12 https://api.ipify.org)
echo "ipify: $IPFY (期望 104.194.83.82)"
echo "-- 4. Anthropic API --"
curl -4 -s --max-time 10 -o /dev/null -w "anthropic: %{http_code}\n" https://api.anthropic.com/
echo ""
echo "===== sing-box log tail ====="
tail -25 /tmp/singbox.log
kill $SBPID 2>/dev/null
