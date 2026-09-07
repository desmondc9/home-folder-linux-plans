-- LSP attach check: wait until client count is stable, then print attached clients
local label = vim.api.nvim_buf_get_name(0)
local last, stable = -1, 0
local t0 = vim.uv.hrtime()
while vim.uv.hrtime() - t0 < 110e9 do
  local n = #vim.lsp.get_clients()
  if n == last and n > 0 then
    stable = stable + 1
  else
    stable = 0
  end
  last = n
  if stable >= 3 then
    break
  end
  vim.wait(2000)
end
local names = {}
for _, c in ipairs(vim.lsp.get_clients()) do
  names[#names + 1] = c.name
end
print("CLIENTS " .. label .. " -> " .. (next(names) and table.concat(names, ",") or "NONE"))
vim.cmd("qa!")
