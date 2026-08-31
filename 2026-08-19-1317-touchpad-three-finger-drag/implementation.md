# 触控板三指拖拽 实施计划(单阶段)

目标:落实 [design.md](design.md) 全部验收标准 · 依赖:cargo、input 组、/dev/uinput(实施前均已确认就绪)

## 文件变更清单

| 文件 | 来源 | 作用 |
|---|---|---|
| `~/linux-3-finger-drag/` | git clone(经代理 127.0.0.1:10809) | 源码,留作后续升级 |
| `/usr/bin/linux-3-finger-drag` | `target/release/` 构建产物(v2.0.0) | 主程序 |
| `/etc/udev/rules.d/60-uinput.rules` | 上游 `60-uinput.rules` | `/dev/uinput` uaccess 权限 |
| `/etc/modules-load.d/uinput.conf` | 内容 `uinput` | 开机加载 uinput |
| `~/.config/linux-3-finger-drag/3fd-config.json` | 上游模板,**改 `dragEndDelay: 0 → 250`** | 手感参数(热重载) |
| `~/.config/systemd/user/three-finger-drag.service` | 上游 unit | systemd user 服务,绑定 graphical-session |

## 任务列表

- [x] 环境盘点:Plasma 6.6.4 / Wayland / 触控板 event6 / cargo 1.95.0 / input 组 / /dev/uinput(全部就绪)
- [x] 调研选型:确认 KDE 原生不支持,选定 lmr97/linux-3-finger-drag(见 design.md 选型表)
- [x] 克隆仓库(经代理)并审阅 README、install.sh、udev 规则、service、默认配置
- [x] 发现并规避 install.sh EOF-重启陷阱 → 采用手动安装步骤
- [x] `cargo build --release`(10.3s 成功;crates.io 直连可用,未动镜像)
- [x] 用户级安装:config(dragEndDelay=250)+ service unit + `systemctl --user daemon-reload`
- [x] root 级安装(用户以 `! sudo bash -c '...'` 执行,howdy 面部认证):udev 规则、二进制、modules-load、`udevadm control --reload`
- [x] `systemctl --user enable --now three-finger-drag.service`
- [x] 验证(见下)
- [x] 留档:design.md / implementation.md 入 `~/plans/`;写入 memory(touchpad-three-finger-drag)

## 验证方式与结果

**日志验证**(`journalctl --user -u three-finger-drag`):
- 配置加载确认 `drag_end_delay: 250ms` ✅
- `Touchpad found: "UNIW0001:00 093A:0255 Touchpad" at /dev/input/event6` ✅
- `Exclusively grabbed the real trackpad` ✅
- 虚拟设备存在:`/proc/bus/input/devices` 可见克隆设备(Phys=`linux-3-finger-drag/proxy`)与 `Virtual trackpad (created by linux-3-finger-drag)` ✅

**实测验证**(用户确认"完美"):
- 三指按住拖窗口/选字 ✅ · 250ms 内续拖 ✅ · 快速轻扫切桌面 ✅ · 三指点按中键 ✅ · 单双指无回归 ✅

## 运维备忘

- 调手感:改 `~/.config/linux-3-finger-drag/3fd-config.json`(热重载,无需重启服务);速度调 `acceleration`
- 日志:`journalctl --user -u three-finger-drag -e`
- 升级:`cd ~/linux-3-finger-drag && git pull && cargo build --release`,重装二进制到 `/usr/bin/`
- 故障:触控板失灵 ≈ 服务挂了(1s 自动拉起),`systemctl --user status three-finger-drag` 确认
- ⚠️ 永远不要非交互运行上游 `install.sh`(EOF → 默认 y → 重启机器)
- 卸载:`systemctl --user disable --now three-finger-drag.service` + 删除上表 5 处文件 + 删源码目录,零残留
