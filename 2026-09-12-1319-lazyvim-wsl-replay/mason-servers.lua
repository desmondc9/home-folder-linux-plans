-- headless 引导第 3 步:LSP server 包显式安装
-- 方法(VPS 档案反查法):遍历 mason-registry 全部包 spec,取 spec.neovim.lspconfig 字段
-- 与 LazyVim 合并后的 nvim-lspconfig opts.servers 键匹配,命中即装。
local mr = require("mason-registry")
mr:on("package:install:failed", function(pkg)
  print("FAILED " .. pkg.name)
end)

pcall(function()
  require("lazy").load({ plugins = { "nvim-lspconfig", "mason.nvim", "mason-lspconfig.nvim" } })
end)

local ok_opts, lo = pcall(function() return require("lazyvim.util").opts("nvim-lspconfig") end)
local servers = (ok_opts and lo and lo.servers) and vim.tbl_keys(lo.servers) or {}
table.sort(servers)
print("SERVERS " .. table.concat(servers, ","))

mr.refresh(function()
  local specs = mr.get_all_package_specs()
  local by_lspconfig = {}
  for _, s in ipairs(specs) do
    local lc = s.neovim and s.neovim.lspconfig
    if type(lc) == "string" then
      by_lspconfig[lc] = s.name
    elseif type(lc) == "table" then
      for _, name in ipairs(lc) do
        by_lspconfig[name] = s.name
      end
    end
  end
  local missing = {}
  for _, server in ipairs(servers) do
    local pkg = by_lspconfig[server]
    if pkg then
      local ok, p = pcall(mr.get_package, pkg)
      if ok and p and not p:is_installed() then
        missing[#missing + 1] = pkg
      end
    elseif server ~= "stylua" and server ~= "*" then
      print("NO_MASON_MAP " .. server)
    end
  end
  -- extras 声明的 formatter/linter 兜底(第 2 轮未入队的)
  for _, tool in ipairs({ "prettierd", "impl", "gomodifytags", "ruff" }) do
    local ok, p = pcall(mr.get_package, tool)
    if ok and p and not p:is_installed() then
      missing[#missing + 1] = tool
    end
  end
  table.sort(missing)
  if #missing > 0 then
    print("INSTALLING " .. table.concat(missing, ","))
    for _, name in ipairs(missing) do
      mr.get_package(name):install()
    end
  else
    print("NOTHING_TO_INSTALL")
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

vim.wait(30000, function() return false end)
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
