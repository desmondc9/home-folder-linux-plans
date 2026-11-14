# 实施记录(完成后补记,操作于 2026-11-14 ~11:30)

## 诊断步骤(全部只读)

1. 定位源:`/etc/apt/sources.list.d/gvisor.list` → `deb [signed-by=/usr/share/keyrings/gvisor.asc] https://storage.googleapis.com/gvisor/releases stable main`(mtime 2026-09-17 16:51,与 gvisor.asc 同刻,即当日成对添加)
2. `apt policy runsc`:Installed/Candidate 均 `0.0~20230807.0-4ubuntu0.24.04.3`,来源 noble-updates/universe + noble-security/universe——**与 gvisor 源无关**
3. 使用面排查:`docker container inspect $(docker ps -aq)` → 6 容器 runtime 全 `runc`;daemon.json 仅注册 runsc 指向 /usr/bin/runsc;`containerd-shim-runsc-v1` 未安装
4. 根因核实:抓取 gvisor.dev/docs/user_guide/install(2026-11-14)→ apt 套件名为 `release`,旧 `stable` 已不存在

## 变更(用户确认后执行)

```bash
sudo rm /etc/apt/sources.list.d/gvisor.list /usr/share/keyrings/gvisor.asc
```

仅删这两个文件。runsc 包、daemon.json、容器一概未动。

## 验证

修复后 `sudo apt update` 输出(尾部):

```
Fetched 6,649 B in 1s (5,597 B/s)
Reading package lists... Building dependency tree... Reading state information...
55 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

无 E:/Err: 行,退出码 0。

## 遗留

- `sudo apt full-upgrade -y` 由用户自行重跑(积压 55 包,含被本故障阻塞的常规更新)。
- 将来启用 gVisor 沙箱时按 spec.md「风险与回滚」中的官方当前写法重建源(或 tarball 安装)。
