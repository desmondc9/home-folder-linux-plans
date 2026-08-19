#!/bin/bash
# sing-box rule-set 智能更新脚本
# 触发 sing-box 重新下载 rule-set(利用其内置的 update_interval 机制)

set -euo pipefail

LOG_TAG="sing-box-rules-update"

# 检查 sing-box 是否运行
if ! systemctl is-active --quiet sing-box; then
  echo "[$LOG_TAG] sing-box not running, skip update"
  exit 0
fi

# 获取上次更新时间
LAST_UPDATE=$(journalctl -u sing-box --since "-7 days" --no-pager | grep "updated rule-set" | tail -1 | awk '{print $1, $2}' || echo "never")
echo "[$LOG_TAG] Last rule-set update: $LAST_UPDATE"

# 计算距离上次更新的天数
if [[ "$LAST_UPDATE" != "never" ]]; then
  last_timestamp=$(date -d "$LAST_UPDATE" +%s 2>/dev/null || echo 0)
  days_ago=$(( ($(date +%s) - last_timestamp) / 86400 ))
  echo "[$LOG_TAG] Days since last update: $days_ago"

  # 如果超过 6 天没更新,触发更新
  if [[ $days_ago -ge 6 ]]; then
    echo "[$LOG_TAG] Triggering sing-box rule-set update (restart)..."
    systemctl restart sing-box
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
    echo "[$LOG_TAG] Rule-sets are recent (updated $days_ago days ago), no action needed"
  fi
else
  echo "[$LOG_TAG] No previous update found, triggering initial update..."
  systemctl restart sing-box
  sleep 5
  echo "[$LOG_TAG] ✅ Initial rule-set download triggered"
fi
