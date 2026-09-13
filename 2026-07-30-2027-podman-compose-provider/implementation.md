# Implementation: Podman compose provider 排查与确认

对应 spec.md 的全部范围（单阶段）。

## 依赖

无（本机容器工具链环境配置，不依赖其他任务）。与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/) 的代理配置有间接关系（见「备注」）。

## 任务列表

- [x] 确认已安装：`podman --version`（6.0.2）、`docker-compose --version`（5.3.1）、`podman-compose --version`（1.6.0），均来自 Homebrew（`brew list` 命中 `podman`/`docker-compose`/`podman-compose`）。
- [x] 确认 `podman machine list`：`podman-machine-default` 处于 `Currently running` 状态（macOS 上 podman 依赖的 Linux VM 已就绪）。
- [x] 确认 `~/.config/containers/containers.conf` 不存在——未做过显式 provider 声明。
- [x] 创建最小化测试用 `compose.yml`（单个 `alpine` 服务，`echo` 命令）。
- [x] 执行 `podman compose config`：输出明确显示 `Executing external compose provider "/opt/homebrew/bin/docker-compose"`，并正确解析出 `services.hello`/`networks.default`。
- [x] 执行 `podman compose up` 做端到端验证：命令正常委托给 `docker-compose`，但拉取 `docker.io/library/alpine:latest` 时报 `i/o timeout`（根因见下）。
- [x] 诊断 `up` 失败原因：确认 `podman machine` 是独立 Linux VM，`~/.zshrc` 中配置给 macOS 宿主机 shell 的代理环境变量不会传递到 VM 内部；未配置镜像仓库代理/加速，故访问境外 `docker.io` 超时。判定为独立于"provider 选择"之外的网络问题，本任务不处理。
- [x] 清理临时测试目录（`compose.yml` 所在的 scratchpad 目录）。

## 变更文件 / 环境变更

| 变更项 | 内容 |
|------|----------|
| Homebrew | 无新增安装（`podman`/`docker-compose`/`podman-compose` 此前均已装好，本任务仅做状态确认） |
| `~/.config/containers/containers.conf` | 未创建——验证结果显示默认 provider 查找顺序已经优先选中 `docker-compose`，无需显式声明覆盖 |

未涉及任何代码仓库文件、API、数据库变更。

## 验证方式

- `which podman` / `which docker-compose` / `which podman-compose`：确认三者均可执行。
- `podman compose config`（对临时 `compose.yml`）：确认输出中 provider 一行指向 `docker-compose` 而非 `podman-compose`，且解析结果结构正确。
- `podman compose up` / `podman compose down`：确认命令委托机制本身工作（能到达"拉镜像"这一步），镜像拉取失败为已知的独立网络问题（见 spec.md「风险与缓解」）。

## 备注

- 本任务未创建 `git worktree` / 分支 / PR，因为改动对象是本机容器工具链（Homebrew 包 + podman 运行时行为），不属于任何代码仓库内的功能开发。
- **教训（可迁移经验）**：`podman compose` 是"委托"而非"内建实现"——只要目标 provider（`docker-compose`）装好并在 PATH 上，且其查找优先级天然高于 `podman-compose`，就不需要额外写 `containers.conf`。误以为"装了 podman-compose 就一定会被优先使用"是不准确的；`podman compose config`（不实际拉镜像/起容器）是验证 provider 选择是否符合预期的最低成本手段，无需先解决网络问题即可确认"配置对不对"。
- 若未来迁移到新机器：`brew install podman docker-compose`（可选装 `podman-compose` 作为兜底，但不影响默认行为）即可复现同样的 provider 选择结果；如需强制锁定，参照 spec.md「解决方案」第 3 条写 `containers.conf`。
- 遗留问题（有意不在本任务处理）：`podman machine` VM 内部访问 `docker.io` 超时，需要单独配置 VM 内代理或镜像加速，建议后续单开一个 `~/plans/*-podman-machine-registry-mirror` 之类的任务跟踪。
