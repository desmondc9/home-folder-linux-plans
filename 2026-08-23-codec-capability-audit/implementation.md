# implementation — 编解码能力审计与补齐

对应 [design.md](./design.md)。

## 任务清单

- [x] 浏览器全矩阵探测(隔离实例 + 生产 flags:CDP canPlayType/MediaCapabilities/MediaRecorder/WebRTC)
- [x] OS 层审计(vainfo/ffmpeg enc+dec/gst 插件集/媒体库/播放器/VDPAU)
- [x] 安装 gstreamer1.0-plugins-bad + gstreamer1.0-vaapi
- [x] 安装 gstreamer1.0-tools(gst-inspect/gst-launch)
- [x] 定位 gst-vaapi 0 元素根因(驱动白名单,GST_DEBUG=6 日志)
- [x] `GST_VAAPI_ALL_DRIVERS=1` 验证 + E2E 硬解(裸流 + baseline/high mp4)
- [x] 持久化 ~/.config/environment.d/70-gst-vaapi.conf
- [x] 归档提交 ~/plans
- [x] Chrome Beta 实测对齐:无 flags 时 HEVC 全无、H.264/AV1 仅软解;带 flags 后与 Stable 一致(NVDEC 硬解三件套)
- [x] Beta 用户级 .desktop 追加同款 flags + ksycoca 重建

## 变更文件表

| 文件 | 变更 |
|------|------|
| `~/.config/environment.d/70-gst-vaapi.conf` | 新建,`GST_VAAPI_ALL_DRIVERS=1` |
| 系统包 | 新增 gstreamer1.0-plugins-bad、gstreamer1.0-vaapi、gstreamer1.0-tools |

## 验证方式

- [x] 插件库 ls 确认(libgstlibav/libgstopenh264/libgstsvtav1/libgstvaapi/libgstvideoparsersbad)
- [x] gst-inspect(带 env)元素注册完整
- [x] 三条 E2E 解码管线全过(裸流/baseline mp4/high mp4)
- [x] 软解对照实验(排除测试文件问题)
- [ ] 下次登录全局生效(待确认)

## 备注(可迁移经验)

- **gst-vaapi 驱动白名单**:元素注册为 0 但插件加载正常时,查 GST_DEBUG=6 日志里的 `gst_vaapi_driver_is_whitelisted`;非主流 VA 驱动(NVDEC 等)需要 `GST_VAAPI_ALL_DRIVERS=1`。
- **GStreamer registry 缓存**会吞掉环境变量变化:改 env/换驱动后先 `rm ~/.cache/gstreamer-1.0/registry.x86_64.bin` 再验证,否则看的是旧缓存(插件 mtime 不变不重扫)。
- 排查 GStreamer 管线用 `gst-launch-1.0 -v`,not-linked 要看 "Delayed linking failed" 的完整上下文,别急着归因于首个报错元素。
- Chromium 的 VP9 硬解在 NVIDIA VAAPI 下不可用是已知限制(MediaCapabilities 报 false),AV1 硬解是替代路径,无需折腾。
