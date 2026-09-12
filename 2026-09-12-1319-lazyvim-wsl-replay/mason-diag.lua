-- 诊断:为什么 extras 的 mason 包没入队
local ok_load, err = pcall(function()
  require("lazy").load({ plugins = { "nvim-lspconfig", "mason.nvim", "mason-lspconfig.nvim" } })
end)
print("LOAD_OK=" .. tostring(ok_load) .. (err and (" ERR=" .. tostring(err)) or ""))
local plugins = require("lazy.core.config").plugins
local names = {}
for n, _ in pairs(plugins) do
  if n:match("mason") or n:match("lspconfig") then
    names[#names + 1] = n
  end
end
print("PLUGIN_NAMES " .. table.concat(names, ","))
local ok_opts, mo = pcall(function() return require("lazyvim.util").opts("mason.nvim") end)
if ok_opts and mo then
  print("MASON_ENSURE " .. vim.inspect(mo.ensure_installed))
end
local ok_ls, lo = pcall(function() return require("lazyvim.util").opts("nvim-lspconfig") end)
if ok_ls and lo and lo.servers then
  local ks = vim.tbl_keys(lo.servers)
  table.sort(ks)
  print("LSP_SERVERS " .. table.concat(ks, ","))
end
vim.wait(20000, function() return false end)
local mr = require("mason-registry")
print("NOW_INSTALLED " .. table.concat(mr.get_installed_package_names(), ","))
local inst = {}
for _, p in ipairs(mr.get_all_packages()) do
  if p:is_installing() then
    inst[#inst + 1] = p.name
  end
end
print("NOW_INSTALLING " .. table.concat(inst, ","))
vim.cmd("qa!")
