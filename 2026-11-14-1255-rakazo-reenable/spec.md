# Rakazo 重启（re-enable）@ v0.11.0

- 环境: 同 [2026-11-12-1517-rakazo-deploy](../2026-11-12-1517-rakazo-deploy/)（Bandwagon VPS；nginx 已于 11-14 升至 1.28.3；**NOPASSWD sudo 于 11-14 12:00 移除**，opencode 配置同步 `deny sudo *`）
- 日期: 2026-11-14
- 状态: 重启完成并验收（全新实例，旧卷/.env 已于停用时销毁，无迁移）；pin 官方 v0.11.0（11-13 发布）
- 权威档案: 私有仓 desmondc9/rakazo-deploy（Issue #5、PR #6/#7、`plans/2026-11-14-1255-rakazo-reenable/`）

## 做了什么

- repo 解档：恢复 `daily-upgrade.yml`（8dafa52 历史还原）、四件套+RAKAZO_VERSION pin v0.11.0（diff 审查：Teams 可选 env 透传 + worker GC flag，无新必填 secret）、README 换横幅（PR #6）
- 机器重放：Cloudflare A/AAAA 重建 → installer 全新 `.env`（6 新随机 secret）+ overlay → 容器栈 pull/up 全 healthy（Docker，沿用 11-12 的技术选型，用户 11-14 再次确认接受）→ bootstrap 账号 → 新 deploy key + secret → force dispatch 全链路绿（run 43560250990）
- **运维模型变化**：root 三步（egress 规章/两段式 vhost+LE 证书 2027-02-12/nginx reload）因 sudo 收紧改由**用户在自有终端**执行一次性脚本 `/tmp/opencode/rakazo-host-setup-root.sh`；repo 的 host-setup.sh 同步适配交互式 sudo（PR #7），今后 vhost 类变更在交互终端重放

## 关键结论

1. agent 无 sudo 时代的部署分工：无 root 依赖的部分（docker 组操作、DNS API、gh secret、workflow）agent 可完成；root 依赖收敛为一个幂等脚本交用户执行——该模式可复用到日后其他部署任务。
2. v0.10→v0.11 官方四件套中 installer/egress/env example 逐字节相同，仅 compose 9 行变更——pin 升级审查成本极低。
3. nginx 1.28.3 对全站 vhost（auth/books/derp/headscale/reading/rakazo）报 `listen … http2` deprecation 警告：全站遗留写法，功能无影响，未处理（非本任务范围）。
