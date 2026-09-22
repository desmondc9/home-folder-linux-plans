# Windows 11 宿主机加入 tailnet(新控制面域名) 实施计划

> 执行环境:AI 在 YAOSHI15PRO 的 WSL2 里;Windows 侧经 interop 代跑,提权步骤标 `[提权]`(一次 UAC);VPS 侧从 WSL ssh 代跑(`sudo -n` NOPASSWD)。

**Goal:** `https://headscale.signal-align.com` 服务现有 headscale;YAOSHI15PRO 以 `yaoshi15pro-win` 入网并通告 Exit Node;WSL/sing-box 零回归。

**Tech Stack:** Cloudflare API(dns-token)/ nginx + certbot(LE) / headscale 0.29.3 / Tailscale Windows(winget MSI)

**Spec:** [spec.md](spec.md)

## Global Constraints

- 存量 9 节点零影响:不动旧 vhost、旧证书、server_url
- preauth key 不落任何 git 跟踪文件(shell 变量传递,档案占位)
- 每个 Windows 侧变更后跑 WSL 回归:localhost 互通 + `podman ps` + 外网解析
- 回退:DNS 记录可删、vhost 单文件可删、`sc stop Tailscale`、`tailscale down`

---

### Task 1: CF DNS 记录 `headscale.signal-align.com` A 104.194.83.82(灰云) ✅ 2026-09-22

- [x] 创建记录(API,proxied=false) ✅ record id `8f0debcc0e252eb84d84b97debb0938b`,TTL auto
- [x] 双解析器验证 ✅ **踩坑记录**:本机所有 DNS 查询(含指定 `-Server` 直连权威 NS)都被宿主 sing-box `hijack-dns` 劫持,读到的是其上游(alidns/cfdoh)的 **NXDOMAIN 负缓存**,疑似"记录未生效";改用 **DoH 绕过验证**(`curl https://1.1.1.1/dns-query` + `https://8.8.8.8/resolve`)→ 记录实际已全球生效。教训:hijack-dns 环境下验证 DNS 变更必须走 DoH/HTTPS,普通查询结果不可信。约 10 分钟后负缓存自然过期,宿主解析恢复。

### Task 2: VPS 新 vhost + 证书 + 健康检查 ✅ 2026-09-22

- [x] `/etc/nginx/sites-available/headscale-new`(server_name 仅新域名,location 段逐行镜像旧 vhost,listen 80 先行) ✅ symlink 到 sites-enabled
- [x] `certbot --nginx -d headscale.signal-align.com`(独立证书) ✅ "Successfully deployed certificate",存量 bandwagon 证书未动
- [x] `nginx -t` + reload;`curl https://headscale.signal-align.com/health` ✅ VPS 侧 + 本机均 `{"status":"pass"}`(本机验证时用 `--resolve`/DoH 后直连)
- [x] 旧域名 /health 复测(存量兼容) ✅ `https://bandwagon.signal-align.com/health` → `{"status":"pass"}`
- 备注:reload 后首个请求见一次 301(旧 worker 竞态),随即恢复;`nginx -T` 确认新 server 块正确命中

### Task 3: headscale 侧准备 ✅ 2026-09-22

- [x] 删除旧 node 1 ✅ `nodes delete --identifier 1 --force` → "Node deleted";剩 node 2–9
- [x] 签发一次性 preauth key(`--user 1`,1h,不入库) ✅ 暂存 VPS `/tmp/opencode/.hs_preauth_key`,用后已删除;未出现在任何 git 跟踪文件
- 备注:删除 node 1 释放了 100.64.0.1,但新节点实际分配到 **100.64.0.10**(headscale 分配计数器不复用,与预期一致)

### Task 4: Windows 安装 Tailscale 并入网 `[提权一次]` ✅ 2026-09-22

- [x] winget 安装 Tailscale.Tailscale(MSI) ✅ v1.102.4,服务 `Tailscale`(Running/Automatic);UAC 弹窗被终端遮挡等待约 4 分钟,用户 Alt+Tab 后批准 —— interop 装机的固有摩擦,记录在案
- [x] `tailscale up --login-server=https://headscale.signal-align.com --hostname=yaoshi15pro-win --accept-dns=false --advertise-exit-node --authkey=__PREAUTH_KEY_REDACTED__` ✅ 静默成功
- [x] `tailscale status` 在线 ✅ `yaoshi15pro-win = 100.64.0.10`,可见全部 8 个 peers;`ExitNodeID: ""`(不自选出口,防环);入网前宿主已能解析新域名(负缓存过期)

### Task 5: Exit Node 批准 + 端到端验收 ✅ 2026-09-22

- [x] VPS:`headscale nodes approve-routes --identifier 10 --routes 0.0.0.0/0,::/0` ✅ "Node updated"(0.29 仍无 `routes list` 命令,与 2026-09-12 记录一致)
- [x] VPS 节点 `tailscale exit-node list` 出现 yaoshi15pro-win ✅ 批准后约 1 分钟 netmap 传播才可见(非即时,勿误判失败)
- [x] netcheck ✅ UDP true;IPv6 native(电信 240e:);Nearest DERP = bwg-derp **130.6ms**(基线 131.4ms 同量级)
- [x] WSL 回归 ✅ localhost 互通 / `podman ps` 正常 / 外网 200 / **`ssh desmond@100.64.0.4` 经 mirrored 直达 tailnet**;ping .4 0% 丢包(~143ms)
- [x] 回退开关登记 ✅ `tailscale down`(停用) / `sc stop Tailscale`(停服务) / 删 `/etc/nginx/sites-enabled/headscale-new`(下线新域名) / CF 删记录 —— 均不影响存量节点

### Task 6: 文档收尾 ✅ 2026-09-22

- [x] 实施结果回填本文件 ✅
- [x] README.md 索引补行 ✅
- [x] gitleaks 扫描 → commit + push main ✅(见下)
