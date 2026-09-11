# WSL Ubuntu 原生 Podman 接入（弃用 Windows 共享 machine 方案）

- 日期：2026-09-11 21:20
- 状态：设计已确认（用户通过），待实施
- 环境：Windows 11 + WSL2（mirrored 网络模式）+ Ubuntu 26.04（resolute），systemd 已启用

## 背景与目标

用户在 Windows 安装了 Podman Desktop 与 Podman 6.0.2，并创建了 rootful machine
（`podman-machine-default` WSL 发行版）。目标是在 WSL Ubuntu 中获得可日常使用的
`podman` + `podman compose`（docker-compose 二进制 runtime，遵循全局 AGENTS.md 偏好）。

调研结论（2026-09-11 实测 + 官方文档）：

1. 共享 machine 方案（官方文档 "Accessing Podman from another WSL distribution"）技术上可行：
   machine 将 rootful socket 共享到 `/mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock`
   （root:gid10, 660），Ubuntu 侧需 `sudo usermod --append --groups 10`（Ubuntu gid 10 = `uucp`）
   + `podman system connection add --default ... unix:///mnt/wsl/...`。
2. **但**该方案下 Ubuntu 路径的 bind-mount 不受支持（上游开放 issue
   [podman#21813](https://github.com/podman-container-tools/podman/issues/21813)），
   仅 `/mnt/c`、`/mnt/d`、`/mnt/wsl`（RAM-backed tmpfs，WSL 停机即丢）可用。
   用户日常高频依赖 `~/...` bind-mount（本地开发栈热重载），且要求 GUI 可见——
   两者在共享 machine 方案下不可兼得。
3. 用户决策：**删除 Windows 侧 podman 与 machine，Ubuntu 原生 podman 作为唯一后端**；
   Podman Desktop 保留安装作为备用（后续实验性以 Docker connection 接入 Ubuntu podman）。

## 方案设计

### 架构

```
Ubuntu shell
 ├─ podman CLI ──────────► 本地 rootless podman（Ubuntu 发行版内直接跑容器）
 │                          └─ bind-mount ~/... 原生支持
 └─ podman compose ──► docker-compose v2 (apt: docker-compose-v2)
                        └─ DOCKER_HOST=$XDG_RUNTIME_DIR/podman/podman.sock
                            （systemd user socket；podman compose 自动注入）
```

- 容器直接运行在 Ubuntu 发行版内，无 machine、无跨发行版路径问题
- mirrored 网络模式下发布端口从 Ubuntu `localhost` 与 Windows 浏览器均可达

### Ubuntu 侧组件

| 组件 | 来源 | 说明 |
|---|---|---|
| `podman` 5.7.0 | apt（阿里云镜像源，无需代理） | 全量安装；rootless 前置条件已满足（subuid/subgid 已有 `100000:65536`；systemd 已启用且 user manager 在跑） |
| `docker-compose-v2` 2.40.3 | apt（阿里云镜像源） | 装后 symlink 实际插件路径（预期 `/usr/libexec/docker/cli-plugins/docker-compose`，以 `dpkg -L` 输出为准）→ `~/.local/bin/docker-compose`，供 `podman compose` provider 探测（`~/.local/bin` 已在 PATH） |
| `podman.socket` user unit | `systemctl --user enable --now podman.socket` | Docker 兼容 API socket（`$XDG_RUNTIME_DIR/podman/podman.sock`） |
| linger | `loginctl enable-linger desmond` | 保证 WSL 重启后无交互会话时 user systemd（含 socket）也在运行 |
| `/etc/containers/registries.conf` | 手写 | docker.io 主 mirror 定为 `docker.m.daocloud.io`（可用性实施时实测，不可用则换 `docker.1ms.run`）；仍失败按全局规范临时走 `127.0.0.1:10809` 代理（不写入持久配置） |
| 已装的 `podman-remote` 5.7.0 | 保留不动 | 无害；将来若重建 machine 可复用 |

### Windows 侧清理（用户手动执行）

```powershell
podman machine stop
podman machine rm -f
wsl --unregister podman-machine-default   # machine rm 通常已注销，此为兜底
# 设置→应用：卸载 "Podman for Windows"；**Podman Desktop 保留**
```

### 备用实验（可选，实施末尾尝试，失败不影响主方案）

目标：让保留的 Podman Desktop（Windows）显示 Ubuntu 原生 podman 的容器。

1. Ubuntu 侧：systemd user unit 跑 `podman system service --time=0 tcp://127.0.0.1:2375`
   （只绑 loopback；mirrored 网络下 Windows `localhost:2375` 可达，不暴露 LAN）。
2. Windows 侧：写入 docker context 文件（`%USERPROFILE%\.docker\contexts\meta\<sha256(name)>\meta.json`，
   endpoint `tcp://127.0.0.1:2375`、SkipTLSVerify=true，无需安装 docker CLI），
   然后 Podman Desktop → Settings → Docker Compatibility → Docker CLI Context 选中该 context。
3. 验证 Containers 列表出现 Ubuntu 容器。

已知风险：官方 Docker Compatibility 功能以「运行中的 podman machine」为前提；
machine 删除后 UI 能否由自定义 docker context 驱动需实测。失败则 Desktop 仅作备用，
不追其他方案（或以后评估 lazydocker/Pods 类 TUI）。

## 验收标准

1. `podman version`：Client=Server=5.7.0；`podman info` 无错误字段
2. `podman compose version` 输出 docker-compose v2.40.3
3. `podman run --rm -v ~/plans:/x:ro busybox ls /x` 能列出仓库文件（bind-mount 生效）
4. 测试 compose 栈（含 `./`相对路径 bind-mount + 发布端口 ≥1024）`podman compose -p <name> up -d`
   → Ubuntu `curl localhost:<port>` 成功；Windows 浏览器访问成功（mirrored 验证）→ `down` 清理
5. 归档收尾：本目录含 implementation.md；README.md 任务索引补行；`gitleaks dir .` 无泄漏

## 风险与对策

| 风险 | 对策 |
|---|---|
| 镜像拉取慢/失败（国内网络） | registries.conf 配 mirror 优先；仍失败临时 `http_proxy/https_proxy=127.0.0.1:10809` |
| rootless 无法绑定 <1024 端口 | compose 栈统一使用 ≥1024 端口（与既有 AGENTS.md 工作流一致） |
| WSL 重启后 user socket 未起 | enable-linger + user unit 自启 |
| fuse-overlayfs 性能 | 内核 6.18 支持 rootless 原生 overlay，podman 5.7 自动选择，无需干预 |

## 参考

- 官方教程：https://podman-desktop.io/docs/podman/accessing-podman-from-another-wsl-instance
- 跨发行版 bind-mount 限制：https://github.com/podman-container-tools/podman/issues/21813
- 本仓库工作流约定：`CLAUDE.md`（plans 归档、README 索引、gitleaks 红线）
