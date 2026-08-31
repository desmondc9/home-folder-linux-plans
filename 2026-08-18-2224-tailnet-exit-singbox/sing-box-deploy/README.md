# sing-box 配置文件说明

本目录包含 sing-box 分流网关的所有配置文件。**这些文件是模板/源文件，需要部署到 `/etc/sing-box/` 后才能使用**。

## 文件清单与部署位置

| 文件 | 部署位置 | 说明 |
|---|---|---|
| `config.json` | `/etc/sing-box/config.json` | sing-box 主配置（已脱敏，见下方"敏感信息"节） |
| `tproxy.nft` | `/etc/sing-box/tproxy.nft` | nftables TPROXY 规则（含 redirect_nat 链） |
| `rules/custom-direct.json` | `/etc/sing-box/rules/custom-direct.json` | 强制直连规则（国内网站例外） |
| `rules/custom-proxy.json` | `/etc/sing-box/rules/custom-proxy.json` | 强制走代理规则（国外网站例外） |
| `99-exit-node.conf` | `/etc/sysctl.d/99-exit-node.conf` | IP 转发持久化 |
| `singbox-dns.conf` | `/etc/systemd/resolved.conf.d/singbox-dns.conf` | 系统 DNS 指向 223.5.5.5（经 sing-box 分流） |
| `sing-box-tproxy.service` | `/etc/systemd/system/sing-box-tproxy.service` | TPROXY 规则加载/清理的 systemd 单元 |
| `update-rules.sh` | `/etc/sing-box/update-rules.sh` | rule-set 智能更新脚本（检查远程更新并触发） |
| `sing-box-rules-update.service` | `/etc/systemd/system/sing-box-rules-update.service` | 更新服务（oneshot） |
| `sing-box-rules-update.timer` | `/etc/systemd/system/sing-box-rules-update.timer` | 定时器（每周一、四 03:30） |

## 敏感信息

`config.json` 中的以下字段已替换为占位符，部署前需填入真实值：

- `<VLESS-UUID>` — VLESS 节点的 UUID（从 V2rayN 或节点提供方获取）
- `<REALITY-PUBLIC-KEY>` — Reality 协议的公钥（从节点配置中提取）

**获取方式**（从已有 V2rayN 配置提取）:

```bash
jq -r '.outbounds[] | select(.protocol=="vless") | {
  uuid: .settings.vnext[0].users[0].id,
  pbk: .streamSettings.realitySettings.publicKey
}' ~/.local/share/v2rayN/binConfigs/config.json
```

## 部署步骤

```bash
# 1. 填入敏感信息
vim config.json  # 替换 <VLESS-UUID> 和 <REALITY-PUBLIC-KEY>

# 2. 校验配置
sing-box check -c config.json

# 3. 部署到 /etc/sing-box/
sudo mkdir -p /etc/sing-box/rules
sudo cp config.json tproxy.nft /etc/sing-box/
sudo cp rules/*.json /etc/sing-box/rules/

# 4. 部署系统配置
sudo cp 99-exit-node.conf /etc/sysctl.d/
sudo cp singbox-dns.conf /etc/systemd/resolved.conf.d/
sudo cp sing-box-tproxy.service /etc/systemd/system/

# 5. 部署 rule-set 自动更新
sudo cp update-rules.sh /etc/sing-box/
sudo chmod +x /etc/sing-box/update-rules.sh
sudo cp sing-box-rules-update.service sing-box-rules-update.timer /etc/systemd/system/

# 6. 启动服务
sudo sysctl --system
sudo systemctl daemon-reload
sudo systemctl enable --now sing-box sing-box-tproxy sing-box-rules-update.timer
sudo systemctl restart systemd-resolved

# 7. 验证
curl -4 -s https://api.ipify.org  # 应显示 VPS IP
curl -4 -s https://myip.ipip.net  # 应显示家宽 IP
systemctl list-timers sing-box-rules-update.timer  # 确认定时器已启用
```

## 自定义规则使用

编辑 `rules/custom-direct.json` 或 `rules/custom-proxy.json`，在对应数组中添加规则：

```json
{
  "version": 2,
  "rules": [
    {
      "domain": ["exact-match.com"],
      "domain_suffix": ["example.com"],
      "domain_keyword": ["keyword"],
      "ip_cidr": ["1.2.3.0/24"]
    }
  ]
}
```

修改后 `sudo systemctl restart sing-box` 生效。

## 沙盒测试

部署前可用 Podman 沙盒验证配置（不影响主机）:

```bash
cd sing-box-deploy

# 1. 下载 sing-box 二进制(只需一次)
curl -fSL -o sing-box "https://github.com/SagerNet/sing-box/releases/download/v1.13.19/sing-box-1.13.19-linux-amd64.tar.gz"
tar -xzf sing-box-1.13.19-linux-amd64.tar.gz --strip-components=1
rm sing-box-1.13.19-linux-amd64.tar.gz
chmod +x sing-box

# 2. 构建并运行沙盒
podman build -t singbox-sandbox .
podman run --rm --cap-add=NET_ADMIN localhost/singbox-sandbox
```

详见 `sandbox-test.sh` 和 `Containerfile`。

**注意**:`sing-box` 二进制文件（约 66MB）已通过 `.gitignore` 排除，不入库。每次克隆仓库后需按上述步骤重新下载。

## 参考

- 完整部署文档：`../README.md`
- 架构设计：`../spec.md`
- 实施记录：`../implementation.md`
