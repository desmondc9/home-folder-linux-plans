# apt update 404:gVisor apt 源 suite 更名(stable→release)处置

> 日期:2026-11-14 11:39 ｜ 类型:系统故障修复(VPS 本机操作,无 repo 代码变更)
> 环境:搬瓦工 VPS brave-goose-1(tailnet 100.64.0.4,exit node 提供方)/ Ubuntu 24.04.4 LTS (noble) / 内核 6.8.0-149-generic / Docker 29.1.3(daemon.json 注册 runsc 运行时,现存 6 容器全部 runc)

## 现象

```
sudo apt update && sudo apt full-upgrade -y
Err:10 https://storage.googleapis.com/gvisor/releases stable Release
  404  Not Found
E: The repository '...stable Release' does not have a Release file.
```

**隐性副作用(比报错本身影响更大)**:`apt update` 因该源非零退出,`&&` 后半的 `full-upgrade` 自源加入日(2026-09-17)起从未执行过——本次修复后首跑即积压 55 个待升级包。

## 根因(一手来源 2026-11-14 核实:gvisor.dev/docs/user_guide/install)

1. **官方 apt 仓库仍在发布,只是 suite 名从 `stable` 改成了 `release`**。当前官方写法:
   `deb [arch=amd64 signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main`
   改名发生在 gVisor 2026-07 转向多文件发布(单二进制 → `runsc` + `containerd-shim-runsc-v1` + `gvisor-bin/` 旁挂目录,google/gvisor#13718)同期;且旧式安装的 auto-download 兜底已于 2026-09 底移除。
2. 本机 `/etc/apt/sources.list.d/gvisor.list`(2026-09-17 加入,含配套 `/usr/share/keyrings/gvisor.asc`)用的是旧 suite `stable` → 该 dists 路径 404。**即该源从加上第一天起就 404,从未成功提供过任何包。**
3. 本机 `runsc` 包并非来自该源:`0.0~20230807.0-4ubuntu0.24.04.3` 来自 **noble-updates/universe**(Ubuntu SRU 维护的上游 2023-08 快照)。删源零损失。
4. 使用情况:docker daemon.json 仅注册 `"runsc": path=/usr/bin/runsc`,现存 6 容器(reading-app、ntfy、books-and-articles、signal-align-auth×3)`HostConfig.Runtime` 全部 = `runc`,**无任何容器实际使用 runsc**。

## 决策(用户会话内确认)

- **删除死源,保持现状**:runsc 继续由 Ubuntu noble-updates 安全维护;不恢复上游源——无容器使用 runsc,升级收益仅在未来。
- 将来实际需要 gVisor 沙箱时,按官方当前文档安装(suite=`release` 的 apt 源,或 `releases/release/latest/${ARCH}` tarball 到 /usr/local/bin;注意新布局要求 `gvisor-bin/` 与 runsc 同目录)。
- 修正记录:会话中曾初步判断"官方已停止 apt 仓库",经 gvisor.dev 一手核实修正为"suite 更名",本档案以核实结论为准。

## 验收标准

- [x] `apt update` 零错误、零 404,退出码 0(55 包待升级可见)
- [x] runsc 包保留,`runsc --version` 正常,docker daemon.json 未动,既有容器不受影响
- [ ] 用户自行重跑 `sudo apt full-upgrade -y` 清掉积压(含被本故障阻塞两个月的升级)

## 风险与回滚

- 无风险:删除的源从未成功提供过包。
- 回滚(若将来要恢复上游源):
  ```bash
  curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | sudo tee /etc/apt/sources.list.d/gvisor.list
  sudo apt update && sudo apt install runsc   # 版本号高于 0.0~*,会替换 universe 版
  ```

## 关联

- 同机前档:`2026-11-01-1447-tailscale-security-upgrade/`(本 VPS 包管理/unattended-upgrades 相关)
