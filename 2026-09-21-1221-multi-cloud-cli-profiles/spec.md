# 多云 CLI 多账号常驻登录:az(AzureCloud + AzureChinaCloud)与 gcloud(dev/uat/prod/emulator)

> 2026-09-21,一次性环境配置 + 排障记录。目标:所有云账号在本机登录一次后,日常 `az` / `gcloud` 命令直接调 API,不再交互登录。

## 1. 最终架构

### Azure —— 分配置目录(`AZURE_CONFIG_DIR`)

| 别名 | 配置目录 | 云 | 账号 | 当前默认订阅 |
|---|---|---|---|---|
| `azg` | `~/.azure-global` | AzureCloud | desmondc9@outlook.com;shun.chen@centific.com | AzureSimple Pactera NA(Centific) |
| `azc` | `~/.azure-china` | AzureChinaCloud | Shun.chen@edgechina1.partner.onmschina.cn | CBOSS PROD ⚠️(6 个订阅:CBoss dev/uat/dr/prod + i-Sight dev/prod) |

- 两目录各自记住各自的云与活动订阅,永不错乱;裸 `az` 仍指向 `~/.azure`(保持空置备用)。
- 同一云多账号天然共存(`azg account list` 聚合),`azg account set -s <subId>` 切换。
- 交互登录一次后 refresh token 自动续期,**90 天内用过一次**就不会失效。

### GCP —— 原生 configurations + `CLOUDSDK_ACTIVE_CONFIG_NAME`

| 别名 | configuration | 项目 | 凭证 |
|---|---|---|---|
| `gdev` | hms-dev | gcp-ihs-hms-dev | SA key `~/.gcp/gcp-ihs-hms-dev-cc1e82b76d2a.json` |
| `guat` | hms-uat | gcp-ihs-hms-uat | SA key `~/.gcp/gcp-ihs-hms-uat-41e4103d7477.json` |
| `gprod` | hms-prod | gcp-ihs-hms-prod | SA key `~/.gcp/gcp-ihs-hms-prod-01ad7a40cf1f.json`(原名带空格 `...cf1f 6.json`,已改名,全盘确认无引用) |
| `glocal` | hms-local | gcp-local-project | dev SA(仅满足 gcloud "active account" 预检;emulator 不校验 token) |

- SA key 长期有效,无需重登;`~/.gcp/*.json` 已 `chmod 600`。
- 裸 `gcloud` 默认激活 hms-dev。
- 别名不改变持久 active config(env var 只对当次调用生效),互不干扰。

## 2. 日常速查

```bash
# Azure
azg vm list                                   # 全球区(Centific)
azg account set -s 2dba9ddf-...  && azg ...   # 切个人订阅
azc account set -s <subId> && azc ...         # 中国区切订阅(注意默认是 PROD)
az rest --url ...                             # 直接调 REST,同套凭证

# GCP
gdev projects describe gcp-ihs-hms-dev
guat spanner instances list
gprod run services list
glocal spanner instance-configs list          # 打本地 Spanner emulator(9020 REST)
glocal pubsub topics list                     # 打本地 Pub/Sub emulator(8085)

# 重登(仅 az 需要,90 天未活动才会)
azg login --use-device-code [--tenant <tid>]  # 本机无浏览器,设备码是标准姿势
```

## 3. 排障记录(根因,均已实证)

### 3.1 Azure:MFA 租户的登录姿势

现象:`azg login` 成功但 `No subscriptions found`,tenant 枚举阶段报 `AADSTS50076`(租户要求 MFA,后台静默 token 请求做不了 MFA)。
修法:`azg login --tenant <订阅所在租户ID> --use-device-code`,在设备码页面**完成 MFA**,订阅即出现。中国区/多账号同理。

### 3.2 GCP:gcloud 无限挂死 → Google v6 死路(已回填 ~/docs/network-access-china.md)

**表象**:`curl -6 https://oauth2.googleapis.com` → 000 超时;`curl -4` → 0.6s 正常;`getaddrinfo` 返回 **AAAA 在前**。curl 有 happy-eyeballs 回落,Python(gcloud)认准第一个地址死等 → "工具卡死不报错"。更阴险的是:gcloud 在 `config set` / `configurations activate` 时也会联网查 project env-tag / universe 描述符缓存 —— 连"本地"配置写入都会挂(先有鸡还是先有蛋)。

**根因(同日晚间补充分层测试后修正,初判"v6 路由黑洞"不准确)**:

| 测试(2026-09-21) | 结果 |
|---|---|
| 宿主 Windows:siteprefixes 在位、ping 阿里 DNS v6 | ✅ 通 |
| WSL:默认路由 + 全局地址(240e:389:a53e:d10::,与 9/17 修复后前缀一致) | ✅ 在位 |
| WSL 国内 v6(ping 2400:3200::1 7ms;tuna 镜像 200/0.13s) | ✅ 通 |
| WSL 国外未墙 v6(cloudflare 200、jsdelivr 301) | ✅ 通 |
| WSL Google v6 | ❌ 死(Google v4 正常) |

- **小米 AX6000 本次无罪**(用户初判"还是路由器"——已证伪;其 RA/PD 固件病史见 [2026-09-17-ipv6-ax6000-ra-outage](../2026-09-17-0915-ipv6-ax6000-ra-outage/),此刻路由器 v6 完全健康)。
- 真正机制:被墙域名的流量由 sing-box 经 **v4-only VPS** 代理,VPS 拨不出 IPv6 → Google 的 v6 路死、v4 路活;未墙的国外 v6 直连走路由器,畅通。
- **9/17 免疫层(sing-box 拒答 AAAA)存在 WSL 缺口**:WSL resolv.conf(10.255.255.254)→ 宿主网卡静态 DNS(223.5.5.5)→ 返回**真 AAAA**,绕过了 AAAA 拒答 → 无 happy-eyeballs 的工具(Python/gcloud,可能还有 Java)暴露在死路上。Chrome 靠 happy-eyeballs 幸存,所以宿主日常无感。

**修法(已实施)**:每个真实环境 configuration 烙入 `proxy/type=http, proxy/address=127.0.0.1, proxy/port=10809`(loopback 走 IPv4,天然绕开 v6);`glocal` 用环境变量级代理 + `NO_PROXY=localhost,127.0.0.1`(token 走代理、emulator 流量直连)。

**可选加固**(WSL 层让 IPv4 优先,惠及所有无 happy-eyeballs 的工具,需 sudo):`echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf`。

### 3.3 GCP:新版 gcloud(585)不认 `SPANNER_EMULATOR_HOST`,`--emulator-host` 参数也已移除

- 现象:设了 env var 后 `gcloud spanner ...` 拿着 dev SA 权限去打真实 API,报 IAM 403。
- 修法:hms-local 里配 `api_endpoint_overrides/spanner=http://localhost:9020/`、`api_endpoint_overrides/pubsub=http://localhost:8085/`(**必须带尾斜杠**,否则报 Invalid value),gcloud 的这两个 API 全部路由到本地 emulator。注意 Spanner emulator **9010 是 gRPC、9020 才是 REST**(gcloud 走 REST,所以指 9020)。
- 别名里保留 `SPANNER_EMULATOR_HOST=localhost:9010` / `PUBSUB_EMULATOR_HOST=localhost:8085` 供客户端库工具使用。

## 4. 验证证据(2026-09-21)

- `azg account show` → Centific 订阅;`azg group list` 两账号各自返回 eastus/eastasia 资源组(真实 ARM 调用)。
- `azc account show` → AzureChinaCloud + CBOSS PROD;`azc group list` 返回 chinaeast3/chinanorth3 资源组。
- gdev/guat/gprod:`gcloud projects describe` 均 ACTIVE(纯配置级代理,无环境变量)。
- glocal:spanner `instance-configs list` 返回 `emulator-config`、pubsub `topics list` 200 空列表(均来自本地容器)。

## 5. 遗留 / 后续

- [ ] GroupHEALTH 租户被管理员策略挡住(AADSTS50105,Azure CLI 企业应用未分配用户)—— 需该租户管理员操作,本机无解;不影响现有账号。
- [ ] `gcloud config configurations delete hms-uat-tw-release`(与 hms-uat 重复)—— 等 UAT 部署脚本(正在用该配置)跑完后删。
- [ ] (可选)WSL `/etc/gai.conf` IPv4 优先,加固所有无 happy-eyeballs 的工具(需 sudo,见 §3.2;对 gcloud 非必需,代理方案已闭环)。
- [ ] 9/17 免疫层的 WSL 缺口:WSL DNS 仍拿到真 AAAA(10.255.255.254 → 宿主静态 DNS 223.5.5.5,绕过 sing-box AAAA 拒答)。如要彻底堵:WSL 侧 gai.conf(上行)或宿主侧让 WSL DNS 也过 sing-box。
- [ ] `~/docs/network-access-china.md` 中 sing-box 配置路径 `C:\Users\Desmond\Apps\sing-box\config.json` 已失效(目录不存在),待下次动 sing-box 时订正。
- [ ] emulator 容器(spanner + pubsub)当前由本次排障拉起、保持运行;不用时 `podman compose -f ~/Repos/ups-hms-all-in-one/backend/docker-compose.yml stop spanner pubsub`。
