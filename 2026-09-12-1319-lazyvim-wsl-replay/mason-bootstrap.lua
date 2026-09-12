-- headless 引导:等 Mason 队列清空 + 安装计数稳定后退出(母本 VPS 教训:提前 qa 会掐掉异步安装)
-- 用法: nvim --headless -u ~/.config/nvim/init.lua +'lua dofile(".../mason-bootstrap.lua")'
local mr = require("mason-registry")

-- 1) 显式安装 debug 适配器(dap.core 未覆盖的按语言适配器)
local debug_pkgs = { "codelldb", "debugpy", "delve", "java-debug-adapter", "java-test" }
mr.refresh(function()
  for _, name in ipairs(debug_pkgs) do
    local ok, pkg = pcall(mr.get_package, name)
    if ok and pkg and not pkg:is_installed() then
      print("BOOT installing " .. name)
      pkg:install()
    end
  end
end)

-- 2) 等 ensure_installed(各 lang extras 声明的)+ 上述显式包全部装完:
--    给入队 30s 缓冲,随后要求「正在安装数=0 且 已装计数」连续 5 次(×3s)不变才放行
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

vim.wait(30000, function() return false end) -- 入队缓冲
local stable, last = 0, -1
local t0 = vim.uv.hrtime()
while vim.uv.hrtime() - t0 < 1200e9 do
  local inst, done = counts()
  local state = inst * 100000 + done
  if state == last then
    stable = stable + 1
  else
    stable = 0
  end
  last = state
  if stable >= 5 then
    print(("MASON DONE installed=%d installing=%d"):format(done, inst))
    break
  end
  vim.wait(3000)
end
if vim.uv.hrtime() - t0 >= 1200e9 then
  print("MASON TIMEOUT")
end
vim.cmd("qa!")
