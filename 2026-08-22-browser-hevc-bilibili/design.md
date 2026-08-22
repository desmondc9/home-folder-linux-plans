# Chrome/Edge 报"浏览器不支持 HEVC"(B 站直播)

日期: 2026-08-22
状态: 已修复——Chrome/Edge 双双验收通过:B 站"浏览器不支持 HEVC"提示消失、直播播放正常

## 背景

B 站直播播放时提示"浏览器不支持 HEVC"(B 站播放器检测 `canPlayType`/MediaCapabilities 失败后的提示)。Chrome 151.0.7922.173、Edge 151.0.4129.101 均受影响。

## 根因(证据链,四层叠加)

Linux 版 Chromium 系浏览器**没有 HEVC 软解**(专利原因),HEVC 只能走 VAAPI 硬件解码。本机四层全缺:

| 层 | 问题 | 证据 |
|---|---|---|
| 硬件拓扑 | 独显直连模式,仅 NVIDIA RTX 4060(无 Intel 核显) | `lspci` 无 Intel VGA;`/dev/dri` 仅 `card1`/`renderD128`(NVIDIA) |
| VAAPI 驱动 | 只装了 Intel 驱动(i965/iHD),对 NVIDIA 无效 | `dpkg -l`;修复前 `vainfo` 打不开驱动 |
| Chromium 策略 | VAAPI 代码**故意跳过 NVIDIA 设备**(`kVaapiOnNvidiaGPUs` 默认禁用) | Chromium 源码 `media/gpu/vaapi/vaapi_wrapper.cc`;运行日志 `WARNING: Should skip nVidia device named: nvidia-drm` |
| 特性开关 | 硬件解码(`VaapiVideoDecoder`)、HEVC 能力宣告(`PlatformHEVCDecoderSupport`)未开 | 修复前 `canPlayType('video/mp4; codecs=hev1...')` 为空 |

叠加导致:浏览器不声明 HEVC → B 站弹提示。

### 排查过程中的两个坑(记录备查)

1. **canPlayType 查询格式**:Chrome 不支持裸 `video/hevc` / `video/h264` 容器,必须用 `video/mp4; codecs=...` 查询。用错格式会得出"连 H.264 都没有"的错误结论,浪费了一轮排查。
2. **KDE 启动器缓存**:修改用户级 `~/.local/share/applications/google-chrome.desktop` 后,从任务栏/菜单重启 Chrome 命令行零参数(连原有的 `--process-per-site` 都丢了)——KDE 用的是系统级 .desktop + 过期 ksycoca 缓存。`kbuildsycoca6 --noincremental` 重建 + 从开始菜单启动后生效。

### 验证方法(修复期复用)

用 Playwright MCP / CDP 起独立 profile 的真实 Chrome 跑 `canPlayType` + `MediaCapabilities.decodingInfo` 探针(Playwright 自带 Chromium 不带专有编解码器,不能代表真实 Chrome,勿用)。测试实例需 `--ozone-platform=x11` 避开本机 Wayland+Vulkan 冲突。

## 解决方案

1. **安装驱动**:`sudo apt install nvidia-vaapi-driver`(universe 源,0.0.14,NVDEC 后端)。装后 `vainfo` 显示 `VAProfileHEVCMain/Main10/Main444` 全系。
2. **特性开关**(三件套,缺一不可):
   `--enable-features=VaapiVideoDecoder,VaapiOnNvidiaGPUs,PlatformHEVCDecoderSupport`
   - `VaapiVideoDecoder`:启用 VAAPI 硬解
   - `VaapiOnNvidiaGPUs`:解锁被 Chromium 跳过的 NVIDIA
   - `PlatformHEVCDecoderSupport`:向页面宣告平台 HEVC 解码能力
3. **固化到启动器**:`~/.local/share/applications/google-chrome.desktop`(原 3 条 Exec 追加 flags)+ `~/.local/share/applications/microsoft-edge.desktop`(从 /usr/share 复制后同样追加 3 条)。
4. **重建 KDE 缓存**:`kbuildsycoca6 --noincremental`。

## 验收标准

- [x] 修复后测试实例 `canPlayType('video/mp4; codecs=hev1.1.6.L120.90')` = "probably",`decodingInfo` supported/smooth/powerEfficient 全 true
- [x] 用户真实 Chrome(开始菜单启动)同串查询 = "probably"(23:41 确认)
- [x] B 站直播页强刷后提示消失、HEVC 流正常播放(23:54 用户确认)
- [x] Edge 重启后同样生效(23:54 用户确认)

## 风险与缓解

- **nvidia-vaapi-driver 是社区驱动**:若出现花屏/卡顿,回退 = 去掉 flags 中的 `VaapiVideoDecoder`(其余两个保留)。
- **Chrome 升级覆盖系统 .desktop**:用户级 `~/.local/share/applications/` 文件不受影响,flags 存活。
- **任务栏图标缓存旧启动项**:ksycoca 重建后应从桌面文件 ID 解析到用户级文件;若个别启动入口仍零参数,需重钉图标或在包装脚本层注入(未采用:会被包升级覆盖)。
- **Wayland ozone 路径未测**:测试实例用 x11 ozone;用户实例 wayland ozone 实测通过(23:41),无需改动。

## 参考

- Chromium 源码:`media/gpu/vaapi/vaapi_wrapper.cc`(NVIDIA skip)、`media/base/media_switches.cc`(`kVaapiOnNvidiaGPUs` 默认禁用)
- 关联档案:本机 Wayland+双显卡问题先例见记忆 vscode-wayland-hybrid-gpu-crash
