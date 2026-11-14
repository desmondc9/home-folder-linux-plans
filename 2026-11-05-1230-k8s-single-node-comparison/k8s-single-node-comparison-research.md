# 单节点"类 Kubernetes"方案调研：Minikube vs K3s vs MicroK8s

- **调研日期**：2026-11-05（所有版本号、认证状态、文档内容均于当日在线核实）
- **调研目的**：在已跑大量常驻服务的搬瓦工 VPS 上选型一个单节点 Kubernetes 发行版，目标是"现在就按 k8s 方式管理工作负载，将来迁到真正的集群时环境统一"

## 0. 机器现状与来源说明

### 0.1 机器现状（主会话当日核实，本报告直接引用）

| 项目 | 状态 |
|---|---|
| 系统 | Ubuntu 24.04.4 LTS x86_64，内核 6.8.0-147-generic |
| 资源 | 8G 内存（已用约 1.5G）/ 6 vCPU / 160G 磁盘（已用 65G） |
| swap | 10G swapfile 开启；cgroup v2 |
| 已跑服务 | docker.service + containerd.service（signal-align-auth、books-and-articles、reading-app 等 compose 工作负载；**更正 2026-11-14**：原文误列 LibreChat/redis/rustfs/codeapi——四栈已于 2026-09-22 全部下线（ADR-0010），此处沿用了停机前旧清单）；podman 4.9.3（rootless，无运行中容器） |
| 反代 | nginx.service 占用 80/443（**按"80/443 已被占用"约束分析**） |
| 网络/安全 | headscale + derper + tailscaled（自建 tailnet）、frps、sing-box、fail2ban、haveged；AppArmor 已加载；snapd 2.76.3 正常 |

### 0.2 来源异常说明（本次调研实际遇到的）

1. `microk8s.io` 文档已迁到 `canonical.com/microk8s/docs`；旧地址 `microk8s.io/docs/requirements` 返回 404，**最低资源要求改从官方 Get Started 页核实**。
2. MicroK8s 官方文档多页内容陈旧且未更新日期戳（Get Started 页仍示例 `--channel=1.35`；"Services and ports"页为 3 年前内容，仍列 etcd/calico 端口行，尽管默认 datastore 已是 k8s-dqlite）。本报告已逐条标注。
3. snapcraft.io 的频道明细表是 JS 渲染，HTML 抓取为空；snap 当前 stable 频道版本依据页面横幅 + GitHub releases 交叉核实，**安装前请以 `snap info microk8s` 实测为准**。
4. minikube `none` 驱动官方页引用的 kubeadm 前提仍写着"cgroups v1（v2 尚不支持）"——这与上游现状不符（上游 k8s 已支持 cgroup v2），属于官方文档陈旧内容，如实标注。
5. K3s 官方 FAQ **没有** flannel 与 tailscale/sing-box 共存的条目，无官方口径，本报告如实写"无官方说法"。
6. CNCF 一致性认证状态以官方仓库 `github.com/cncf/k8s-conformance` 的 v1.33–v1.37 目录逐版本核实（当日）。

---

## A. 逐产品档案

### A1. Minikube

**基础信息**

| 项 | 事实 | 来源 |
|---|---|---|
| 最新稳定版 | v1.39.0，发布于 2026-09-02（GitHub Releases API 与官网横幅一致） | (来源: https://api.github.com/repos/kubernetes/minikube/releases/latest, https://minikube.sigs.k8s.io/docs/) |
| 治理/维护方 | Kubernetes 官方 SIG 项目（kubernetes/minikube 仓库，"© The Kubernetes Authors"） | (来源: https://github.com/kubernetes/minikube) |
| 许可证 | Apache-2.0 | (来源: https://api.github.com/repos/kubernetes/minikube license 字段) |
| k8s 版本跟进 | 支持"最新 k8s 版本 + 前 2 个次版本"；`--kubernetes-version` 默认 `stable`，文档（2026-11-02 更新）标注 stable=v1.37.2，即已跟进到上游最新 | (来源: https://minikube.sigs.k8s.io/docs/ , https://minikube.sigs.k8s.io/docs/commands/start/) |
| CNCF 一致性认证 | **当前版本无有效认证**：k8s-conformance 仓库中仅在 v1.33、v1.35 有 minikube 条目，v1.34/v1.36/v1.37 均无（2026-11-05 核实） | (来源: https://github.com/cncf/k8s-conformance/tree/master/v1.35 与 v1.36/v1.37 目录对比) |

**1) 官方定位**：官方明确"minikube is local Kubernetes, focusing on making it easy to learn and develop for Kubernetes"，并在 Get Started 页原话注明"**minikube is for learning and development. For a production cluster, see the Kubernetes production environment docs**"——官方口径就是开发/学习工具，不是常驻生产负载的目标环境。(来源: https://minikube.sigs.k8s.io/docs/start/)

**2) 驱动模型在无显示器 VPS 上的可行性**：

- **docker 驱动（本机可用）**：直接复用已安装的 Docker（要求 18.09+，推荐 20.10+），"On Linux, this does not require virtualization to be enabled"——把整个 k8s 装进一个名为 minikube 的容器里。(来源: https://minikube.sigs.k8s.io/docs/drivers/docker/)
- **podman 驱动（不建议）**：官方标注为 **experimental**："Please use it only for experimental reasons until it has reached maturity"；Linux 上 rootful podman 需要配置 passwordless sudo，rootless 需配置 subuid/subgid。本机 podman 4.9.3 是 rootless 且无运行容器，走此驱动无收益。(来源: https://minikube.sigs.k8s.io/docs/drivers/podman/)
- **`--driver=none`（不推荐，未废弃）**：未被标记 deprecated，但官方口径是"recommended for advanced users only"、"Most users … should consider the newer Docker driver"。它把 kubelet/apiserver 等直接跑在宿主机上（apiserver 监听 `*:8443`、kubelet `*:10250/10255`），会接管/重启宿主机的 containerd、docker 等运行时，且官方页自述大量限制（不支持多 profile、部分命令不可用、会覆写 `/etc/kubernetes` 等路径、安全隐患清单）。另注意该页引用的 kubeadm 前提仍写"cgroups v1（v2 not yet supported）"，为陈旧内容。(来源: https://minikube.sigs.k8s.io/docs/drivers/none/)
- **VM 类驱动（不可用）**：kvm2/qemu/virtualbox 等需要嵌套虚拟化，搬瓦工这类 KVM VPS 通常不暴露嵌套虚拟化；官方驱动列表见 (来源: https://minikube.sigs.k8s.io/docs/drivers/)

**3) 资源占用**：官方最低要求"2 CPUs or more / 2GB of free memory / 20GB of free disk space"。docker 驱动下整个集群是单个容器，内存由 `--memory`/`minikube config set memory` 控制（官方未给出 control plane 典型内存数字，**无官方口径**）。(来源: https://minikube.sigs.k8s.io/docs/start/)

**4) 常驻能力**：

- **开机自启：官方无 systemd 支持**，文档只提供 `minikube start/stop/pause/unpause` 手工生命周期，未提供任何自启单元（官方文档全站无此内容）。
- **重启后数据**：docker 驱动的集群状态存在 docker 卷中，重启后需再次手工 `minikube start` 恢复（同版本同参数）。
- **bootstrap**：默认 bootstrapper 为 **kubeadm**（`--bootstrapper` 默认值 "kubeadm"），证书默认 3 年有效期（`--cert-expiration` 默认 26280h）。(来源: https://minikube.sigs.k8s.io/docs/commands/start/)

**5) 与真实集群的差异**：LoadBalancer 依赖 `minikube tunnel` 这个**前台进程**（在宿主机上建路由到 service CIDR，Ctrl-C 即消失）；NodePort 默认仅暴露 30000-32767；ingress addon（ingress-nginx）仅 Linux 支持完整。这些都是"本机开发"语义，与生产集群的 LoadBalancer/Ingress 达成方式不同。(来源: https://minikube.sigs.k8s.io/docs/handbook/accessing/ , https://minikube.sigs.k8s.io/docs/start/)

**6) 多节点**：`minikube start --nodes=N` 支持多节点，`--ha` 可起 3 控制面节点；版本跟进及时（见上表）。(来源: https://minikube.sigs.k8s.io/docs/commands/start/)

### A2. K3s

**基础信息**

| 项 | 事实 | 来源 |
|---|---|---|
| 最新稳定版 | v1.37.2+k3s1，发布于 2026-11-03（跟进上游 Kubernetes v1.37.2） | (来源: https://api.github.com/repos/k3s-io/k3s/releases/latest) |
| 治理/维护方 | k3s-io 组织（SUSE/Rancher 团队维护；发布说明链接 Rancher Slack 与 Rancher 文档）；2020-08-19 加入 CNCF，**当前仍为 Sandbox 级** | (来源: https://www.cncf.io/projects/k3s/ , https://github.com/k3s-io/k3s) |
| 许可证 | Apache-2.0 | (来源: https://api.github.com/repos/k3s-io/k3s license 字段) |
| CNCF 一致性认证 | **有**：v1.33–v1.37 每个版本目录都有 k3s 条目（2026-11-05 核实）；官方 FAQ 原话"K3s is a CNCF-certified Kubernetes distribution" | (来源: https://github.com/cncf/k8s-conformance , https://docs.k3s.io/faq) |

**1) 定位**：官方自述"Lightweight Kubernetes. Easy to install, half the memory, all in a binary of less than 100 MB"，面向 Edge / Homelab / IoT / CI / Development 等；"a fully compliant Kubernetes distribution"（完全合规的发行版）。(来源: https://docs.k3s.io/)

**2) 架构与捆绑组件**（v1.37.2+k3s1 内嵌版本）：

- 单二进制 + 单进程封装全部控制面；内置 **containerd v2.3.7-k3s1**（与系统 docker 的 containerd 互不相干，另有 cri-dockerd 选项）；默认 datastore 为 **SQLite 3.53.4（经 kine v0.17.1）**，可选 etcd v3.7.1-k3s3 / MySQL / Postgres。(来源: https://docs.k3s.io/ , https://github.com/k3s-io/k3s/releases/tag/v1.37.2+k3s1)
- 默认捆绑：Flannel v0.28.10（CNI）、CoreDNS v1.14.7、**Traefik v3.7.15（Ingress）**、**ServiceLB/Klipper（LoadBalancer，hostPort 实现）**、kube-router 网络策略、local-path-provisioner v0.0.37（存储）、metrics-server v0.9.0、Spegel 镜像仓。(来源: https://docs.k3s.io/ , release notes 同上)
- **可关项（官方 flag）**：`--disable=traefik|coredns|local-storage|metrics-server|servicelb`（新版语法，禁用即卸载并删除 manifest），`--flannel-backend none`（自带 CNI 全关），`--disable-network-policy`（关 kube-router 网络策略）。(来源: https://docs.k3s.io/installation/packaged-components , https://docs.k3s.io/networking/networking-services)

**3) 官方最低/推荐资源**（区分 server/agent）：

- 最低要求：**Server 2 核 / 2GB RAM；Agent 1 核 / 512MB**（不含工作负载）。(来源: https://docs.k3s.io/installation/requirements#hardware)
- 官方实测画像（v1.26.5、含 Prometheus+Grafana+示例负载）：**单机 server+workload 最低内存 1596MB（SQLite）/ 1606MB（内嵌 etcd）**（x86）；server+1 agent 无负载时 server 1428M、agent 275M。(来源: https://docs.k3s.io/reference/resource-profiling)

**4) swap 支持现状（本机开着 10G swap）**：

- 上游官方口径：kubelet **默认拒绝在开启 swap 的 Linux 节点启动**（`failSwapOn` 默认 true）；`failSwapOn:false` 时默认行为 `NoSwap`（Pod 拿不到 swap，但系统进程/宿主服务可以用 swap）；`LimitedSwap` 仅 Burstable QoS Pod 可用 swap；**官方建议控制面节点不启用 swap**；1.37 调度器尚不感知 swap。(来源: https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/)
- K3s：**官方文档无 swap 专门页面/条目（无官方文档口径）**；但源码可查——K3s 默认 kubelet 配置写死 `FailSwapOn: false`（`pkg/daemons/agent/agent.go` L180，main 分支当日核实），即 **K3s kubelet 可在开 swap 的节点上正常启动**，Pod 默认仍不吃 swap（NoSwap 语义）。(来源: https://raw.githubusercontent.com/k3s-io/k3s/main/pkg/daemons/agent/agent.go)

**5) 安装与生命周期**：`curl -sfL https://get.k3s.io | sh -` 一条命令装成 **systemd 服务**（官方明确"automatically restart after node reboots or if the process crashes"）；附带 `kubectl/crictl/ctr`、`k3s-killall.sh`、**`k3s-uninstall.sh`（卸载脚本）**；kubeconfig 在 `/etc/rancher/k3s/k3s.yaml`；配置可用 `/etc/rancher/k3s/config.yaml`（支持 drop-in 目录）；kubelet 配置 drop-in 目录 `/var/lib/rancher/k3s/agent/etc/kubelet.conf.d/`（v1.32+）。升级：手动（重跑安装脚本指定版本/channel）或 **system-upgrade-controller 自动化**。(来源: https://docs.k3s.io/quick-start , https://docs.k3s.io/installation/configuration , https://docs.k3s.io/upgrades)

**6) 端口占用**（与已有服务冲突的关键）：

| 端口 | 用途 | 冲突判断 |
|---|---|---|
| TCP 6443 | supervisor + kube-apiserver（另有本地 6444） | 本机无占用，但要考虑安全暴露策略 |
| TCP 10250 | kubelet metrics/API | 本机无占用 |
| UDP 8472 | Flannel VXLAN（默认后端） | **官方警告不得暴露公网** |
| UDP 51820/51821 | Flannel WireGuard 后端（非默认；tailscale 也用 WireGuard 但端口不同，默认不开） | 仅换后端时相关 |
| TCP 2379-2380 | 内嵌 etcd（仅 HA） | 单机 SQLite 不用 |
| **80/443** | **Traefik LB Service 经 ServiceLB 用 hostPort 占用** | **与 nginx 冲突** |

官方原话："The Traefik ingress controller deploys a LoadBalancer Service that uses ports 80 and 443 … ports 80 and 443 will not be usable for other HostPort or NodePort pods"。**官方给的解法**：① `--disable=traefik`（用自己的 ingress）；② `--disable=servicelb`（换 MetalLB 等，此时 LB Service pending 但 NodePort 仍分配）；③ 用 HelmChartConfig 把 Traefik Service 改 `ClusterIP` 等类型；④ 节点标签控制 ServiceLB 调度位置。注意 2026-06 起 Traefik chart v40 把 Service 类型键从 `service.type` 改为 `service.spec.type`（旧键被静默忽略）。(来源: https://docs.k3s.io/installation/requirements#networking , https://docs.k3s.io/networking/networking-services)

**7) 与 tailscale/sing-box 共存**：官方 FAQ/已知问题**均无条目**——无官方口径。技术上 K3s 默认 flannel VXLAN + kube-proxy 会持续维护 iptables 规则链（KUBE-*），与 sing-box/tailscale 的 iptables/nftables 规则共存属"需实测"事项，本报告不编造结论。(来源: https://docs.k3s.io/faq)

**8) 单节点数据备份（官方做法）**：SQLite datastore "No special commands are required"——**停机窗口内直接拷贝 `/var/lib/rancher/k3s/server/db/`，并必须同时备份 `/var/lib/rancher/k3s/server/token`**（token 用于加密 datastore 内敏感数据，丢了快照不可用）；如切到内嵌 etcd 则用 `k3s etcd-snapshot` 命令体系。(来源: https://docs.k3s.io/datastore/backup-restore)

**9) 与上游差异清单**（官方"What is K3s"页）：单二进制/单进程、SQLite 默认 datastore、封装 TLS 复杂度、外部依赖最小化（仅需现代内核 + cgroup 挂载）、以及一组"batteries-included"替代组件（上述捆绑列表）。架构页：server=控制面+datastore+kubelet+runtime；HA 需 3 server + 内嵌 etcd（单机默认 SQLite 不是 etcd）。(来源: https://docs.k3s.io/ , https://docs.k3s.io/architecture)

### A3. MicroK8s

**基础信息**

| 项 | 事实 | 来源 |
|---|---|---|
| 最新稳定版（源码） | v1.36（Kubernetes 1.36），GitHub release 发布于 2026-05-25；**截至当日尚无 1.37 版本**（上游 k8s 1.37 已发布，kubernetes.io 默认文档已是 v1.37） | (来源: https://api.github.com/repos/canonical/microk8s/releases/latest) |
| snap 商店状态（当日页面） | 默认安装横幅指向 **1.35/stable（v1.35.6，2026-07-02）**，最新记录见 1.36/edge（2026-09-30）；1.36 stable 频道是否已就绪**需 `snap info microk8s` 实测** | (来源: https://snapcraft.io/microk8s) |
| 治理/维护方 | Canonical（Ubuntu 厂商），snap 分发 | (来源: https://canonical.com/microk8s/docs) |
| 许可证 | Apache-2.0 | (来源: https://snapcraft.io/microk8s Details-License) |
| CNCF 一致性认证 | **有（截至 v1.36）**：v1.33–v1.36 目录均有 microk8s 条目；v1.37 暂无（与其尚未发 1.37 一致） | (来源: https://github.com/cncf/k8s-conformance) |

**1) 定位与 channel 模型**：官方自述"low-ops, minimal production Kubernetes"，从单节点扩展到 HA 生产集群。snap channel = `<track>/<risk>`（track=k8s 次版本，risk=stable/candidate/beta/edge）；不指定 channel 默认装 latest/stable 且**只收补丁更新不跨次版本**；**snap 默认每天自动刷新 4 次**（可延迟/计划/阻止，见 snap refreshes 文档）。(来源: https://canonical.com/microk8s/docs , https://canonical.com/microk8s/docs/setting-snap-channel)

**2) datastore 现状**：**k8s-dqlite（dqlite）仍是默认 datastore**（"the default datastore (dqlite)"；HA 文档亦写 "Kubernetes dqlite database"）；etcd 非默认——HA 文档称 etcd 方案"more involved"，需自建外部 etcd 集群。(来源: https://canonical.com/microk8s/docs/restore-quorum , https://canonical.com/microk8s/docs/high-availability)

**3) 官方最低/推荐资源**：官方 Get Started 原话"**MicroK8s runs in as little as 540MB of memory, but to accommodate workloads, we recommend a system with at least 20G of disk space and 4G of memory**"。（注：原 /docs/requirements 页已 404。）(来源: https://canonical.com/microk8s/docs/getting-started)

**4) snap 严格限制与 docker 关系**：

- 默认安装是 `--classic`（经典限制）；另提供 `1.36-strict` 等 strict confinement 轨道——完全隔离（AppArmor/seccomp/namespaces），但部分需要宿主共享挂载的 addon（cilium、gpu、multus）在 strict 下不可用，需回到 classic。(来源: https://canonical.com/microk8s/docs/strict-confinement , https://canonical.com/microk8s/docs/setting-snap-channel)
- MicroK8s **自带独立 containerd**（socket: `unix:///var/snap/microk8s/common/run/containerd.sock`），不使用也不干扰系统 docker/containerd。(来源: https://canonical.com/microk8s/docs/services-and-ports)

**5) swap 官方口径**：**官方文档无 swap 相关专门说明（无官方口径）**——文档站内无对应条目（当日检索）。实际效果取决于其 kubelet 默认参数，装前可实测。

**6) 端口与 80/443 冲突**：API server 在 **16443**（非 6443，天然避开常见冲突）、kubelet 10250/10255、cluster-agent 25000、etcd 12379、dqlite 19001、calico VXLAN 4789/udp（此表来自 3 年前的官方页，端口布局沿用）。**ingress addon（自 1.35 起为 Traefik，此前为 ingress-nginx）在 addon 的 values.yaml 中写死 `hostPort: 80` 与 `hostPort: 443`**（"Expose ports on host (matching previous nginx behavior)"），**与已运行的 nginx 直接冲突**；addon 支持 `-V/--default-ssl-certificate` 等选项，但 hostPort 需改 addon values 才能避让。另提供 host-access addon 方便宿主访问（导航有列）。(来源: https://canonical.com/microk8s/docs/services-and-ports , https://canonical.com/microk8s/docs/addon-ingress , https://github.com/canonical/microk8s-core-addons/blob/main/addons/ingress/values.yaml)

**7) 单机生命周期**：`microk8s start/stop/status`；官方明确"if you leave MicroK8s running, it will automatically restart after a reboot"（保持运行即可开机自启）；证书用 `microk8s refresh-certs --cert server.crt` 刷新并加 SAN；**dqlite 备份（官方做法）= 停机后 `tar` 打包 `/var/snap/microk8s/current/var/kubernetes/backend/`**（官方恢复文档即按此目录操作）。(来源: https://canonical.com/microk8s/docs/getting-started , https://canonical.com/microk8s/docs/services-and-ports , https://canonical.com/microk8s/docs/restore-quorum)

**8) 多节点/HA（一句话）**：3 节点起自动 HA（k8s-dqlite Raft，voter/standby/spare 三种角色，`microk8s add-node/join/leave` 管理）。(来源: https://canonical.com/microk8s/docs/high-availability)

---

## B. 横向对比（针对"这台机器 + 统一环境迁移"目标）

### B1. 资源账（8G 总量 − 已用约 1.5G ≈ 6.5G 余量）

| 方案 | 官方数字 | 现实判断（单节点 control plane + 2~3 个真实应用） |
|---|---|---|
| K3s | 最低 server 2C/2G；官方画像 server+workload ≈ **1596MB**（含监控栈） | **最省**：纯 control plane 约 1.2~1.6G，叠加 2~3 个中小应用（每个 100~300M）后总计约 2~2.5G，机器余量充裕 |
| MicroK8s | 最低 540MB 可跑；**官方推荐整机 4G 内存/20G 盘** | 中等：实际裸控制面约 1G 上下（无官方实测数字），但官方推荐口径按 4G 整机规划，叠加现有服务后偏紧但可行 |
| Minikube | 官方要求 **2GB 空闲内存**、2C、20G 盘 | 集群整体装进一个容器，内存按 `--memory` 分配；占用与 K3s 相当或更高（多一层容器嵌套），且不为常驻设计 |

叠加本机现状（1.5G 已用 + 容器缓存）：**K3s/MicroK8s 都装得下**，K3s 的官方数字最扎实也最轻；Minikube 不是资源问题而是定位问题。CPU 方面 6 vCPU 对三者都富余（K3s 官方画像 server 稳态仅 6% 单核）。(来源: https://docs.k3s.io/installation/requirements , https://docs.k3s.io/reference/resource-profiling , https://canonical.com/microk8s/docs/getting-started , https://minikube.sigs.k8s.io/docs/start/)

### B2. 与现有服务的共存/迁移路径

**1) docker compose → k8s manifests 的迁移路径**：

- **kompose（官方现状：活跃）**：kubernetes.io 官方任务页《Translate a Docker Compose File to Kubernetes Resources》当前有效，kompose 当前版本 v1.34.0、**三周一个发布周期**，`kompose convert` 可把 compose 转 Deployment/Service/PVC 等（也支持 OpenShift）。适合做初稿，再人工修（探针、资源限额、密钥）。(来源: https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/)
- **Helm 化 / 手写 manifests**：对 LibreChat 这类多容器 compose 栈，长期看手写（或 Helm chart + values）质量更高；kompose 输出当作起点。
- **逐个迁 vs 全量迁**：建议**逐个迁**——现有 reading-app/signal-align-auth 等继续留在 docker compose（不受影响，K3s 用自己的 containerd，MicroK8s 也是），新服务（如将来要上的 NATS JetStream）直接以 k8s 方式部署进集群，跑顺后再回头迁旧服务。理由：单机 8G 内存对"全量双轨"（docker + k8s 各一份）不友好；且一次迁一个便于归因。（更正 2026-11-14：原示例 LibreChat/redis/rustfs 已于 2026-09-22 下线，替换为在跑负载。）

**2) 与继续运行的 docker/nginx/tailnet 共存**：

- **端口**：K3s 需处理 80/443（见 A2.6，disable Traefik+ServiceLB 即可让 nginx 独占）；MicroK8s 的 API server 在 16443 不与谁冲突，但 ingress addon 的 hostPort 80/443 与 nginx 冲突（需改 values）；minikube docker 驱动不占宿主 80/443（自己待在容器网络里，NodePort 30000-32767）。
- **iptables**：三者都会经由 kube-proxy/CNI 维护 iptables（KUBE-* 链）。与 sing-box/tailscale 的规则共存**无任何一家给出官方说法**（K3s FAQ 无条目；MicroK8s/minikube 文档也无）——部署后必须实测连通性（derp/frp/代理链路回归测试）。可确知的差异点：K3s 默认 flannel 用 VXLAN(UDP 8472)，其 WireGuard 后端(UDP 51820/51821)默认不启用，与 tailscale 常用端口不撞。
- **cgroup/内存**：cgroup v2 下三者均按 systemd cgroup 切片运行；K3s 源码默认 `FailSwapOn=false` 可在 swap 机器上直接跑（A2.4）；上游建议控制面不依赖 swap，可按官方 good practice 给 system.slice 设 `memory.swap.max=0` 保护系统关键守护。
- **containerd**：K3s/MicroK8s 各自内置独立 containerd，不与 docker.service/containerd.service 冲突；已有 compose 工作负载无需改动。

**3) "环境统一"成色（迁移资产的可移植性）**：

- **K3s、MicroK8s 均为 CNCF 一致性认证发行版**（K3s 至 v1.37、MicroK8s 至 v1.36，当日核实）；**minikube 当前版本（v1.36/v1.37）无认证记录**（仅 v1.33/v1.35 有）。(来源: https://github.com/cncf/k8s-conformance)
- manifest/Helm/kubectl/GitOps（Flux/ArgoCD）技能与资产：K3s 与 MicroK8s 都是"真集群"语义（systemd 常驻、kubeconfig、RBAC、证书、storage class、LoadBalancer 语义），学到的和写下的东西可直接搬到任何认证集群；minikube 的 tunnel/本机服务暴露是特有机制，迁走时要重学暴露方式。
- K3s 的 HelmChartConfig/auto-deploy manifests、MicroK8s 的 addon 是各自的发行版扩展，**不要**把核心工作负载绑在这些扩展上——用标准 manifests/Helm 才是真统一的资产（这一点是通用工程原则，非官方文档口径）。

### B3. 运维负担

| 维度 | K3s | MicroK8s | Minikube |
|---|---|---|---|
| 升级节奏 | 跟进最快（当日已 v1.37.2+k3s1）；手动重跑安装脚本或 system-upgrade-controller 自动化 | 慢一拍：1.36（2026-05 发布），1.37 未出；snap 自动刷新每天 4 次（跨版本需手动换 channel，可 hold） | 跟进快（stable=v1.37.2），但升级=重建本机集群语义 |
| 6443 暴露策略 | 公网 VPS 上 **6443 绝不对公网开放**（K3s 官方同时警告 UDP 8472 不得暴露公网）；用 tailscale 私网访问 kube-apiserver 是与现有 headscale/tailscale 设施最契合的做法——防火墙只放行 tailnet 网段访问 6443 | API server 在 16443，同样只对 tailnet 放行 | 8443 在 minikube 容器内，默认不直接对外 |
| 证书 | K3s 封装了证书管理（官方："handles a lot of the complexity of TLS"，启动时自动处理） | `microk8s refresh-certs` 手动/按需刷新 | `--cert-expiration` 默认 3 年 |

(来源: https://docs.k3s.io/ , https://docs.k3s.io/installation/requirements#networking , https://docs.k3s.io/upgrades , https://canonical.com/microk8s/docs/services-and-ports , https://docs.k3s.io/quick-start , https://minikube.sigs.k8s.io/docs/commands/start/)

### B4. 风险与坑（仅有官方/项目依据的才写）

- **Minikube 非常驻设计**：官方原话"for learning and development"；无 systemd 自启；`minikube tunnel` 是前台进程。**不适合当这台 VPS 的常驻底座**。(来源: https://minikube.sigs.k8s.io/docs/start/)
- **Minikube none 驱动风险**：官方自列安全/可靠性问题清单（apiserver/kubelet 监听公网地址、可能接管 docker/containerd、`minikube delete` 抹掉系统路径）。(来源: https://minikube.sigs.k8s.io/docs/drivers/none/)
- **Minikube docker 驱动 + AppArmor**：官方已知问题——AppArmor 主机上特权方式跑 MySQL 有 issue #7401（本机 AppArmor 已加载，需留意）。(来源: https://minikube.sigs.k8s.io/docs/drivers/docker/)
- **K3s Traefik chart v40 破坏性变更**（2026-06 起）：Service 类型键从 `service.type` 改为 `service.spec.type`，旧键被**静默忽略**导致回退 LoadBalancer——改过 Traefik Service 类型的集群升级时要先迁移配置。(来源: https://docs.k3s.io/networking/networking-services#traefik-service-type)
- **K3s 禁用 servicelb 后**：LoadBalancer Service（含打包的 Traefik）会一直 pending（NodePort 仍分配），需另装 LB 或改 ClusterIP。(来源: https://docs.k3s.io/networking/networking-services#disabling-servicelb)
- **K3s 备份必须带 token**：`/var/lib/rancher/k3s/server/token` 丢失则快照不可用。(来源: https://docs.k3s.io/datastore/backup-restore)
- **MicroK8s ingress addon 硬编码 hostPort 80/443**：与 nginx 冲突，改起来要动 addon values。(来源: https://github.com/canonical/microk8s-core-addons/blob/main/addons/ingress/values.yaml)
- **MicroK8s snap 自动刷新**：默认每天 4 次检查刷新（同 channel 内补丁），对"深夜自动重启集群"敏感的话要配 hold/维护窗。(来源: https://canonical.com/microk8s/docs/setting-snap-channel)
- **MicroK8s 版本滞后**：上游 1.37 已出而 MicroK8s 停在 1.36（snap 商店默认横幅仍 1.35/stable），且"CNCF 认证至 v1.36"。(来源: https://api.github.com/repos/canonical/microk8s/releases/latest , https://snapcraft.io/microk8s)
- **iptables 共存**：三者与 sing-box/tailscale 的 iptables 共存**均无官方说法**，上线前必须实测（这是"未知"而非"没问题"）。
- **swap**：上游官方建议控制面节点不启用 swap、调度器不感知 swap；K3s 源码层面容忍 swap 节点（FailSwapOn=false），MicroK8s/minikube 无官方口径。(来源: https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/ , https://raw.githubusercontent.com/k3s-io/k3s/main/pkg/daemons/agent/agent.go)

---

## C. 结论

### C1. 三者按适配度排序（本机 + "统一将来 k8s 环境"目标）

1. **K3s（首选）**——真·常驻单节点集群：systemd 官方支持、CNCF 认证至最新版 v1.37、官方资源数字最轻（server+负载 ≈1.6G）、SQLite 备份一条 tar 命令、`--disable=traefik --disable=servicelb` 两个 flag 就把 80/443 还给 nginx，kube-apiserver 6443 可配合 tailscale 私网访问。
2. **MicroK8s（次选）**——同样是认证过的真集群、装好即用，但当前版本落后上游一个次版本、snap 自动刷新机制与"我控制重启窗口"的偏好相悖、4G 推荐口径在 8G 机器上叠加现有服务偏紧、ingress addon 的 hostPort 80/443 与 nginx 冲突需改 addon。
3. **Minikube（不适配此目标）**——官方定位学习/开发，无 systemd 常驻、LoadBalancer 靠前台 tunnel 进程、当前 k8s 版本无一致性认证记录；它适合"在这台机器旁边临时起个练习集群"，不适合当底座。

### C2. 首选方案（K3s 单节点）落地要点清单

**安装（让出 80/443、可被 tailnet 访问）：**

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - \
  --disable=traefik \
  --disable=servicelb \
  --tls-san=<该机 tailscale 主机名或 tailnet IP>   # 证书 SAN，供 tailnet 内 kubectl 访问
# 等价做法：把以上写进 /etc/rancher/k3s/config.yaml
# uninstall: /usr/local/bin/k3s-uninstall.sh
```

- 必须/建议 disable：`--disable=traefik`、`--disable=servicelb`（否则经 ServiceLB hostPort 占 80/443 与 nginx 冲突，来源: https://docs.k3s.io/networking/networking-services ）。保留 coredns / local-storage / metrics-server。
- kubectl：`k3s kubectl`，kubeconfig 在 `/etc/rancher/k3s/k3s.yaml`（复制到 tailnet 内的管理机时改 server 地址为 tailnet IP/主机名）。(来源: https://docs.k3s.io/quick-start)

**端口规划（公网 VPS 安全基线）：**

- 6443：**绝不对公网开放**；防火墙只放行 tailscale 网段（100.64.0.0/10）访问 6443。
- UDP 8472（flannel VXLAN）：**官方明确警告不得暴露公网**——单机自闭环，防火墙直接封外部入向。
- 10250/6444 等：仅本机/集群内部使用。(来源: https://docs.k3s.io/installation/requirements#networking)

**与 nginx 的 Ingress 共存（三选一，按复杂度递增）：**

1. **nginx 继续做 edge，反代到 k8s NodePort（推荐起步）**：k8s 内服务用 `type: NodePort`（默认 30000-32767），nginx 加 `location` 反代 `http://127.0.0.1:<nodePort>`。零新增组件，最稳。
2. **集群内 Ingress 换非 80/443 hostPort**：保留 Traefik 但用 HelmChartConfig 把 `ports.web.hostPort`/`ports.websecure.hostPort` 改成如 8081/8444，nginx 443 → 127.0.0.1:8444。能保留 Ingress 资源语义（对"将来迁移"更有价值），注意 chart v40 的 `service.spec.type` 破坏性变更。
3. **MetalLB（单机场景不建议）**：需 `--disable=servicelb` 后另装，为单节点引入额外控制器，收益低。

**其他要点：**

- **kubelet/swap**：K3s 默认容忍 swap（源码 `FailSwapOn:false`），Pod 默认不吃 swap（NoSwap）。如想让 Burstable Pod 用 swap，按上游文档在 `/var/lib/rancher/k3s/agent/etc/kubelet.conf.d/` 放 drop-in 配 `memorySwap.swapBehavior: LimitedSwap`；并建议按上游 good practice 给 system.slice 设 `memory.swap.max=0` 保护系统服务。(来源: https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/ , https://docs.k3s.io/installation/configuration#kubelet-configuration-files)
- **备份（cron，低峰执行）**：
  ```bash
  systemctl stop k3s && \
  tar czf /backup/k3s-db-$(date +%F).tgz /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/token && \
  systemctl start k3s
  ```
  （SQLite 官方口径即"拷目录 + token"，来源: https://docs.k3s.io/datastore/backup-restore ）
- **升级**：重跑 install 脚本指定 `INSTALL_K3S_VERSION`/channel，或部署 system-upgrade-controller；单节点升级=短暂停机，选维护窗执行。(来源: https://docs.k3s.io/upgrades)
- **NATS JetStream（将来）**：直接以 Helm/manifests 进 K3s，local-path-provisioner 提供 PV；这就是"新服务先上 k8s"路线的第一个候选。

### C3. "不建议 / 缓一缓"的诚实评估

- **这台机器装 K3s 是可行的**（余量账：1.5G 现有 + ~1.6G K3s + 应用 ≤ 4G，8G 内有余地），但有两个真实代价要接受：① 每周量级的运维注意力（升级、备份、证书、防火墙）；② iptables 规则与 sing-box/tailscale 共存**未经官方验证**，出问题时要能回滚（`k3s-uninstall.sh` 一键清掉）。
- **不建议全量迁移**：reading-app（含数据库依赖）、signal-align-auth 等已稳定运行在 docker compose，迁移收益低、回归风险实打实。建议**现有服务留在 docker，新服务（NATS 等）进 K3s，旧的按需逐个迁**。（更正 2026-11-14：原示例 LibreChat/rustfs 已于 2026-09-22 下线，替换为在跑负载。）
- **如果目标只是"学 k8s"**：不急着上常驻集群——在这台机器上 `minikube start` 起个临时集群练手、用完 `minikube delete`，比把它变成第二套常驻基础设施更划算。
- **出现以下任一情况应暂缓**：内存空闲长期 < 3G；无法接受偶发的维护窗停机；近期没有真正要按 k8s 方式部署的新服务。

### C4. 决策自检清单

| 信号 | 选择 |
|---|---|
| 要"现在就按 k8s 管理 + 将来平滑迁移"，且能留出 ~2G 内存 | **K3s 单节点**（本报告首选） |
| 未来 6 个月内确定要 ≥3 节点 HA，且偏好 Canonical 生态/Ubuntu Pro 支持 | MicroK8s（注意版本滞后与 snap 刷新） |
| 只想学/试验 k8s，不想承担常驻运维 | minikube 临时集群，用完即删 |
| 装上 K3s 后 sing-box/derp/frp 出现连通性故障且 1~2 小时内定位不了 iptables 冲突 | 回滚 `k3s-uninstall.sh`，回到 docker compose，改为只在本地/沙箱练 k8s |
| 内存水位持续 > 6G / swap 频繁换入换出 | 停止向 k8s 迁移，现有服务留 docker，考虑扩内存后再说 |
| 新服务全部愿意写 manifests/Helm 且团队（含 AI 会话）熟悉 kubectl | 加速迁移；反之继续"新服务优先"渐进路线 |

---

## 附：本次核实过的全部一手来源

- minikube：https://minikube.sigs.k8s.io/docs/ ; /docs/start/ ; /docs/drivers/docker/ ; /docs/drivers/podman/ ; /docs/drivers/none/ ; /docs/handbook/accessing/ ; /docs/commands/start/ ; https://api.github.com/repos/kubernetes/minikube（/releases/latest）
- K3s：https://docs.k3s.io/ ; /quick-start ; /installation/requirements ; /installation/configuration ; /installation/packaged-components ; /networking/networking-services ; /datastore/backup-restore ; /reference/resource-profiling ; /architecture ; /upgrades ; /faq ; https://github.com/k3s-io/k3s/releases/tag/v1.37.2+k3s1 ; https://raw.githubusercontent.com/k3s-io/k3s/main/pkg/daemons/agent/agent.go ; https://www.cncf.io/projects/k3s/
- MicroK8s：https://canonical.com/microk8s/docs ; /docs/getting-started ; /docs/setting-snap-channel ; /docs/services-and-ports ; /docs/strict-confinement ; /docs/addon-ingress ; /docs/high-availability ; /docs/restore-quorum ; https://snapcraft.io/microk8s ; https://github.com/canonical/microk8s/releases ; https://github.com/canonical/microk8s-core-addons/blob/main/addons/ingress/values.yaml
- 上游 Kubernetes：https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/ ; https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/ ; https://kubernetes.io（默认文档版本 v1.37）
- CNCF：https://github.com/cncf/k8s-conformance（v1.33–v1.37 目录逐版本核对，2026-11-05）
