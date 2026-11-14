# 实施记录:headscale 控制面域名收敛

执行时间: 2026-11-12 16:01–16:10 CST · 执行人: opencode 会话(desmond 确认)
回退备份: `~/Backups/headscale-convergence-2026-11-12/`(config.yaml、旧/新 vhost、bandwagon 续期配置)

## 执行步骤与结果

| # | 操作 | 结果 |
|---|---|---|
| 1 | 备份 4 个文件 + 建立 plan 目录 | ✅ |
| 2 | `server_url` → `https://headscale.signal-align.com`,`systemctl restart headscale` | ✅ active;双域名 /health 均 200(切换窗口旧 vhost 仍在,无缝) |
| 3 | VPS 节点(4)重指 | ✅ `tailscale up --login-server=... --advertise-exit-node --force-reauth --authkey=<一次性 key>`;ControlURL=新域名;**id 4 / 100.64.0.4 身份不变**;exit node 路由 Approved+Serving(0.0.0.0/0, ::/0)保留 |
| 4 | vhost 收敛:删两个软链与旧文件,`headscale-new` 内容(更新注释)落为 `sites-available/headscale`,单软链 | ✅ `nginx -t` 通过,reload 成功 |
| 5 | 旧域名验证 | ✅ `/health` 404 + 证书不匹配(落默认 server),旧入口已失效 |
| 6 | `certbot delete --cert-name bandwagon.signal-align.com` | ✅ 其余 6 张证书不受影响 |
| 7 | 数据面验证 | ✅ `tailscale ping 100.64.0.10` pong via DERP(bwg) —— 内嵌 DERP(新域名链路)工作正常 |

节点 4 重指的两步弯路(记录备忘):
- `tailscale up` 报 "requires mentioning all non-default flags" → VPS 通告了 exit node,需带 `--advertise-exit-node`
- 改 ControlURL 需 `--force-reauth`;无 OIDC,用 preauth key:`headscale preauthkeys create -u 1 -e 10m -o json | jq -r .key`(**`--user` 是数字 ID,不是用户名**)

## 插曲:rakazo 并行操作

执行期间(16:00–16:04)另一进程删除了 `sites-available/rakazo` 及其软链并于 16:03 reload 了 nginx(worker 时间戳可证)。与本任务无关(本任务只触碰 headscale 两个 vhost),未干预。若非预期,检查 rakazo 部署会话。

## 离线节点改指指引(7 个,记录保留在 headscale)

设备下次上线时连旧域名会失败,按类型改指:

1. **先在 VPS 签发一次性 key**(30 分钟有效):
   ```bash
   sudo headscale preauthkeys create -u 1 -e 30m -o json | jq -r .key
   ```
2. **Windows/Linux PC**(WIN-75EIILSV34U、DESKTOP-J7NBNU4,各自补上原有的非默认 flag):
   ```powershell
   tailscale up --login-server=https://headscale.signal-align.com --force-reauth --authkey=<key>
   ```
   同一设备重新注册按机器键识别,身份/IP 不变(节点 4 已验证此行为)。
3. **iOS/Android**(desmond-ipad ×2、desmond-iphone-11、一加15、oneplus-15-sfa):Tailscale App → 退出登录 → 添加自定义服务器 `https://headscale.signal-align.com` → 用 authkey 登录。
4. 若某设备确认退役,可 `sudo headscale nodes delete -i <ID>` 清掉记录。

## 最终状态

- 控制面唯一入口: `https://headscale.signal-align.com`(vhost `headscale`,证书独立,2026-12-21 到期,certbot 自动续期)
- `sites-enabled`: auth, books, derp, **headscale**(唯一), ntfy, reading
- bandwagon.signal-align.com:DNS A 记录保留(SSH 等用途),HTTPS 入口已下线,证书已删
- 内嵌 DERP region 999(bwg)随 server_url 切至新域名;standalone DERP(derp.signal-align.com)不受影响
