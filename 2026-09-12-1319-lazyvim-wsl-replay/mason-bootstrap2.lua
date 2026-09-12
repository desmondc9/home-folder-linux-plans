-- headless 引导第 2 版(修正两个母本未覆盖的坑):
-- 1) mason.nvim / nvim-lspconfig 均为 cmd/keys 懒加载,headless 下 config 不跑 →
--    ensure_installed 从未入队。用 lazy.load 强制加载,让 LazyVim 的安装链执行。
-- 2) 稳定判据必须要求 installing==0(第 1 版只看状态稳定,卡死的安装也算“稳定”)。
local mr = require("mason-registry")
mr:on("package:install:failed", function(pkg)
  print("FAILED " .. pkg.name)
end)

-- 强制加载懒加载 specs,触发 mason/mason-lspconfig 的 ensure_installed
pcall(function()
  require("lazy").load({ plugins = { "nvim-lspconfig", "mason.nvim" } })
end)

-- 显式补装 debug 适配器 + tree-sitter-cli(幂等)
mr.refresh(function()
  for _, name in ipairs({ "codelldb", "debugpy", "delve", "java-debug-adapter", "java-test", "tree-sitter-cli" }) do
    local ok, p = pcall(mr.get_package, name)
    if ok and p and not p:is_installed() then
      print("BOOT " .. name)
      p:install()
    end
  end
end)

local function counts()
  local inst, done = 0, 0
  for _, pkg in ipairs(mr.get_all_packages()) do
    if pkg:is_installing() then
      inst = inst + 1
    elseif pkg:is_installed() then
      done = done + 1
    end
  end
  return inst, done
end

vim.wait(45000, function() return false end) -- 入队缓冲
local stable, lastdone = 0, -1
local t0 = vim.uv.hrtime()
local timedout = false
while true do
  if vim.uv.hrtime() - t0 > 1500e9 then
    timedout = true
    break
  end
  local inst, done = counts()
  if inst == 0 and done == lastdone and done > 0 then
    stable = stable + 1
  else
    stable = 0
  end
  lastdone = done
  if stable >= 4 and inst == 0 then
    break
  end
  vim.wait(3000)
end
local _, done = counts()
print((timedout and "MASON TIMEOUT" or "MASON DONE") .. " installed=" .. done)
print("INSTALLED " .. table.concat(mr.get_installed_package_names(), ","))
vim.cmd("qa!")
