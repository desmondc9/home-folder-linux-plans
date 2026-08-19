# 移除 Cloudflare Zero Trust 残留 + 归档 frp 配置 — 实施记录

对应设计:[design.md](design.md) · 日期:2026-08-19

## 任务清单

- [x] 盘点 CF 残留:dpkg / systemd 单元 / apt 源 / keyring / 软链 / ssh config / 配置目录
- [x] 写移除脚本 `/tmp/remove-cloudflare-zerotrust.sh`
- [x] 用户以 `! sudo bash /tmp/remove-cloudflare-zerotrust.sh` 交互执行(人脸解锁 sudo)→ 输出 `ALL DONE`
- [x] 删除 `~/.ssh/config` 的 `Host yaoshi15pro.signal-align.com` 块(无需 sudo)
- [x] 验证:无二进制 / 无包 / 无单元 / 无进程 / 无 apt 源 / 无 keyring;`frpc.service` 仍 active running
- [x] 归档 frp 配置 → 独立档案 [../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/)(最初落在本目录 `frp/`,同日应用户要求 `git mv` 移出)
- [x] Cloudflare DNS 审计(`~/.cloudflare/tokens.jsonc` 的 dns-token,CF API 直连可达):三 zone 全量记录核对,tunnel CNAME 早已不存在;唯一残留 `edgetunnel` AAAA `100::` 为 Workers Custom Domain 只读记录
- [x] 尝试 API 删除 edgetunnel 记录 → 错误 1043 read-only(Workers 托管记录,DNS API 不可写);dns-token 无 Workers 权限 → 转 dashboard 手动项
- [ ] (用户手动,见 design.md「遗留」)Cloudflare dashboard 删除 tunnel、Workers 自定义域及 7 月遗留资源

## 变更文件表

| 文件/对象 | 变更 |
|---|---|
| `/etc/systemd/system/cloudflared.service`、`cloudflared-update.service`、`cloudflared-update.timer` | 删除(`cloudflared service install` 手动装的,不属于 deb) |
| deb 包 `cloudflared`、`cloudflare-warp` | `apt purge`(warp 由 rc 态彻底清干净,释放约 39.8 MB) |
| `/etc/apt/sources.list.d/cloudflared.list`、`cloudflare-client.list` | 删除 |
| `/usr/share/keyrings/cloudflare-public-v2.gpg`、`cloudflare-warp-archive-keyring.gpg` | 删除 |
| `/usr/local/bin/cloudflared` | 删除(指向 `/usr/bin/cloudflared` 的软链,包删后会悬空) |
| `~/.ssh/config` | 删除 `Host yaoshi15pro.signal-align.com` 3 行块 |
| `~/plans/2026-08-19-cloudflare-zerotrust-removal/` | 新增(本档案) |
| `~/plans/2026-08-19-frp-config-archive/` | 新增(frp 配置实体快照,独立成档) |

## 验证

脚本末尾自检输出:

```
cloudflared binary: gone
packages: gone
systemd units: gone
ALL DONE
```

补充抽查:`pgrep -af 'cloudflared|warp'` 无进程;`/etc/cloudflared`、`/etc/cloudflare-warp` 不存在;`ls /etc/apt/sources.list.d/ | grep -i cloud` 只剩无关的 `google-cloud-sdk.sources`;`/usr/share/keyrings/cloudflare*` glob 无匹配。`frpc.service` 全程 active running。

## 备注 / 可迁移经验

- **token 型(远端托管)CF tunnel 的 systemd 单元由 `cloudflared service install` 写入 `/etc/systemd/system/`,`apt purge` 不覆盖**——卸载 CF 类软件时,删包之外要单独检查 `/etc/systemd/system/` 下同名单元。
- 该单元的 `ExecStart` 内嵌 tunnel token;归档/贴日志前注意脱敏(本次单元已删,token 即失效)。
- 本机 sudo 需交互认证(人脸):agent 把需要 root 的步骤写成脚本,请用户用 `! sudo bash <script>` 在本会话执行,输出直接回落到对话里,衔接顺畅。
- frp 配置含 token,只允许进这个私人 plans 仓库;快照用 `install -m644` 落到 `/tmp` 再拷贝,绕开线上文件 0600 root 权限,agent 无需 sudo 读配置。
- **Cloudflare Workers Custom Domain 会自动建一条 DNS 记录(AAAA `100::` 橙云),该记录由 Workers 托管、DNS API 只读**——`DELETE /dns_records/:id` 报 1043 "read only"。删除路径是拆 Worker 的自定义域绑定(Domains & Routes),记录随之消失;审计 CF 残留时见到 `100::` 地址的橙云 AAAA 基本就是它。
- `~/.cloudflare/tokens.jsonc` 的 dns-token 对 CF API 直连可用(无需代理),但只有 DNS 权限,Workers/Zero Trust 资源需另配权限或走 dashboard。
