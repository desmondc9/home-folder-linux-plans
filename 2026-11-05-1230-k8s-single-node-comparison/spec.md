# 单节点 K8s 发行版选型调研：Minikube vs K3s vs MicroK8s

- 环境: Bandwagon VPS（Ubuntu 24.04.4 LTS x86_64，内核 6.8.0-147-generic，8G 内存（已用约 1.5G）/ 6 vCPU / 160G 磁盘已用 65G；10G swapfile 开启；cgroup v2；AppArmor 已加载；snapd 2.76.3 正常）。已跑常驻服务：docker+containerd（signal-align-auth、books-and-articles、reading-app 等 compose 负载）、nginx（占 80/443）、headscale、derper、tailscaled、frps、sing-box、fail2ban、haveged；另有 podman 4.9.3（rootless，未用）。（**更正 2026-11-14**：原文盘点误列 LibreChat/redis/rustfs/codeapi 为在跑负载——四栈已于 2026-09-22 随 LibreChat 停栈 `down --rmi all` 下线，见 [ADR-0010](../2026-09-22-1957-librechat-stack-shutdown/adr-0010-decommission-librechat.md)，此处沿用了停机前旧清单。按容器创建时间核实，2026-11-05 当日实际在跑的 compose 容器为 signal-align-auth ×3、books-and-articles-api（2026-09-23 起）、reading-app-api（2026-11-03 起）。）
- 日期: 2026-11-05
- 状态: 调研完成，结论 K3s 单节点为首选（渐进路线：新服务先上 k3s，旧服务留 docker）；未部署。

## 背景与目标

想在这台 VPS 上装一个"类 Kubernetes 的单节点集群"，主要目的是**让今后迁移到 Kubernetes 时环境统一**（现在就按 k8s 方式管理工作负载，将来迁真集群时平滑）。指定调研 Minikube / K3s / MicroK8s 三个产品。

## 范围

- In：三产品的最新版本/治理/许可证/CNCF 一致性认证（逐版本核对 k8s-conformance 仓库）、资源要求、与本机约束（80/443 被 nginx 占、10G swap、docker 共存、sing-box/tailscale/frp 网络栈）的冲突分析、compose→k8s 迁移路径、运维负担与风险。全部 2026-11-05 当日核实一手来源。
- Out：实际安装部署（后续任务）、多节点/HA、性能压测。

## 关键结论

详见 [k8s-single-node-comparison-research.md](./k8s-single-node-comparison-research.md)，逐条带官方来源。

### 排序：K3s ≫ MicroK8s > Minikube

| | K3s（首选） | MicroK8s | Minikube |
|---|---|---|---|
| 最新版 | **v1.37.2+k3s1**（2026-11-03，跟进上游最新） | v1.36（源码 2026-05；snap 商店默认横幅仍 1.35/stable，装前 `snap info` 实测） | v1.39.0（2026-09-02） |
| CNCF 一致性认证 | 每个版本都认证，至 v1.37 | 至 v1.36 | **当前版本（v1.36/1.37）无认证记录**（仅 v1.33/v1.35 有条目） |
| 资源口径 | server 最低 2C/2G；官方实测画像 server+负载 **≈1596MB**（最轻） | 最低 540MB 可跑，**官方推荐整机 4G** | 需 2G 空闲内存 |
| 常驻 | systemd 官方支持、崩溃/重启自动拉起 | 保持运行即自启；snap 默认**每天自动刷新 4 次** | **官方定位"learning and development"**；无 systemd 自启；LoadBalancer 靠前台 `minikube tunnel` |
| 80/443 冲突 | `--disable=traefik --disable=servicelb` 两个 flag 让出 | ingress addon **硬编码 hostPort 80/443**，需改 addon values | 不占宿主 80/443 |

### K3s 关键事实

- 单二进制（<100MB）内置 containerd 2.3.7（与系统 docker 互不干扰）、默认 SQLite datastore（经 kine）、Flannel VXLAN、CoreDNS、local-path-provisioner、metrics-server。
- **swap**：上游 kubelet 默认拒绝 swap 节点，但 K3s 源码写死 `FailSwapOn:false`（`pkg/daemons/agent/agent.go` L180）——**本机 10G swap 开着可直接跑**，Pod 默认 NoSwap 语义。
- 备份：SQLite 官方口径 = 停机后 tar 打包 `/var/lib/rancher/k3s/server/db/` + **必须带上 `server/token`**（丢失则快照不可用）。
- 安全：6443 绝不对公网（只放行 tailnet 网段 100.64.0.0/10）；flannel VXLAN UDP 8472 官方禁止暴露公网（单机自闭环，防火墙封外部入向）。
- 已知坑：2026-06 起 Traefik chart v40 把 Service 类型键 `service.type` 改为 `service.spec.type`，旧键**被静默忽略**；禁用 servicelb 后 LB Service 会一直 pending（NodePort 仍分配）。

### 迁移路径（与"统一环境"目标）

- kompose 活跃（v1.34.0、kubernetes.io 官方任务页在列）可做 compose→manifests 初稿，再人工修探针/限额/密钥。
- **渐进路线（推荐）**：reading-app/signal-align-auth 等已稳定服务留 docker compose；新服务（如 NATS JetStream）直接以 manifests/Helm 进 K3s（local-path 提供 PV）；跑顺后按需逐个迁旧服务。全量双轨对 8G 内存不友好。（更正 2026-11-14：原示例 LibreChat/rustfs 已于 2026-09-22 下线，示例替换为在跑负载。）
- 环境统一成色：K3s/MicroK8s 均为认证发行版，manifest/Helm/kubectl/GitOps 资产可直接搬；**不要**把核心工作负载绑在 K3s 的 HelmChartConfig/auto-deploy 或 MicroK8s addon 等发行版扩展上。

## 决策

**K3s 单节点**（systemd 常驻 + 认证至最新版 + 官方资源数字最轻 + 两个 flag 让出 80/443 + 备份一条 tar 命令 + 6443 走 tailnet）。安装基线：

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - \
  --disable=traefik --disable=servicelb \
  --tls-san=<tailnet 主机名/IP>
# 回滚：/usr/local/bin/k3s-uninstall.sh
```

与 nginx 的 Ingress 共存三选一（复杂度递增）：① nginx 做 edge 反代 k8s NodePort（起步推荐）；② Traefik 保留但 hostPort 改 8081/8444 由 nginx 443 反代（保留 Ingress 资源语义，注意 chart v40 变更）；③ MetalLB（单机不建议）。

## 风险与缓解

- **iptables 共存未经验证**（最大未知）：三产品与 sing-box/tailscale/frp 的 iptables 共存均无官方说法——上线前实测 derp/frp/代理链路回归；故障且 1~2 小时定位不了 → `k3s-uninstall.sh` 回滚回 docker compose。
- 内存水位：1.5G 现有 + ~1.6G K3s + 应用 ≤4G，8G 内有余地；若内存空闲长期 <3G 或 swap 频繁换入换出 → 暂缓迁移。
- 运维注意力：升级（单节点=短暂停机，选维护窗；重跑 install 脚本或 system-upgrade-controller）、备份（低峰 cron tar db+token 异机）、证书（K3s 自动处理）。

## 参考

- [k8s-single-node-comparison-research.md](./k8s-single-node-comparison-research.md) — 全量调研（A 逐产品档案 / B 横向对比 / C 结论与落地清单），报告原生成于 `~/docs/`（research 技能产物），归档时迁入。
- 前置调研：[2026-11-05-0847-mq-research-kafka-nats](../2026-11-05-0847-mq-research-kafka-nats/)（NATS JetStream 为"新服务先进 k3s"的第一个候选）。
- compose 负载位置：在跑——`~/reading-app` 等；已停栈（2026-09-22 下线，配置目录与 `.env` 保留）——`~/librechat-deploy`、`~/redis-deploy`、`~/rustfs-deploy`。（更正 2026-11-14：原文未区分在跑/已停。）
