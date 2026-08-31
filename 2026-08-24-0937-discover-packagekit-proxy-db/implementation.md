# 实施记录 — Discover/PackageKit 代理修复

## 时间线（2026-08-24，CST）

- 09:11–09:13 取证：端口/apt 配置/systemd 环境/kioslaverc 定位，锁定 kioslaverc 残值（后被证伪为非根因，但确属附带垃圾）
- 09:16 清理 kioslaverc 4 条 10808 残值（备份 `~/.config/kioslaverc.bak-20260824`）
- 09:19 重启 Discover 验证 → **仍失败** → 假设证伪，回 Phase 1
- 09:2x 判别实验：手动驱动 `/usr/lib/apt/methods/https`，证明代理注入对 apt method 生效
- 09:2x `packagekitd` strings + `transactions.db` 读取 → **根因实锤：proxy 表 10 行僵尸 10808（2025-12-28 ~ 2026-05-08）**
- 09:34 用户执行 `DELETE FROM proxy`（count→0）+ `systemctl restart packagekit`
- 09:34:47 验证：Discover 启动自动 refresh-cache **success 6787ms**，22 源全绿 ✅

## 变更清单

| 文件/对象 | 变更 | 备份 |
|---|---|---|
| `~/.config/kioslaverc` | 删 httpProxy/httpsProxy/ftpProxy/socksProxy（均 10808） | `~/.config/kioslaverc.bak-20260824` |
| `/var/lib/PackageKit/transactions.db` 表 `proxy` | DELETE 全部 10 行 | 无（僵尸数据，无保留价值；原始内容已记录在 design.md） |

## 验证

```bash
# 修复后
$ journalctl -u packagekit --since "-2 min" | rg refresh-cache
Aug 24 09:34:47 … PackageKit[20482]: refresh-cache transaction /8011_abbdbaae
  from uid 1000 finished with success after 6787ms
# 零 "Unable to connect"，零 Transaction error
```

## 遗留

- `packagekit.service` unit 有 on-disk 变更未 daemon-reload 的警告（与本次无关，历史遗留，不影响）
- 若未来再次配置显式代理给 Discover：注意它会经 `SetProxy` 持久化到同一张表，弃用代理时需同样清表
