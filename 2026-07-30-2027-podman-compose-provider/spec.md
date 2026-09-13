# Podman 使用 `podman compose`（Docker Compose 后端）替代 Python 版 `podman-compose`

- 日期:2026-07-30(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(podman + Homebrew 版 docker-compose provider)
- 类型:本机容器工具链配置(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

用户已安装 `podman`（容器引擎，替代 Docker，见 `~/CLAUDE.md`「Preferred CLI tools」）。Podman 自带的 `podman compose` 子命令本身不实现 Compose 规范，而是委托给一个外部 "compose provider" 执行；默认候选之一是 Python 实现的 `podman-compose`，但用户反馈 `podman-compose` 运行时会有"奇奇怪怪的问题"。目标：让 `podman compose` 优先使用（Homebrew 版）`docker-compose`（Docker 官方 Compose V2 独立二进制）作为 provider，而不是退化到 `podman-compose`。

本任务为本机容器工具链环境配置，非某个代码仓库内的功能开发，因此不涉及 `~/CLAUDE.md` 工作流中 Kanban 关联、`git worktree`、Gherkin/E2E、文档同步等环节；仅保留 spec.md / implementation.md 的记录方式（与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/) 一致）。

## 范围

- **In scope**：确认 `podman`、`docker-compose`、`podman-compose` 三者的安装状态；确认 `podman compose` 实际选择的是哪个 provider；验证 `podman compose` 在选中 `docker-compose` 作为后端时，能正确解析/执行 compose 文件。
- **Out of scope**：`podman machine`（macOS 上 Podman 依赖的 Linux VM）内部的镜像仓库代理/加速配置——验证过程中发现 `podman compose up` 拉取 `docker.io` 镜像会 `i/o timeout`（VM 内部网络未配置代理/镜像加速，属于独立问题，见「风险与缓解」），本任务不处理。

## 现状分析

1. 三者均已通过 Homebrew 安装：`podman`（6.0.2）、`docker-compose`（Homebrew formula，实为 Docker Compose V2 独立二进制，5.3.1）、`podman-compose`（Python 实现，1.6.0，Homebrew formula 打包）。
2. `podman compose` 命令**不是**一个内建的 Compose 实现，而是按固定顺序在 `$PATH` 中查找外部 provider 可执行文件并委托执行（`podman-compose(1)` manpage 中说明的 "external compose provider" 机制）。查找优先级上，Docker 官方的 `docker-compose` / `docker compose` 排在纯 Python 的 `podman-compose` 之前。
3. 用户机器上没有 `~/.config/containers/containers.conf`（可用于显式指定 `compose_providers` 的配置文件），因此 `podman compose` 走的是默认查找顺序。
4. 实测 `podman compose config`：命令输出明确提示 `Executing external compose provider "/opt/homebrew/bin/docker-compose"`——证明在**未做任何额外配置**的情况下，只要 `docker-compose` 存在于 `$PATH` 且排在 `podman-compose`能被发现的位置之前（Homebrew 的 `docker-compose` 与 `podman-compose` 都装在 `/opt/homebrew/bin` 下，podman 的内部候选顺序本身就优先选 `docker-compose`），`podman compose` 就会自动选用它，而不会用到 Python 版 `podman-compose`。
5. 结论：**用户实际要做的"配置"，本质上只是"把 `docker-compose` 装好并留在 PATH 上"**——不需要额外写 `containers.conf` 去强制指定 provider，podman 的默认优先级已经满足需求。

## 解决方案

1. 通过 Homebrew 安装 `podman`、`docker-compose`（若此前已装 `podman-compose`，无需卸载——多个 provider 共存不冲突，podman 按内置优先级自动选中 `docker-compose`）。
2. 不新增 `~/.config/containers/containers.conf`：默认 provider 查找顺序已经把 `docker-compose` 排在 `podman-compose` 之前，验证结果符合预期，无需显式覆盖。
3. 如未来需要**强制**锁定 provider（例如同机再装了其他候选、想避免依赖默认顺序），可在 `~/.config/containers/containers.conf` 中显式声明：
   ```toml
   [engine]
   compose_providers = ["/opt/homebrew/bin/docker-compose"]
   ```
   当前未采用此步骤，仅作为备选记录。

## 验收标准

- [x] `which podman` / `which docker-compose` / `which podman-compose` 均能定位到 Homebrew 安装的可执行文件。
- [x] `podman compose config`（对最小化 `compose.yml`）明确输出 `Executing external compose provider ".../docker-compose"`，而非 `podman-compose`。
- [x] `podman compose config` 正确解析出 `services.hello`、`networks.default` 等结构化内容，证明 provider 委托机制端到端可用。
- [~] `podman compose up` 实际拉起容器——受限于 `podman machine` VM 内部网络未配置代理/镜像加速，拉取 `docker.io/library/alpine` 时 `i/o timeout`，**provider 选择本身没有问题，失败点在镜像拉取网络层**，不属于本任务范围（见风险）。

## 风险与缓解

- **`podman machine`（macOS 上的 Linux VM）内部网络与 macOS 宿主机是隔离的**：宿主机 `~/.zshrc` 里配置的 `http_proxy`/`https_proxy`（见 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)）**不会**自动传递到 VM 内部，因此 VM 内 `podman pull` 访问 `docker.io` 等境外源可能超时。缓解：后续如需稳定拉取镜像，应在 VM 内单独配置代理（`podman machine ssh` 进入后配置 `/etc/environment` 或 containers 的 proxy 设置）或改用国内镜像加速（`~/.config/containers/registries.conf` 配置 `docker.io` 的 mirror），本任务未处理，留作后续独立任务。
- **依赖"默认查找顺序"而非显式 `containers.conf` 声明**：如果未来 Homebrew 或 podman 版本升级改变了内置候选顺序，`podman compose` 有可能重新退回到 `podman-compose`。缓解：一旦观察到该行为回退，直接采用「解决方案」第 3 条的 `containers.conf` 显式声明，无需重新排查。
- **`podman-compose` 依然留在系统中未卸载**：不会主动被调用（因 `docker-compose` 优先级更高），可放心保留；如日后想彻底避免误用，可 `brew uninstall podman-compose`，但当前非必要。

## 参考

- `podman-compose(1)` manpage（`man podman-compose`）—— external compose provider 查找机制。
- `~/CLAUDE.md`「Preferred CLI tools」：优先 podman 而非 docker。
- [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)（代理配置，说明宿主机代理不透传到 podman machine VM 的背景）
- [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)（同类"单机环境配置修复"记录格式参考）
