# Design: Rime + 雾凇拼音 小鹤双拼 集成

**Date:** 2026-07-02  
**Status:** Approved

## 背景

用户已安装 fcitx5（含 fcitx5-rime、librime 1.16.1），且 `~/.local/share/fcitx5/rime/` 已是雾凇拼音的 git clone（remote: `https://github.com/iDvel/rime-ice.git`）。现有配置：

- `default.custom.yaml`：候选词9个，schema 锁定为 `double_pinyin_flypy`（小鹤双拼）
- `double_pinyin_flypy.custom.yaml`：英文标点为默认，完整模糊音规则

**核心问题**：`fcitx5-rime` 从未被加入 fcitx5 的 profile，导致 Rime 一直没有启用。

**目标**：
1. 更新雾凇拼音到最新版
2. 在 fcitx5 中激活 Rime，作为主力输入法
3. 保留 fcitx5 内建双拼和全拼
4. 切换顺序：Rime 小鹤双拼 → fcitx5 shuangpin → fcitx5 pinyin

## 现有配置快照

```
~/.config/fcitx5/profile:
  DefaultIM=shuangpin
  Items: keyboard-us, shuangpin, pinyin

~/.local/share/fcitx5/rime/
  ├── default.custom.yaml        # page_size: 9, schema: double_pinyin_flypy
  ├── double_pinyin_flypy.custom.yaml  # 英文标点 + 模糊音
  ├── double_pinyin_flypy.schema.yaml  # 小鹤双拼主方案（上游）
  ├── rime_ice.dict.yaml         # 词库入口
  ├── cn_dicts/                  # 词库文件
  ├── rime_ice.userdb/           # 用户词库（半年积累，需保留）
  └── .git/                      # remote: iDvel/rime-ice
```

## 实施方案

### Phase 1：更新雾凇拼音

1. 检查 `.gitignore`，确认 `*.custom.yaml` 不被 pull 覆盖
2. `git pull origin master` 拉取最新版
3. 验证 `double_pinyin_flypy.custom.yaml` 的 patch 键路径（`speller/algebra`、`switches/1/reset`）在新版 schema 中仍有效
4. 如有 patch 路径失效，按新版 schema 调整

### Phase 2：激活 Rime 到 fcitx5

编辑 `~/.config/fcitx5/profile`：

```ini
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=rime
Layout=

[Groups/0/Items/2]
Name=shuangpin
Layout=

[Groups/0/Items/3]
Name=pinyin
Layout=

[GroupOrder]
0=Default
```

### Phase 3：部署 Rime + 重启 fcitx5

1. 触发 Rime 重新部署（重建 schema 索引和词库缓存）
2. 安全重启 fcitx5（使用 `qdbus6` 切换 VirtualKeyboard，不用 `fcitx5 -r`）
3. 验证：
   - `Super+Space` 切换输入法，确认 Rime 排在首位
   - 打入小鹤双拼按键，确认候选词正常（如 `ui` → 回）
   - `Shift+Space` 或切换顺序正常到达 shuangpin / pinyin

## 关键约束

- **不删除 `rime_ice.userdb/`**：半年的用户词库，直接 `git pull` 不会动它
- **不用 `fcitx5 -r`**：在 KDE Plasma 6 / Wayland 下会杀掉 VirtualKeyboard 启动链；改用 qdbus6 toggle
- **custom 文件不被 git pull 覆盖**：雾凇拼音上游在 `.gitignore` 中排除 `*.custom.yaml`，本地自定义安全
