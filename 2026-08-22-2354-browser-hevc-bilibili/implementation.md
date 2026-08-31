# implementation — Chrome/Edge HEVC 修复

对应 [design.md](./design.md)。

## 任务清单

- [x] 诊断:四层根因定位(见 design.md 证据链)
- [x] 安装 `nvidia-vaapi-driver`(vainfo 验证 HEVC profiles 齐备)
- [x] 特性三件套在隔离测试实例验证通过(canPlayType "probably" + decodingInfo 全 true)
- [x] 固化 flags 到用户级 desktop 文件(Chrome 3 条 Exec 追加;Edge 复制到用户目录后 3 条追加)
- [x] `kbuildsycoca6 --noincremental` 重建 KDE 缓存
- [x] 用户真实 Chrome 验证 `hevc: probably`(23:41)
- [x] B 站直播最终验收(23:54 用户确认:Chrome/Edge 提示消失、播放正常)
- [x] 归档提交 ~/plans

## 变更文件表

| 文件 | 变更 |
|------|------|
| `~/.local/share/applications/google-chrome.desktop` | 3 条 Exec 追加 `--enable-features=VaapiVideoDecoder,VaapiOnNvidiaGPUs,PlatformHEVCDecoderSupport` |
| `~/.local/share/applications/microsoft-edge.desktop` | 新建(复制自 /usr/share/applications/),3 条 Exec 同样追加 |
| 系统包 | 新增 `nvidia-vaapi-driver` 0.0.14(universe) |

## 验证方式

- [x] `vainfo`:NVDEC 驱动 + HEVCMain/Main10/Main12/Main444
- [x] 隔离实例:canPlayType + MediaCapabilities(CDP 探针)
- [x] 真实 Chrome:`chrome://version` 可见 flags;控制台 `video/mp4; codecs=hev1.1.6.L120.90` → "probably"
- [x] B 站直播强刷后无提示、播放正常(23:54)
- [x] Edge 同样验证(23:54)

## 备注(可迁移经验)

- **Chrome/Edge 在 Linux 上查 HEVC 支持必须用 `video/mp4; codecs=hev1...` 格式**——裸 `video/hevc` 恒为空,会误判"无编解码器"。
- Chromium 的 NVIDIA VAAPI 跳过是**特性开关**控制(`VaapiOnNvidiaGPUs`),不是硬编码禁止——装社区驱动 + 开开关即可,不必编译或换浏览器。
- **Playwright MCP 自带 Chromium 不带专有编解码器**,做浏览器能力探针要用 `channel:'chrome'` 或 CDP 拉起真实 Chrome + 独立 profile。
- KDE 启动器修改 .desktop 后若命令行零参数,先 `kbuildsycoca6 --noincremental` 再重启;cgroup 名 `app-<appid>-<pid>.scope` 可反查启动入口(Plasma 6 用 systemd scope 包应用)。
- 测试实例与用户实例的 ozone 平台可能不同(x11 vs wayland),最终验收以用户真实浏览器为准。
