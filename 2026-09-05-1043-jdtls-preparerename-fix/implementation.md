# 修复实现与验证

## 变更清单

仅一个新文件:`~/.config/nvim/lua/plugins/java-rename.lua`(内容见下)。

**为什么三条"常规"注入路径全部无效**(排查中实测):

1. `opts.servers.jdtls.capabilities`(LazyVim 标准 per-server 能力覆盖)→ 无效:java extra 用 legacy `require("jdtls").start_or_attach(config)` 自建客户端,capabilities 来自 blink.cmp,不走 `vim.lsp.config` 合并;
2. 直接 `vim.lsp.config("jdtls", { capabilities = ... })` → 同因无效;
3. `opts.jdtls` merge(extra 的 `extend_or_override` 后门)→ 能进 config 但**挡不住服务器侧动态注册**的 prepareProvider。

唯一有效点:注册到达时改写 `registerOptions`。

## java-rename.lua(修复当时版本)

```lua
local orig_register = vim.lsp.handlers["client/registerCapability"]

vim.lsp.handlers["client/registerCapability"] = function(err, res, ctx, config)
  if res and res.registrations then
    for _, r in ipairs(res.registrations) do
      if r.method == "textDocument/rename" and r.registerOptions then
        r.registerOptions.prepareProvider = false
      end
    end
  end
  return orig_register(err, res, ctx, config)
end

return {
  "mfussenegger/nvim-jdtls",
  opts = {
    jdtls = {
      capabilities = {
        textDocument = { rename = { prepareSupport = false } },
      },
    },
  },
}
```

## 验证方法(无头,可复用为通用 LSP 排障骨架)

1. **supports_method 复核**:
   `nvim --headless` 打开目标文件 → 等 attach → `c:supports_method("textDocument/prepareRename")`(修复前 true / 后 false)。
2. **端到端**:`vim.lsp.buf.rename("新名字")`(传名可跳过输入框,headless 可测)→ 检查 **buffer 内容**(不是磁盘!编辑先进内存 buffer):
   ```
   line77 before:     public void upsertFromBoss(BossWarehouseCodeUpdateDto dto) {
   line77 after:      public void upsertFromBossV2(BossWarehouseCodeUpdateDto dto) {
   buffers containing upsertFromBossV2: 2   ← service + controller
   ```
3. 探针要点(踩过的坑):
   - `client:request(method, params, handler)` 第四参**不要传 table**(这版 nvim 会抛错把脚本打死且无输出——必须每步 `pcall` + 逐行 flush 写文件);
   - 验证 rename 落点看 `nvim_buf_get_lines`,落盘与否看 `vim.bo.modified`;
   - 修改实验文件内容后**重算行号坐标**,并带"字符串内位置"作阴性对照。

## 用户侧效果

重启 nvim 后 `Space c r`:输入框预填当前名字 → 回车 → 跨文件引用同步更新(注释/TODO 不更新,LSP 只改代码引用)→ 保存生效。

## 后续

- jdtls 升级后可尝试删除本 shim 验证是否已修复(症状复测:对 `WarehouseCodeChangeCommandService.upsertFromBoss` 发 prepareRename)。
- 若向上游报 issue,可用本档证据链;一个可深挖的点:CoreASTProvider 共享 AST 在大项目上的状态(与 hover 的独立解析路径行为分叉)。
- 排查产物:`~/learning/lazyvim/practice-maven/`(Lombok + spring parent 复刻对照项目,保留作回归 fixture)。
