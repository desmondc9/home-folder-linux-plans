# Rakazo 自托管部署 @ rakazo.signal-align.com（含每日自动升级流水线）

- 环境: Bandwagon VPS（Ubuntu 24.04.4 LTS，8G 内存/6 vCPU/160G 盘；docker 29.1.3 + nginx 反代 + certbot + headscale/derper/tailscaled/frps/sing-box 共存；公网 95.169.0.65 + 2607:8700:5500:7bd3::2，DNS=Cloudflare）。新增第 6 个 nginx 子域名 vhost。
- 日期: 2026-11-12
- 状态: **已停用（2026-11-12 当日试用后弃用并完全清除）→ 2026-11-14 重新启用**，见 [2026-11-14-1255-rakazo-reenable](../2026-11-14-1255-rakazo-reenable/)（v0.11.0，全新实例）。停用清除清单见私有仓 implementation.md 停用记录段。
- 权威档案: 私有仓库 **desmondc9/rakazo-deploy**（保留为历史档案，已打 DECOMMISSIONED 横幅；`plans/2026-11-12-1517-rakazo-initial-deploy/` 含完整 spec/implementation/验收证据/停用记录）。本档案只做机器级变更摘要。

## 背景

按官方 SETUP_PROMPT 的 published-images 路径部署 [Rakazo](https://github.com/elie222/rakazo)（开源自托管 AI teammates，含 Docker 沙箱 bot 计算机），域名 `rakazo.signal-align.com`，并要求每日根据官方 release 自动升级。

## 关键决策

| 决策 | 理由 |
|---|---|
| Docker 而非 podman | 官方硬要求 Engine ≥26/API 1.45（bot 计算机卷子路径）；本机 podman 4.9 API 不足 |
| 固定 stable tag（v0.10.0）而非 `edge` | stable 有迁移契约；`edge` 是 main 构建流 |
| GH-hosted runner + SSH deploy key（同 librechat vps-cd.yml 惯例） | 不在生产机常驻 runner；key 带 `restrict`，可单点撤销 |
| Action bump 直推 main | Action 即本 repo 的 CD；人工配置改动仍走 PR |
| secrets 全在宿主 `.env`（官方 installer 生成） | 零密钥入 git；比 librechat 的 tofu 矩阵轻量，安全边界等价 |

## 机器级变更（新增/触碰面）

1. **DNS**：Cloudflare 新增 `rakazo` A/AAAA（DNS-only 灰云，同 apex 模式）
2. **nginx**：`sites-available/rakazo`（stream SNI→127.0.0.1:14443 proxy_protocol 既有模式；加 websocket upgrade map + `client_max_body_size 25m`）；源文件在 repo `nginx/rakazo.conf`，经 `host-setup.sh` 幂等安装
3. **证书**：certbot certonly --nginx 新签（2027-02-10 到期，certbot.timer 自动续）
4. **防火墙**：官方 `restrict-computer-egress.sh` → DOCKER-USER 链 + `rakazo-computer-egress.service`；仅 `rakazo-c*` 桥，不影响 librechat 等其他 compose 栈
5. **容器**：compose 项目 `rakazo`（postgres16 digest-pin + app:v0.10.0 ×4 服务 + computer 镜像）；web 127.0.0.1:5173、api 127.0.0.1:3100 仅 loopback，由 nginx 对外
6. **SSH**：新增专用 deploy key（restrict）供 Action 登录执行 `git pull + upgrade.sh`

## 资源占用评估（8G 内存机）

服务 mem caps 合计 6.5G（pg 2g/api 1.5g/worker 2g/supervisor .5g/web .5g），每台运行中 bot 计算机另 2G（默认上限）→ **同时运行计算机建议 ≤1**；观察 `docker stats --no-stream`。磁盘新增镜像约 3–4G（余 80G+）。

## 运维入口

- 手动重部署/升级/回滚：`cd ~/rakazo-deploy && bash scripts/upgrade.sh $(cat RAKAZO_VERSION)`（回滚=旧 tag，DB 迁移不回滚）
- 流水线：`gh workflow run daily-upgrade.yml -f force=true`（repo Actions 页看历史）
- 停止不删数据：`docker compose --env-file .env -f docker-compose.images.yml down`（绝不可 `-v`）
- 备份：`.env`（含不可轮换的 ENCRYPTION_KEY）+ pgdata 导出，命令在 repo README

## 风险与注意

- 升级失败自动回滚旧镜像 + revert pin 提交；**连续失败看 Action run + migrate 容器日志**
- ENCRYPTION_KEY 丢失=加密内容不可恢复，备份必含 `.env`
- GitHub 60 天无活动停用 scheduled workflow——升级 bump 提交维持活跃，停用手动 dispatch 复活
- 初始账号密码经会话一次性交付（未落任何文件），首登后已提示改密
