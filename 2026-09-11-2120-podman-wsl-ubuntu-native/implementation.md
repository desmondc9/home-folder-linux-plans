# 实施记录：WSL Ubuntu 原生 Podman

对应 [spec.md](./spec.md)。任务清单、变更文件、验证与教训。

## 任务清单

- [x] 方案调研与决策：共享 machine vs 原生（结论见 spec「背景与目标」；弃共享 machine 的根因 = 跨发行版 bind-mount 不支持，podman#21813）
- [x] 仓库 git 修复：`.git/config` 残留主机侧 `http.proxy=127.0.0.1:10809`（本机无该代理，git 全部网络操作卡死）→ unset 两项；remote 改 `ssh://git@ssh.github.com:443/desmondc9/home-folder-linux-plans.git`（本机 `~/.ssh/id_rsa` 已注册 GitHub，22 端口不可靠改走 443）；repo-local 补 user.name/user.email
- [x] gitleaks 8.30.1 安装至 `~/.local/bin/`（GitHub releases 直连下载，本机直连 GitHub 可用、ghproxy 镜像反而 SSL 失败；主机规范中的 10809 代理在本 WSL 不存在）
- [x] `apt install podman 5.7.0 + docker-compose-v2 2.40.3`（**用户手装**——本机 sudo 无免密，沿用 [sdkman-jdk21](../2026-09-11-2142-sdkman-jdk21/) 的用户手装惯例）
- [x] `~/.config/containers/registries.conf`：`unqualified-search-registries=["docker.io"]` + docker.io 双 mirror（daocloud → 1ms.run）。（**spec 偏离**：设计写的是 `/etc/containers/`；实施改用户级——免 sudo 且 rootless 下用户级覆盖系统级，效果等价、影响面更小）
- [x] `~/.local/bin/docker-compose` symlink → `/usr/libexec/docker/cli-plugins/docker-compose`（`podman compose` provider 探测 PATH）
- [x] `systemctl --user enable --now podman.socket`（Docker 兼容 API：`$XDG_RUNTIME_DIR/podman/podman.sock`）
- [x] `loginctl enable-linger desmond`（**直接成功无需 sudo**——WSL logind 允许 self-linger；`Linger=yes` 复核）
- [x] 验证五连（见下）
- [ ] Windows 侧清理（用户手动）：`podman machine stop && podman machine rm -f` → 确认 `wsl -l -v` 无 podman-machine-default（残留则 `wsl --unregister`）→ 设置→应用 卸载 "Podman for Windows"（**保留 Podman Desktop**）
- [ ] 备用实验：Ubuntu 侧 `podman system service tcp:127.0.0.1:2375` user unit + Windows docker context 文件 + Podman Desktop Docker Compatibility 选择 context（步骤见 spec「备用实验」；失败不影响主方案）

## 变更文件表

| 文件 | 变更 |
|---|---|
| `~/.config/containers/registries.conf` | 新建（短名解析 + mirror 链） |
| `~/.local/bin/docker-compose` | 新建 symlink |
| `~/.config/systemd/user/sockets.target.wants/podman.socket` | enable 产生 |
| `~/.local/bin/gitleaks` | 新建二进制 v8.30.1 |
| 本仓库 `.git/config` | unset http(s).proxy；remote → ssh 443；user identity |
| `/tmp/opencode/compose-test/` | 一次性验证栈（compose.yml + html/），验证后已 `down` |

## 验证记录（2026-09-11 21:2x–21:5x）

| 验收项（spec §验收标准） | 结果 |
|---|---|
| 1. `podman version` Client=Server=5.7.0 / `podman info` | ✓ |
| 2. `podman compose version` → docker-compose 2.40.3 | ✓（provider 探测 symlink 生效） |
| 3. `podman pull nginx:alpine`（短名 + mirror） | ✓（daocloud 直连，未用代理） |
| 3b. `podman run -d -p 8080:80 nginx:alpine` → `curl localhost:8080` | ✓ HTTP 200（已清理） |
| 4. compose 栈：`./html` bind-mount + `8088:80` → up → curl → down | ✓ 返回 `<h1>hello from bind mount</h1>`，`podman ps -a` 无残留 |
| 5. 归档收尾 | 本文件 + README 索引 + gitleaks + commit/push |

socket：`curl --unix-socket $XDG_RUNTIME_DIR/podman/podman.sock http://d/_ping` → `OK`。
Windows 浏览器访问容器端口（mirrored 网络）未在本轮显式验证——下次起栈时顺带确认。

## 教训 / 可迁移经验

1. **Ubuntu/Debian 的 `/etc/containers/registries.conf` 默认不含 `unqualified-search-registries`**（商标策略），短名 `podman pull nginx` 直接报错；用户级 `~/.config/containers/registries.conf` 即可修复，无需 sudo。
2. **灾备恢复的 `.git/config` 会带着旧主机的 proxy 设置**：本机无 10809 代理 → git ls-remote/push 全部静默卡死（curl 反而正常，因为 curl 不读 git 配置）。新机恢复后第一件事检查 `git config -l | grep proxy`。
3. **GitHub 访问**：本 WSL 直连 github.com 可用（网页 + releases + git smart-http）；`ssh.github.com:443` + 已注册的 id_rsa 是 push 的可靠通道。
4. `"/" is not a shared mount` 警告在 WSL rootless podman 下是常见噪音，本轮 run/bind-mount 均未受影响；若将来出现挂载异常，用 `/etc/wsl.conf [boot] command` 加 `mount --make-shared /`。
5. mirrored 网络模式下 WSL 内 rootless 容器的发布端口，理论上 Windows localhost 直接可达（待下次实测确认）。
6. `loginctl enable-linger <self>` 在 WSL systemd 下无需 sudo（logind 允许 self-linger）。
