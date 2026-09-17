# opencode LSP 配置(rust/java/python/typescript)与双配置文件合并

- 日期:2026-09-17 10:49
- 范围:`~/.config/opencode/`(全局配置,非项目仓库,无 PR)
- 状态:已完成并验证(rust/pyright/typescript ✓;jdtls 被上游 bug 挡住,已决定报 upstream 等修复,见附录)

## 背景与目标

1. 确保 rust / java / python / typescript 四种语言的 LSP 在本机可用。
2. opencode 只启用这四个 LSP,其余全部禁用(参考 https://opencode.ai/docs/lsp/ )。
3. 顺带解决:`~/.config/opencode/` 下 `opencode.json` 与 `opencode.jsonc` 并存的问题(合并为单一 `opencode.jsonc`)。

## 结论与发现(核心知识,防遗忘)

### opencode v1.18.31 LSP 语义(从二进制反编译字符串确认)

- `lsp` 省略/falsy → 全部禁用;`lsp: true` → 全部内置启用。
- **`lsp: {}` 对象形式会保留全部内置 LSP**,条目只能逐个 `disabled: true` 或覆盖单个 server;想"只开某几个"必须把其余的逐个禁用。
- 覆盖条目会用 `e.command` 替换内置 spawn 逻辑 → **保留项(rust/jdtls/pyright/typescript)不要写覆盖条目**,否则丢失智能启动逻辑。
- 内置 server 共 38 个,完整 ID 清单(禁用列表由此而来):
  `deno, typescript, vue, eslint, oxlint, biome, gopls, ruby-lsp, ty, pyright, elixir-ls, zls, csharp, razor, fsharp, sourcekit-lsp, rust, clangd, svelte, astro, jdtls, kotlin-ls, yaml-ls, lua-ls, "php intelephense", prisma, dart, ocaml-lsp, bash, terraform, texlab, dockerfile, gleam, clojure-lsp, nixd, tinymist, haskell-language-server, julials`
  (注意 `php intelephense` 带空格;`ty` 是实验性 Python LSP,未开 `experimentalLspTy` 时自动移除)
- 四个保留项的内置启动要求:
  - **rust**:PATH 里有 `rust-analyzer`。
  - **jdtls**:Java ≥21 即可,**无需手装 jdtls 命令**——opencode 自动从 eclipse.org 下载 jdt.ls 到自己 的 bin 目录并拼 JVM 参数。
  - **pyright**:PATH 里有 `pyright-langserver`(npm 全局装 pyright 即得;内置逻辑还会探测 venv)。
  - **typescript**:PATH 里有 `typescript-language-server` + **项目内**有 `typescript` 依赖(解析 `typescript/lib/tsserver.js`,逐项目条件)。

### 双配置文件并存行为(从二进制加载逻辑 + `opencode mcp list` 实证)

- opencode 接受 `opencode.json` 与 `opencode.jsonc` 两种文件名;**两者并存时都加载并深度合并**,顺序 json → jsonc,键冲突时 jsonc 覆盖 json(逐键覆盖,非整体替换)。
- 当时两文件重复定义了 4 个 MCP server 且 key/URL 不同(bigmodel.cn+ZHIPU 旧 key vs api.z.ai+ZAI 新 key),json 那份已被静默覆盖成死配置。
- `.bak` / `.bak-*` 文件不被读取,无害。

## 实施内容

1. `npm install -g pyright typescript typescript-language-server`(经 npmmirror 镜像一次 性 flag,未改全局 registry)。装后 `pyright-langserver`、`typescript-language-server` 在 PATH(nvm node v24.21.0 bin)。
2. 本机已有:rust-analyzer(~/.cargo/bin,rustup 管理)、Java 21(Temurin 21.0.12)。
3. `opencode.jsonc` 增加 `lsp` 段:禁用其余 34 个内置,保留 rust/jdtls/pyright/typescript(无覆盖条目)。
4. 合并配置:`opencode.json` 独有的 `autoupdate`/`permission`/`compaction` 并入 `opencode.jsonc`(mcp 保留 jsonc 的 z.ai 版本即实际生效版;空 `provider: {}` 跳过),随后删除 `opencode.json`。

## 验证

- JSONC 解析正常;禁用键与内置清单比对无拼写错误,保留项恰为 4 个。
- `opencode mcp list`:4 个 server URL 均为 api.z.ai,与合并前一致。
- `opencode models`:配置加载无报错(schema 校验通过)。
- 重启后实测(在 cwd 内建带类型错误的测试文件 + read 触发 `LSP.touchFile`,查 `~/.local/share/opencode/log/opencode.log` 与 `ps`):
  - 日志确认 `enabled LSP servers serverIds="typescript, rust, pyright, jdtls"`,其余 34 个逐一 `is disabled`。
  - rust-analyzer ✓、pyright-langserver ✓ 进程拉起;test.go 反例未拉起 gopls ✓。
  - typescript-language-server ✓ 在干净 `opencode run` 实例中拉起(opencode 还会自动装一份到 `~/.cache/opencode/packages/`,不依赖 PATH)。
  - jdtls ✗:上游 bug,见附录。

### 验证过程中发现的行为(防再踩)

- **工作目录外的文件不触发 LSP**:在 `/tmp` 下 touch 无反应;须在实例 cwd(项目)内。
- **typescript 的 root 判定认锁文件**(package-lock.json / bun.lock / pnpm-lock.yaml / yarn.lock,向上查到实例目录为止),仅 package.json/tsconfig.json 不够;且 `tsserver.js` 必须从**实例 cwd** 可解析 → 已在 `~/.config/opencode/package.json` 加 `typescript@^5.9.3`(该目录 node_modules 由 opencode 后台同步管理,`npm i --no-save` 会被清掉,必须写进 package.json)。
- **spawn 失败会记入会话级 sticky `broken` 集合,同 root+id 不再重试**——tsserver 就位后也须重启/新实例才恢复。TUI 当前会话在 typescript 修好前已标 broken,需再重启一次 TUI。

## 遗留与注意

- **jdtls 暂不可用**(上游 bug,决定报 upstream 等修复,素材见附录);修复前 java 诊断走 `./mvnw test` 等 CLI 即可。
- typescript LSP 在无本地 `typescript` 依赖的项目里不会启动(内置行为,逐项目)。
- 遗留旧备份 `opencode.json.bak`、`opencode.json.bak-cbm-20260809-233159`,不被读取,可随手清理。
- opencode 升级后若新增内置 LSP ID,需在 `lsp` 禁用清单里补一行才会保持"只开四个"。
- 配置不热加载,改动后需重启 opencode。

## 附录:jdtls 上游 bug(可直接作为 issue 素材)

- **组件**:opencode v1.18.31(亦应影响更早版本),`packages/core` 内置 jdtls LSP server 的 Java 版本检查。
- **现象**:满足文档要求(Java SDK 21+)但 jdtls 从不启动,且无任何日志——静默失败。
- **根因**:spawn 前执行 `java -version` 并用正则 `/"(\d+)\.\d+\.\d+"/` 解析 stderr 中的版本号,仅匹配三段式;Eclipse Temurin 的 CPU 版本号为四段式(如 `openjdk version "21.0.12.1" 2026-08-18 LTS`)→ 不匹配 → `V==null` → 直接 return,server 不启动。
- **复现**:
  1. `sdk install java 21.0.12.1-tem`(或任何四段式版本 JDK)并设为默认。
  2. 配置 `"lsp": {}` 启用 LSP,打开任意 `.java` 文件。
  3. 期望:jdtls 启动;实际:无进程、无日志(对比三段式 JDK 如 `21.0.5-tem` 可正常启动)。
- **建议修复**:正则改为 `/"(\d+)\.\d+\.\d+(?:\.\d+)?"/`(或用非捕获的可选第四段)。
- **本机临时绕过方案(未采用)**:手动下载 eclipse jdt.ls,在 `lsp.jdtls` 写显式 `command` 覆盖(保留内置 root 探测);或换默认 JDK 为三段式版本。
