# Windows 11 ComfyUI Desktop + NoctQ V4 (Qwen-Image-2.1) 本地部署与 img2img 工作流

- 环境: Windows 11 宿主机(WSL2 mirrored networking,WSL 可直接访问 `/mnt/c`、`/mnt/d` 与宿主 localhost);RTX 4060 Laptop GPU 8G 显存;64G 内存;ComfyUI Desktop 工作目录 `D:\Comfy-Desktop`。
- 日期: 2026-11-14
- 状态: 部署完成,t2i 与 img2img(edit)均端到端实测出图成功;原版 Qwen Image 2.1 int8 亦已就位。

## 背景与目标

在 ComfyUI Desktop 本地实例上部署 HF `Noctaluna/Noct-Q-Uncensored-Qwen-Image-2.1` 的 `NoctQ_V4_int8_convrot` 模型及其 workflow(用户已自行下载 checkpoint 与 workflow json 到 `D:\Desmond\Downloads\`);随后基于 t2i workflow 派生一个 img2img 编辑 workflow;最后补充下载原版 `qwen_image_2.1_int8_convrot` 供对比使用。

## 最终交付

### 模型文件(全部字节级 + sha256 双重校验通过)

| 文件 | 位置 (`D:\Comfy-Desktop\ComfyUI-Shared\models\`) | 大小 | sha256(前 8 位) |
|---|---|---|---|
| `NoctQ_V4_int8_convrot.safetensors` | `diffusion_models/` | 7,256,784,368 B (6.8GiB) | `4d92d553` |
| `qwen_image_2.1_int8_convrot.safetensors` | `diffusion_models/` | 7,256,783,064 B (6.8GiB) | `cb74113c` |
| `qwen3vl_8b_int8_convrot.safetensors` | `text_encoders/` | 9,350,798,360 B (8.7GiB) | `8bfd0f6e` |
| `qwen_image_2.1_vae_bf16.safetensors` | `vae/` | 675,509,688 B (0.63GiB) | `bb21f747` |

TE 与 VAE 两个模型(NoctQ / 原版)共用,无需重复下载。

### Workflow(`...\ComfyUI-Installs\ComfyUI\ComfyUI\user\default\workflows\`)

- `NoctQ_V4_workflow.json` — 用户拖入的原版 t2i(与 HF 原件仅序列化元数据差异,无需修改)
- `NoctQ_V4_edit_workflow.json` — 本次新建的 img2img 编辑版

## 关键事实与坑

### 1. ComfyUI Desktop 目录布局与模型路径真相源

- `D:\Comfy-Desktop` 下三目录:`ComfyUI-Shared`(models/input/output 共享数据)、`ComfyUI-Installs`(ComfyUI 代码 + standalone-env Python 环境)、`ComfyUI-Cache`(安装包缓存)。
- **models 目录映射的真相源是** `C:\Users\Desmond\AppData\Roaming\Comfy Desktop\instance-model-paths\inst-*.yaml`(由 `--extra-model-paths-config` 启动参数引入),`base_path` 指向 `D:\Comfy-Desktop\ComfyUI-Shared\models`。排布模型文件前先读它,不要猜。
- `ComfyUI-Installs\ComfyUI\manifest.json` 记录的版本(v0.42.1)可能**落后于实际运行版本**(自动更新,实测 `/system_stats` 报 0.45.3)。
- Desktop 运行实例的 API 在 `http://127.0.0.1:8188`(WSL mirrored 模式下 WSL 可直连),`/object_info/<Node>` 可验证模型是否被识别,`/prompt` 可无头提交生成,`/queue`+`/history` 可监控;`POST /interrupt` 可取消运行中的任务。

### 2. NoctQ 与原版的文件对应关系

- `NoctQ_V4_int8_convrot` 的全精度原版是 **`NoctQ_V4_bf16.safetensors`(14.2GB),只在 Civitai(model 2958896),HF 仓库只放 int8**。
- 原版 `Comfy-Org/Qwen-Image-2.1` 的 `diffusion_models/` 只有 bf16 / int8_convrot / turbo_bf16 / turbo_int8_convrot 四个文件,**没有 int4**;int4 只有 NoctQ 的 `int4_mixed`(Civitai)或第三方 GGUF。
- 作者口径(Civitai 页):8–12G 显存用 int8 convrot,"几乎与 bf16 像素级一致";bf16/fp16 是给合并与训练用的。8G 卡上 int8 就是最优解。
- 参数配方差异:**原版官方路径 cfg 1、无负面提示词**(有内容安全过滤,NSFW 会被拦截);**NoctQ 作者配方 cfg 3 + workflow 自带负面提示词**(cfg 1 快一倍但负面词失效)。

### 3. HuggingFace 下载与校验方法

- 下载直链:`https://huggingface.co/<repo>/resolve/main/<path>`,WSL 里 curl 直连即可(宿主 sing-box TUN 已分流,无需显式代理)。
- **校验捷径:对该 URL 发 HEAD 请求,响应头 `x-linked-etag` 就是 LFS 文件的 sha256,`x-linked-size` 是精确字节数**——不用调 API 也行;API 途径是 `/api/models/<repo>/tree/main/<dir>`。
- 教训:肉眼比对 64 位哈希曾看错一位(多读一个字符),**哈希比对必须程序化做**。
- 下载流程:先写 `.part` 再 `mv` 改名,防止 ComfyUI 扫到半成品文件。

### 4. TextEncodeQwenImage21 原生编辑机制(Qwen Image 2.1)

- 编辑路径 = `image_1`(编辑对象图,可选 image_2..image_16 多参考,提示词用 `<image1>` 指代)+ `vae` 接入 TextEncodeQwenImage21;**该节点的第 3 个输出 `latent`(按 image_1 尺寸生成的空 latent)直接喂 KSampler 的 latent_image**,不用 EmptyLatentImage。
- `resolution=0` = 保持输入图原尺寸(32 倍数取整);设 1024/1536/2048 = 把参考图缩到该像素预算。
- 官方模板参数:25 步、euler/simple、cfg 1、denoise 1.0。
- **API 格式坑(实测踩中)**:autogrow 输入(`COMFY_AUTOGROW_V3`)在 UI workflow 里叫 `images.image_1`,经 `/prompt` API 提交时键名也**必须带点号写成 `images.image_1`**;写成 `image_1` 能通过校验但执行时报 `execute() got an unexpected keyword argument 'image_1'. Did you mean 'images'?`。
- 官方模板还有一个可选 Prompt Enhancer(`qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors`,8.8GB,默认关闭),本次未引入。

### 5. 8G 显存的分辨率坑(img2img"卡在 33%"事件)

- 现象:img2img 进度条停在 33%,GPU 100%、显存占满,10 分钟不出图。
- 根因:输入照片 2000×2982(6MP)且 `resolution=0` → 按原尺寸采样,日志显示 **KVCacheModel 需要 23GB**(对照:1024×1536 仅 90MB),在 8G 显存上靠 PCIe 反复倒腾,每步分钟级——不是卡死,是慢到像卡死。
- 解法:TextEncodeQwenImage21 的 `resolution` 改 1024(或 1536;2048 是模型原生上限但 8G 卡很慢),或预先缩小照片。改 1024 后单张 ~2.5 分钟。
- 判断技巧:进度条有百分比 = KSampler 在走;配合 `/queue` 看提交参数、`user/comfyui.log` 看 KVCacheModel Staged 大小、`nvidia-smi` 看 GPU 是否真在算。

### 6. 性能实测(4060 Laptop 8G + 64G RAM,int8 convrot)

| 场景 | 参数 | 耗时 |
|---|---|---|
| t2i | 25 步 / cfg 3 / 1024×1536 | 2m24s |
| img2img edit | 25 步 / cfg 1 / 1024×1536 输入 | 2m23s |

64G 内存对 offload 极有利;多次取消运行后内存可能滞留占用,异常时重启 Desktop 释放。

## 验证记录

- t2i:按 workflow 原参数 API 提交,success,产出 `NoctQ_V4_test_00001_.png`。
- img2img:示例图(湖边日出)+ "白衬衫→红毛衣"指令,第一次因 API 键名踩坑失败,改 `images.image_1` 后 success,产出 `NoctQ_V4_edit_test_00001_.png`。
- 示例输入图存于 `ComfyUI-Shared\input\noctq_edit_sample.png`;img2img"卡 33%"事件已定位并解决(见上)。

## 测试计划说明

纯本机环境配置/运维任务,无代码仓库改动,不适用单元测试计划;验证以 API 实跑出图 + 全文件哈希校验为准(均已通过)。

## 参考

- HF 模型页: https://huggingface.co/Noctaluna/Noct-Q-Uncensored-Qwen-Image-2.1 (含 `?not-for-all-audiences=true` 门禁,API/HEAD 不受影响)
- TE/VAE/原版 diffusion: https://huggingface.co/Comfy-Org/Qwen-Image-2.1
- Civitai 全格式(含 bf16/fp16/int4): https://civitai.com/models/2958896 (网页 403 需登录,`/api/v1/models/2958896` 可公开访问)
- 官方 2.1 edit 模板(本地): `ComfyUI-Installs\ComfyUI\standalone-env\Lib\site-packages\comfyui_workflow_templates_json\templates\image_qwen_image_2_1_image_edit.json`
