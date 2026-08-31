# 实施记录:自建 DERP 兜底中继

日期:2026-08-19 · 对应设计:[spec.md](spec.md)

所有 VPS 操作经 `ssh desmond@bandwagon.signal-align.com`(sudo 密码见 `~/.bandwagon/credentials.jsonc`,session 内 `sudo -S` 使用,未落盘到 VPS)。

## 实施清单

- [x] DNS:CF API 加 `derp.signal-align.com` A→`104.194.83.82` / AAAA→`2607:8700:5500:7bd3::2`(灰色云,ttl 3600,token 在 `~/.cloudflare/tokens.jsonc`,需 Zone.DNS:Edit 权限)
- [x] Go 1.26.6 → `/usr/local/go`(官网 tarball + sha256 校验;VPS 直连 go.dev,不走镜像)
- [x] derper 编译:`CGO_ENABLED=0 GOMEMLIMIT=1400MiB GOBIN=$HOME/go/bin /usr/local/go/bin/go install tailscale.com/cmd/derper@v1.102.2`(2GB 内存够用)→ `install -m 0755 ~/go/bin/derper /usr/local/bin/derper`
- [x] `useradd -r -s /usr/sbin/nologin -d /var/lib/derper derper`;`mkdir -p /var/lib/derper/certs`(derper:derper)
- [x] systemd `derper.service`(enabled)→ 见下方配置
- [x] nginx `/etc/nginx/sites-available/derp` + sites-enabled 软链 → 见下方配置
- [x] certbot --nginx 签发(有效期至 2026-11-17)
- [x] deploy hook `/etc/letsencrypt/renewal-hooks/deploy/derper-certs.sh`(755)→ 见下方
- [x] `ufw allow 3479/udp comment 'derper STUN'`(8443 不放行,靠默认 deny)
- [x] headscale:`/etc/headscale/derp-standalone.yaml` + config.yaml `derp.paths` → 重启
- [x] 验收:DERP 页面 / 101 Upgrade / netcheck 双区域 / certbot renew --dry-run

## 配置实体(排障速查)

### /etc/systemd/system/derper.service

```ini
[Unit]
Description=Tailscale DERP relay server (derp.signal-align.com)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=derper
Group=derper
ExecStart=/usr/local/bin/derper -c=/var/lib/derper/derper.key -hostname=derp.signal-align.com -a=:8443 -http-port=-1 -certmode=manual -certdir=/var/lib/derper/certs -stun=true -stun-port=3479 -verify-clients
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/derper

[Install]
WantedBy=multi-user.target
```

### /etc/nginx/sites-available/derp(SSL block 节选)

```nginx
location / {
    proxy_pass https://127.0.0.1:8443;
    proxy_ssl_server_name on;                    # 必须:derper manual 模式强制 SNI
    proxy_ssl_name derp.signal-align.com;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;   # 复用 conf.d/headscale-map.conf 的 map
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering off;
    proxy_read_timeout 3600s;                    # DERP 长连接
    proxy_send_timeout 3600s;
}
# listen [::]:443 ssl;   ← 注意:不能再写 ipv6only=on(headscale block 已声明)
```

### /etc/letsencrypt/renewal-hooks/deploy/derper-certs.sh

```bash
#!/bin/bash
set -e
DOMAIN=derp.signal-align.com
SRC=/etc/letsencrypt/live/$DOMAIN
DST=/var/lib/derper/certs
install -m 0644 -o derper -g derper "$SRC/fullchain.pem" "$DST/$DOMAIN.crt"
install -m 0640 -o derper -g derper "$SRC/privkey.pem" "$DST/$DOMAIN.key"
systemctl restart derper.service
```

### /etc/headscale/derp-standalone.yaml

```yaml
regions:
  998:
    regionid: 998
    regioncode: bwg-derp
    regionname: "Bandwagon DERP standalone"
    nodes:
      - name: 998a
        regionid: 998
        hostname: derp.signal-align.com
        ipv4: 104.194.83.82
        ipv6: 2607:8700:5500:7bd3::2
        stunport: 3479
        stunonly: false
        derpport: 443
```

config.yaml 变更:`derp.paths: []` → `derp.paths: ["/etc/headscale/derp-standalone.yaml"]`

## 升级路径

- derper:看 tailscale 新 release → `go install tailscale.com/cmd/derper@vX.Y.Z`(同构建参数)→ `install` 覆盖 `/usr/local/bin/derper` → `systemctl restart derper`
- Go:重下 tarball 覆盖 `/usr/local/go`(校验 sha256)

## 验证命令

```bash
curl https://derp.signal-align.com/                                    # derper 页面
curl -si -H "Connection: Upgrade" -H "Upgrade: derp" https://derp.signal-align.com/derp   # 101
tailscale netcheck                                                     # bwg + bwg-derp 双区域
ssh desmond@bandwagon.signal-align.com 'sudo journalctl -u derper -f'  # 中继连接日志
```
