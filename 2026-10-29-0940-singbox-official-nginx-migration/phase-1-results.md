# 阶段 1：候选配置与协议验证

> 历史记录：#68后来合并后又由#69撤销，本阶段不是最终生产部署。最终本机状态与Android v2rayNG验收见[final-state.md](./final-state.md)。

- 环境：本机 Ubuntu 24.04.4 LTS / linux amd64，rootless Podman 隔离网络；2026-10-29。
- 状态：实现与本地验证完成，独立审阅反馈已单轮修复并验证；PR已提交、CI绿，等待合并确认；未发布生产。
- Issue：[signal-align-umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)。
- 分支：`feature/singbox-vps-edge-config`；base `44a084d`，阶段初始完成提交 `37d6d53`。
- 最终提交：`6f13183`；[PR #68](https://github.com/desmondc9/signal-align-umbrella/pull/68)；[CI run 40805801336](https://github.com/desmondc9/signal-align-umbrella/actions/runs/40805801336)。changes/scripts通过，bridge-app/hydra/kratos/tofu-plan按路径跳过；新增协议suite本轮在本机完整运行，CI接线按计划留在阶段3，不把CI绿等同于已在CI运行这些新测试。
- Worktree：`~/.local/share/opencode/worktree/3390ca/2026-10-29-1000-singbox-vps-edge-config`（OpenCode 原生工具管理）。

## 交付物

- `scripts/vps_edge/config.py`：新凭据 schema/格式/密钥配对校验、服务端/客户端 JSON 与 VLESS URI；错误信息及 repr 不带认证值。
- `scripts/vps_edge/release_target.py`：严格选择 full / vps-edge，未知/重复/矛盾 selector 拒绝，不执行 release 文本。
- `local/vps/edge/`：正式协议候选、8个现有 vhost、非 root service 和离线测试环境。原 `local/vps/nginx-auth.conf` 与 CD workflow 没有修改。

官方 tarball 摘要与 1.14.4 版本都已核对；核心只解压在 `/tmp/opencode` 和测试容器，**没有安装进宿主机 PATH**，没有替换当前 1.14.2 服务。用于测试的 UUID/密钥/short ID 临时生成，不是未来生产凭据。

## 实测验证

1. 配置 unit 7/7，selector unit 6/6，均观察过缺失实现的失败再通过。
2. 容器内真实协议初版14/14，独立审阅补强后 **18/18**：
   - 11个域名 IPv4/IPv6 的既有 root 状态码（含4个404、auth307）。
   - 7个专门 health endpoint、80重定向、HTTP/2。
   - PROXY TCP4/TCP6 原始来源、IPv6外侧到IPv4回环不丢源地址。
   - 内部Web要求PROXY；公网443拒绝客户端注入PROXY；18790不被改成PROXY listener。
   - 未知/缺失SNI进Web default，WebSocket/DERP升级。
   - REALITY vision经两层stream的正确凭据成功、错误public key/short ID失败；内部端口仅回环。
   - 后端端口/身份/Host/path契约，拒绝误路由与错误health路径；各证书lineage只包含实际分组的SAN。
3. 新模块完整 unittest discover 14入口/14通过（其中1入口运行上面的14项容器协议测试）。
4. 原 `bash scripts/test-merge-image-tag.sh`：9/9；新shell入口 bash -n/shellcheck通过；git diff --check及gitleaks工作区扫描通过。
5. 8个候选vhost与现有运行文件排除listen/real_ip差异后，其他指令token完全一致；候选service在容器内systemd-analyze verify通过。

测试容器使用 `network_mode: none`、无published ports、只读挂载worktree；不连接任何线上应用，不使用真实证书或凭据，不运行OAuth/浏览器业务E2E。

## 环境与决策记录

- 原生OpenCode worktree由工具选择目录，不额外移动到 `.worktrees/`，以免破坏工具注册。代价：路径与通用模板不同，不影响生产行为。
- 计划中的配置源文本断言替换为真实请求和运行态监听断言。代价：fixture不覆盖所有线上业务细节，仍必须进行部署前后现场验收。
- 初次Compose构建失败是默认用户Podman API socket不存在，尚未进入配置测试。启用了临时用户API socket `/tmp/opencode/singbox-edge-podman-1001.sock`（0600），命令显式DOCKER_HOST；没有重启默认socket或现有服务，测试收尾会停止该临时进程。
- 收尾：测试project已down（没有残留资源）；仅停止本次创建的临时API进程，worktree/分支保留供PR修改。独立审阅反馈、单轮修复与全部执行判断见 [review-decisions.md](./review-decisions.md)，延期minor为无。

## 性能与容量

命中网关/连接路径的设计门禁，但此阶段候选未接入生产，无线上资源/频率变化。隔离环境证明协议与回环边界正确，不代表生产吞吐、延迟分位或用户网络已验收；生产备份/恢复、watchdog、证书迁移和新的Release CD仍属后续阶段。
