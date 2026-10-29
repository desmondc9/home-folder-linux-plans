# VPS-edge 协议与候选配置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成并验证官方 sing-box 与 Nginx 的候选配置，不改变生产服务。
**Architecture:** Python 标准库提供配置、密钥格式、发布范围和基线契约；Nginx 与 sing-box 候选文件先在隔离容器网络验证。本阶段不接入任何生产部署入口，合并也不会改变在线布局。
**Tech Stack:** Python 3.12 unittest、Bash、Nginx 1.24、sing-box 1.14.4、Podman。
**Spec:** [spec.md](./spec.md)，关联 [umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)。

## Global Constraints

- official 1.14.4；官方 tarball SHA256 `699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968`。
- 连接 `vs.signal-align.com:443`，SNI/handshake `www.cloudflare.com:443`；VLESS/TCP/REALITY/xtls-rprx-vision/chrome。
- 公网 stream 443 → Web 127.0.0.1:14443 或 REALITY 解包中继 127.0.0.1:24444 → 核心 127.0.0.1:24443；公网不能接收 PROXY，核心不能收到 PROXY。
- 生产仅 PR → Release → CD；真实密钥、备份和部署态配置不入库。fixture 源于 spec/已测结构，测试密钥运行时生成。
- 本阶段 ≤3 points/一天；分支 `feature/singbox-vps-edge-config`，执行前 fetch 后从 origin/main 创建隔离 worktree。使用 repo 的 plans 命名约定复制本 spec 和本 phase 文档，公开主档仍在 ~/plans。

## Review Focus

1. 有效 IPv6 客户端经 IPv4 回环转发，HTTP 仍获得原 IPv6 来源；Task 3 PROXY TCP6 测试。
2. 缺失/未知 SNI 不误入 REALITY；Task 3 默认分流测试。
3. 私钥/公钥不配对或凭据字段缺失，渲染在写文件前拒绝；Task 1 格式与配对测试。
4. release notes 内未知/重复 selector 不能降级成 full；Task 2 selector 测试。
5. 原来 404/307 的站点不被当失败或修改路由；Task 3 baseline 语义测试。

## Files / boundaries

| 路径（均相对 umbrella repo） | 职责 |
|---|---|
| `scripts/vps_edge/{__init__,config,release_target}.py` | 协议渲染/验证、严格发布目标解析；不执行服务操作 |
| `local/vps/edge/manifest.json` | 无秘密的版本、端口、官方摘要、KV 名称注册表 |
| `local/vps/edge/nginx/nginx.conf`、`stream.conf`、`sites/*.conf` | 候选共享入口与完整站点配置；auth 候选也在这里，不改现有部署文件 |
| `local/vps/edge/sing-box.service` | 专用非登录用户服务、启动前核心 check、无网络管理 capability |
| `scripts/tests/vps_edge/test_{config,release_target,nginx_contract}.py` | 单元与协议契约测试 |
| `local/vps/edge/tests/{Containerfile,compose.yml,run-contracts.sh}` | 独立端口/网络的契约测试环境，不启动正式 auth/DB |

## Interface Schema（后续阶段必须依此实现）

`EdgeCredentials` 为 dataclass：`schema_version: int=1`, `uuid: str`, `private_key: str`, `public_key: str`, `short_id: str`。UUID v4；密钥为配对 X25519 base64url；short_id 固定 **16 个小写十六进制字符（8 bytes）**，必须通过官方核心实测。整组作为单个 KV secret `sing-box-vs-credentials` 的 JSON value 保存，避免分字段轮换产生混配。

`manifest.json` 字段：`schema_version=1`，`sing_box_version="1.14.4"`，`archive_sha256`，`connection_host="vs.signal-align.com"`，`server_name="www.cloudflare.com"`，`web_port=14443`，`relay_port=24444`，`inbound_port=24443`，`vault_name="signal-align-kv-w2"`，`credential_secret="sing-box-vs-credentials"`。不存认证值。

配置 API：`validate_credentials(raw: dict, binary: Path) -> EdgeCredentials`；`server_config(credentials: EdgeCredentials) -> dict`；`client_config(credentials: EdgeCredentials, server: str="vs.signal-align.com", socks_port: int=10808) -> dict`；`client_uri(credentials: EdgeCredentials) -> str`。格式以官方核心 check 验证；X25519 配对用已有 OpenSSL pkey 从受限 DER 私钥文件推导公钥并比较（值不放 argv），最终还需真实往返证明；不得把输入或核心含秘密的错误原文打印到控制台。服务端只含一个 vless inbound + direct outbound，客户端不携带 private_key。

发布 API：`release_target(body: str) -> Literal["full","vps-edge"]`；无 selector 为 full，唯一独立完整行 `deployment-target: full|vps-edge` 可接受；任何以 deployment-target 为键的未知值、重复行、矛盾行或尾随垃圾抛 ValueError。调用方日志只显示 target/错误类别，不打印整段 body。

### Task 1: 官方核心与凭据/配置契约

- [ ] 写 `test_config.py`：断言 manifest 的 exact values、server listen/flow/handshake、client 没有 private_key、URI 的 scheme/flow/security/type/fp；拒绝无效 UUID、奇数/非 hex short ID、缺失密钥；用运行时生成的两个 keypair 构造不配对负例。

  ```python
  def test_server_contract(self):
      inbound = server_config(self.credentials)["inbounds"][0]
      self.assertEqual((inbound["listen"], inbound["listen_port"]), ("127.0.0.1", 24443))
      self.assertEqual(inbound["users"][0]["flow"], "xtls-rprx-vision")
      self.assertEqual(inbound["tls"]["reality"]["handshake"]["server"], "www.cloudflare.com")
  ```
- [ ] 运行 `python3 -m unittest discover -s scripts/tests/vps_edge -p test_config.py -v`，确认新测试因模块/API 缺失失败，而不是环境或网络故障。
- [ ] 实现 config API、manifest 和 service 候选。从官方固定 URL 下载 tar 到 `/tmp/opencode` 任务目录，先校验摘要、拒绝路径穿越再解包；不安装进系统 PATH。验证 `version` 精确 1.14.4。若需要额外工具，先评估并安装测试工具，不触碰运行中的核心。
- [ ] 重跑测试，并以临时生成凭据执行官方 `check -c <fixture>`；新旧凭据不在日志中显示。记录 short ID 与非 root service 权限验证结果。
- [ ] commit 本任务文件，消息 `feat(vps-edge): add official sing-box configuration contracts`。

### Task 2: 严格 release selector

- [ ] 写 `test_release_target.py`：`release_target("")=="full"`；单行 vps-edge/full 正确；未知值、两个相同 selector、两个矛盾 selector、尾随字符均抛错；包含 shell 元字符的其他文本只当数据，不执行。

  ```python
  def test_reject_duplicate_target(self):
      with self.assertRaises(ValueError):
          release_target("deployment-target: vps-edge\ndeployment-target: vps-edge\n")
  ```
- [ ] 运行 `python3 -m unittest discover -s scripts/tests/vps_edge -p test_release_target.py -v`，确认未实现时失败。
- [ ] 实现纯函数及 CLI：`python3 -m scripts.vps_edge.release_target < body.txt`，成功 stdout 仅 target，校验失败 exit 2；GitHub 表达式不得插入 shell 源码。
- [ ] 重跑相同测试全部通过，commit `feat(vps-edge): validate release deployment targets`。

### Task 3: Nginx 双分支与现有站点契约

- [ ] 只读导入现有完整 vhost 内容为候选；私钥只引用文件路径，保留 include 顺序、默认 server、location、headers、证书 SAN 对应与 80/18790 布局。原 `local/vps/nginx-auth.conf` 此阶段保持原样。
- [ ] 写 `test_nginx_contract.py`：为 spec 列出的 11 域记录 exact baseline，4 个原 404 + auth 307 不能转成 200；断言所有候选 Web TLS listen 只在 14443、只有这些 server 信任回环 PROXY，18790 不新增 real_ip；stream 精确 SNI 路由、default Web、relay 解包。
- [ ] 先运行测试确认候选缺失/未迁移时失败；随后实现候选配置。worker_connections=4096、rlimit=16384，preread=10s、connect=3s、idle=24h、relay PROXY header timeout=3s；core 目标连接=5s、TLS handshake=15s。使用 Nginx 1.24 支持的指令，不抄 1.31 新语法。
- [ ] 写隔离测试环境：测试证书/目标服务仅容器网络，fixture Web echo 接收来源/Host，fixture raw TCP 服务核对收到的首字节为 TLS 而非 PROXY；注入 TCP4/TCP6 头，断言 HTTP 回显的来源完全相符；未知和无 SNI 均进 Web。使用 spec 派生的测试值，不读取真实私钥。
- [ ] 在同一隔离网络加入真实官方 REALITY server/client 与测试 TLS handshake 目标（仅测试环境覆盖目标地址，不改生产 manifest），对 fixture HTTP origin 完成正例代理请求；wrong public key / short ID 两个负例不能取得 origin 的标记响应。证明 16-hex short ID、vision 与双层 stream 真正互通，而不仅是 nginx -t 通过。
- [ ] 运行 `podman compose -p <task>-contracts -f local/vps/edge/tests/compose.yml run --rm contracts` 与 unit discover；这是本模块协议 integration/contract test，不是业务 E2E。容器不绑定正式 80/443/18790，不调用生产 systemctl。fixture 中暂缺备份证书路径通过 test-only mount/渲染覆盖，不弱化生产证书校验。
- [ ] 执行格式/秘密扫描，commit `feat(vps-edge): validate nginx stream routing and source IP`；跑 `bash scripts/test-merge-image-tag.sh`，关联 #67 提 PR；无 production release。完成后记录测试、性能门禁（仅候选）并等 CI 绿再合并。

## Phase handoff

后续阶段消费上述 Python API、manifest schema 和候选路径，不重新定义端口/字段；阶段完成的含义是候选与测试可用，**不是线上已迁移**。阶段 2 从合并后的 main 开新分支。
