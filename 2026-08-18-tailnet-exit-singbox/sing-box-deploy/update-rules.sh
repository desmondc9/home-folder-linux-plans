#!/bin/bash
# sing-box rule-set 智能更新脚本
# 下载远程 rule-set 比对 hash,有变化才触发 sing-box 重新加载

set -euo pipefail

LOG_TAG="sing-box-rules-update"
RULE_SETS=(
  "geosite-cn:https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
  "geoip-cn:https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
  "geosite-greatfire:https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-greatfire.srs"
)

CACHE_DIR="/var/lib/sing-box/rule-set-hashes"
mkdir -p "$CACHE_DIR"

# 检查 sing-box 是否运行
if ! systemctl is-active --quiet sing-box; then
  echo "[$LOG_TAG] sing-box not running, skip update check"
  exit 0
fi

UPDATED=false
for rule_set in "${RULE_SETS[@]}"; do
  name="${rule_set%%:*}"
  url="${rule_set#*:}"  # 只去掉第一个冒号(保留 https://)
  hash_file="$CACHE_DIR/$name.sha256"

  echo "[$LOG_TAG] Checking $name..."

  # 下载远程文件到临时位置(通过环境变量中的代理,在 service 文件中配置)
  tmp_file=$(mktemp)
  set +e  # 允许 curl 失败不退出脚本
  curl_output=$(curl -sL --max-time 30 -o "$tmp_file" "$url" 2>&1)
  curl_exit=$?
  set -e
  if [[ $curl_exit -ne 0 ]]; then
    echo "[$LOG_TAG]   ⚠️  Download failed (curl exit $curl_exit): $curl_output"
    rm -f "$tmp_file"
    continue
  fi

  # 检查下载是否成功(文件非空)
  if [[ ! -s "$tmp_file" ]]; then
    echo "[$LOG_TAG]   ⚠️  Download failed (empty file), skip"
    rm -f "$tmp_file"
    continue
  fi

  # 计算 hash
  remote_hash=$(sha256sum "$tmp_file" | awk '{print $1}')
  local_hash=$(cat "$hash_file" 2>/dev/null || echo "none")

  if [[ "$remote_hash" != "$local_hash" ]]; then
    echo "[$LOG_TAG]   ✓ Hash changed (${local_hash:0:8}... → ${remote_hash:0:8}...), update needed"
    UPDATED=true
    echo "$remote_hash" > "$hash_file"
  else
    echo "[$LOG_TAG]   ✓ Up-to-date (${remote_hash:0:8}...)"
  fi

  rm -f "$tmp_file"
done

if [[ "$UPDATED" == "true" ]]; then
  echo "[$LOG_TAG] Triggering sing-box rule-set reload (restart)..."
  echo "[$LOG_TAG] ⚠️  This will briefly interrupt the proxy (10809)"
  systemctl restart sing-box

  # 等待 sing-box 恢复
  sleep 5

  # 验证更新成功
  if journalctl -u sing-box --since "-1min" --no-pager | grep -q "updated rule-set"; then
    echo "[$LOG_TAG] ✅ Rule-sets updated successfully"
    journalctl -u sing-box --since "-1min" --no-pager | grep "updated rule-set" | while read -r line; do
      echo "[$LOG_TAG]   $line"
    done
  else
    echo "[$LOG_TAG] ⚠️  Update triggered but no confirmation in logs"
  fi
else
  echo "[$LOG_TAG] All rule-sets are up-to-date, no action needed"
fi
