#!/bin/bash
# 报告流水线看门狗 · 状态探针（由 trigger 脚本调用，输出一行状态）
# S=今日日报是否含 SCAN-COMPLETE哨兵  M=今日晨报已发标记  R1=扫描job运行中(ms|no)  R2=晨报job运行中(ms|no)
D=$(date +%F)
LIB=/home/desmond/reports/全球机构研究报告库
OC=/home/desmond/.nvm/versions/node/v26.8.1/bin/openclaw
J_SCAN=72bbfb86-6a82-4563-a4e1-911abc3e75c8
J_BRIEF=c93a7761-7fd8-40b5-ac86-f451712424af
S=N; M=N
[ -f "$LIB/日报/$D.md" ] && grep -q 'SCAN-COMPLETE' "$LIB/日报/$D.md" && S=Y
[ -f "$LIB/日报/$D.简报已发" ] && M=Y
R1=$("$OC" automations get "$J_SCAN" 2>/dev/null | jq -r '.state.runningAtMs // "no"')
R2=$("$OC" automations get "$J_BRIEF" 2>/dev/null | jq -r '.state.runningAtMs // "no"')
echo "S=$S M=$M R1=$R1 R2=$R2"
