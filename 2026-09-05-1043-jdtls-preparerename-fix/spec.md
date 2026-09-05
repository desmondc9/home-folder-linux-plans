# jdtls prepareRename 全项目失效 — 排查与修复(prepareProvider 拦截)

- **日期**:2026-09-05(约 09:00–10:45)
- **性质**:本机工具链 bug 调查 + 修复(用户 nvim 配置新增一个 workaround 插件文件,无业务代码变更)
- **状态**:已修复并端到端验证;根因止步于"jdtls 1.60 服务器内部 OccurrencesFinder 通路在该项目失灵",未继续上游定位

## 症状

`~/Repos/ups-hms-backend`(Spring Boot 3.4.3 / Maven / Lombok / jdtls 1.60 via LazyVim java extra)中,任意 Java 文件、任意符号(类名/方法/局部变量)上执行 `Space c r`(vim.lsp.buf.rename)报:

```
Error on prepareRename: Renaming this element is not supported.
```

同一台机器上 `~/learning/lazyvim/practice/`(invisible project)与 `practice-maven/`(Maven,含 Lombok + spring parent 复刻)rename 全部正常。

## 关键证据链(按排查顺序)

| # | 嫌疑 | 实验 | 结论 |
|---|---|---|---|
| 1 | 光标位置不在标识符上 | 用户自查 + 无头探针三种位置(类/方法/局部变量) | ❌ 全部同样报错 |
| 2 | jdtls 未挂载/类路径坏 | hover 完整解析签名、documentSymbol 完整、"0 problems" 验证 | ❌ Java 模型健康 |
| 3 | 工作区缓存脏/导入未完成 | `:JdtWipeDataAndRestart` + 我方 rm -rf 后全新导入、7 分钟长窗每 10s 轮询 prepareRename | ❌ 导入完成瞬间(排队响应一次性涌回)依然报错 |
| 4 | Maven 导入失败/元数据坏 | Eclipse `.classpath`/`.project` 与健康项目逐字节同构;项目注册表路径正确 | ❌ |
| 5 | **Lombok**(一度定罪) | practice-maven 加 @Slf4j "复现" → **复现是假的**:加注解后方法行号偏移,探针坐标打进了字符串(任何项目该位置都报同错);修正坐标后 Lombok + spring parent 复刻项目完全正常 | ❌ **平反;教训:改文件内容后必须重算探针坐标,并设"字符串内位置"阴性对照** |
| 6 | 编码/只读/文件权限 | 前 76 行纯 ASCII、文件 rw、目录可写、无 immutable 属性 | ❌ |
| 7 | settings.xml 内网镜像不可达 | aliyun 公网镜像 | ❌ |
| 8 | 完整 rename 是否可用 | 直接发 `textDocument/rename`(跳过 prepare)→ **返回精确的 2 文件 edits(service 声明 + controller 调用点)** | ✅ 唯一坏的是 prepare 一步 |

### 决定性机制分析(nvim 0.12 源码 + jdtls 字节码)

- nvim 的 `vim.lsp.buf.rename`:`supports_method('textDocument/prepareRename')` 为真则先发 prepareRename。
- jdtls 的 rename 能力是**动态注册**的(`client/registerCapability`,`registerOptions = { prepareProvider = true }`),所以 `server_capabilities.rename_provider == nil` 但 supports_method 仍返回 true —— 客户端侧关 prepareSupport 声明拦不住它。
- jdtls `PrepareRenameHandler` 字节码:走 `CoreASTProvider.getAST` → `OccurrencesFinder.initialize/getOccurrences`,找不到 occurrence 即报 "Renaming this element is not supported";hover/definition/documentSymbol/完整 rename 走其他通路,故全部正常。
- 为什么 OccurrencesFinder 恰好在此项目失灵:**未定位**(小项目复刻一切已知变量均正常)。差异只剩项目规模/依赖树,疑为 jdtls 1.60 大项目下的 AST 共享缓存问题,留待上游。

## 修复方案

拦截 `client/registerCapability`,把 jdtls 注册的 `textDocument/rename` 的 `prepareProvider` 改为 false → nvim 跳过 prepareRename,直接 `textDocument/rename`(预填 = 光标下单词,Java 标识符场景下与 prepare range 等价)。rename 能力本身不受影响。

实现与验证见 [implementation.md](implementation.md)。
