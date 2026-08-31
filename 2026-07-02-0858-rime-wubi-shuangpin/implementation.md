# Implementation: Rime + 雾凇拼音 小鹤双拼 集成

**Date:** 2026-07-02  
**Status:** ✅ 完成

## 任务清单

- [x] 探索当前 fcitx5 配置
- [x] 确认方案（方案 A：git pull + 激活 Rime）
- [x] Phase 1：更新雾凇拼音
- [x] Phase 2：激活 Rime 到 fcitx5 profile
- [x] Phase 3：部署 Rime + 重启 fcitx5
- [x] 验证小鹤双拼可正常使用

---

## 初始状态发现

检查后发现用户系统已有大量基础：

| 项目 | 状态 |
|---|---|
| `fcitx5-rime` 包 | ✅ 已安装 (v5.1.13) |
| `librime` | ✅ 已安装 (v1.16.1) |
| 雾凇拼音 git clone | ✅ 已在 `~/.local/share/fcitx5/rime/`（停在 2026-01-08）|
| `double_pinyin_flypy.custom.yaml` | ✅ 已有：英文标点默认 + 完整模糊音规则 |
| **Rime 在 fcitx5 中激活** | ❌ profile 中无 `rime` 条目 |

---

## Phase 1：更新雾凇拼音

```bash
git -C ~/.local/share/fcitx5/rime pull origin main
```

- 更新范围：124 个文件，词库（`cn_dicts/`）、schema、lua 脚本、英文词典全部更新
- 版本：`5100347` → `6810e89`
- `.gitignore` 确认 `*.custom.yaml` 不被覆盖 ✅
- 验证 `double_pinyin_flypy.custom.yaml` 补丁路径：
  - `switches/1`（`ascii_punct`）：位置未变 ✅
  - `speller/algebra`：路径未变，结构未变 ✅

## Phase 2：激活 Rime 到 fcitx5

停止 fcitx5（防止 AutoSave 覆盖编辑）：
```bash
qdbus6 org.kde.KWin /VirtualKeyboard org.kde.kwin.VirtualKeyboard.enabled false
```

编辑 `~/.config/fcitx5/profile`：
- `DefaultIM`: `shuangpin` → `rime`
- 新增 `Items/1 = rime`，原 shuangpin/pinyin 顺移为 Items/2、Items/3
- 最终顺序：`keyboard-us → rime → shuangpin → pinyin`

## Phase 3：部署 Rime + 重启 fcitx5

```bash
qdbus6 org.kde.KWin /VirtualKeyboard org.kde.kwin.VirtualKeyboard.enabled true
```

- 进程链验证：`fcitx5-wayland-launcher --reopen` → `/usr/bin/fcitx5` ✅
- Rime 自动部署，关键产物（09:02 时间戳）：
  - `double_pinyin_flypy.prism.bin` ✅
  - `rime_ice.table.bin`（新词库）✅
  - `rime_ice.reverse.bin` ✅

---

## 最终配置

```
~/.config/fcitx5/profile
  DefaultIM=rime
  Items: keyboard-us, rime, shuangpin, pinyin

~/.local/share/fcitx5/rime/
  double_pinyin_flypy.custom.yaml  # 英文标点 + 模糊音（保留不变）
  default.custom.yaml              # page_size:9, schema:double_pinyin_flypy（保留不变）
  rime_ice.userdb/                 # 用户词库（保留不变）
```

## 验证结果

- `Super+Space` 切换到 Rime 小鹤双拼 ✅（用户确认可正常使用）
- fcitx5 内建 shuangpin / pinyin 保留 ✅
