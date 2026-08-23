# Chrome/Edge/OS 音视频编解码能力审计与补齐

日期: 2026-08-23
状态: 已完成——浏览器侧能力完整;OS 侧补齐 GStreamer bad+vaapi 并解锁 NVIDIA VAAPI(白名单),E2E 硬解验证通过

## 背景

在昨日 HEVC 修复([browser-hevc-bilibili](../2026-08-22-browser-hevc-bilibili/))基础上,全面审计 Chrome/Edge 与系统的音视频编解码能力,按最佳实践补齐影响性能的缺口。

## 审计结果

### 浏览器(隔离实例 + 生产同款 flags 实测)

| 能力 | 结果 |
|---|---|
| 视频解码 H.264/HEVC/AV1/VP8/VP9 | ✅ canPlayType 全 "probably" |
| 音频解码 AAC/Opus/FLAC/MP3/Vorbis | ✅ 全 "probably" |
| 硬解 | ✅ H.264/HEVC/**AV1** 均 `powerEfficient: true`(NVDEC) |
| VP9 硬解 | ⚠️ Chromium-on-NVIDIA 已知限制(驱动缺 picture processor),无解;AV1 硬解覆盖场景 |
| 录制/WebRTC | ✅ MediaRecorder(webm vp8/vp9/av01/opus + mp4 h264)、WebRTC 全套 |

### OS 层

| 组件 | 审计前 | 结论 |
|---|---|---|
| ffmpeg | 解码全家桶 + NVENC(h264/hevc/av1)/libx264/libx265/SVT-AV1/librav1e,libx265 链接正常 | ✅ 无缺口 |
| VAAPI | 解码全 profile、无编码入口 | ✅ 正常(NVIDIA 编码走 NVENC) |
| GStreamer | **缺 plugins-bad + vaapi** | ❌ → 已修复 |
| gst-vaapi × NVIDIA | 插件加载但 **0 元素** | ❌ → 已修复(驱动白名单) |
| 播放器 | Haruna(mpv)/VLC 借助昨日驱动自动获得硬解 | ✅ |
| Firefox | snap 版,无法加载系统级 nvidia-vaapi-driver → 无硬解 | ⚠️ 记录在案,不动(换 deb 是大事) |

## 根因与修复(gst-vaapi 0 元素)

日志定位:`gstvaapipluginutil.c:970 gst_vaapi_driver_is_whitelisted: Unsupported VA driver: VA-API NVDEC driver [direct backend]. Export envir...` —— gst-vaapi 内置**驱动白名单**,NVDEC 社区驱动不在名单,插件注册 0 元素(libva 本身初始化是成功的)。

修复:`GST_VAAPI_ALL_DRIVERS=1` 跳过白名单。持久化到 `~/.config/environment.d/70-gst-vaapi.conf`(Plasma 6 systemd 会话,下次登录全局生效)。

## 验收标准

- [x] `gst-inspect-1.0 vaapi`(带 env)注册 vaapiav1dec/vaapih264dec/vaapih265dec/vaapidecodebin 等
- [x] E2E:videotestsrc→x264enc→h264parse→vaapih264dec→fakesink 解码成功
- [x] E2E:baseline 与 high profile mp4 经 qtdemux→vaapih264dec 均解码成功
- [x] `~/.config/environment.d/70-gst-vaapi.conf` 已写入
- [ ] 下次登录后 GStreamer 应用无需手工 env 即可硬解(待确认)

## 补充(同日):Chrome Beta 对齐

用户追问 Beta(153.0.8010.5)是否与 Stable 同等能力。实测:

- **无 flags(Beta 原状)**:HEVC **完全不支持**(canPlayType 空),H.264/AV1 仅软解(powerEfficient: false);
- **带同款三特性 flags**:与 Stable 完全对齐——H.264/HEVC/AV1 全部 "probably" + `powerEfficient: true`(NVDEC 硬解)。

修复:复制系统 `google-chrome-beta.desktop` 到用户目录,3 条 Exec 追加同款 flags + `kbuildsycoca6 --noincremental` 重建缓存。验收标准追加:用户从开始菜单重启 Beta 后控制台 `video/mp4; codecs=hev1.1.6.L120.90` → "probably"。

## 补充(同日):任务栏启动为何不带 flags

用户实测:开始菜单启动 chrome/beta → hevc: probably;任务栏固定图标启动 → 无 HEVC。

根因:任务栏固定图标(appletsrc `launchers=applications:com.google.Chrome.desktop,...`)引用的是 Chrome 新版安装的**反向域名 ID 桌面文件**(`com.google.Chrome.desktop`/`com.google.Chrome.beta.desktop`/`com.microsoft.Edge.desktop`),与菜单用的 `google-chrome.desktop` 是**两套不同的文件**。前者只存在于系统目录且零 flags。

修复:三个反向域名文件各复制一份到用户目录,9 条 Exec 全部追加同款三特性 flags + ksycoca 重建。

注意:用户目录现在同时存在 `google-chrome.desktop` 与 `com.google.Chrome.desktop`,KDE 菜单若出现重复的 Chrome 条目,可用 NoDisplay=true 隐藏其一。

## 风险与缓解

- **registry 抖动**:白名单刚放开时曾出现一次 qtdemux not-linked(registry 缓存旧特征),之后 2/2 稳定通过;若复发 `rm ~/.cache/gstreamer-1.0/registry.x86_64.bin`。
- **GST_VAAPI_ALL_DRIVERS=1 全局放开白名单**:理论上允许了"未验证"驱动,本机仅 NVDEC 一个 VA 驱动,风险可控。
- **VP9 软解**:YouTube 等平台在 AV1 可用时优先 AV1,VP9 软解兜底,性能影响小,不做特殊处理。

## 参考

- 昨日档案 [browser-hevc-bilibili](../2026-08-22-browser-hevc-bilibili/)(flags/驱动安装)
- gst-vaapi 源码 gstvaapipluginutil.c(白名单逻辑)
