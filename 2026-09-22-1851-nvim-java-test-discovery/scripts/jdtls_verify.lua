-- Verify: after workspace wipe, does test discovery work on the real project?
local probe_file = "/home/desmond/Repos/ups-hms-all-in-one/.worktrees/2026-09-21-1726-lazyvim-java-lsp/backend/src/test/java/com/ups/upshmsbackend/FieldPositionUtilTest.java"

local function log(msg) print("[VERIFY] " .. msg) end
vim.fn.timer_start(540000, function()
  log("WATCHDOG fired - quitting")
  vim.cmd("qa!")
end)

vim.cmd.edit(probe_file)
local ok = vim.wait(180000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "jdtls" }) > 0
end, 500)
log("attached=" .. tostring(ok))
local client = vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })[1]
if not client then
  log("FATAL no client")
  vim.cmd("qa!")
end
log("root_dir=" .. tostring(client.config.root_dir))

local uri = vim.uri_from_bufnr(0)
local function exec(cmd_name, args)
  local result, err, done = nil, nil, false
  client:request("workspace/executeCommand", { command = cmd_name, arguments = args }, function(e, r)
    err, result, done = e, r, true
  end, 0)
  vim.wait(30000, function() return done end, 100)
  return err, result
end

-- poll: every 10s up to 210s, report the FIRST time test discovery returns non-empty
local elapsed = 0
while elapsed < 480 do
  vim.wait(15000)
  elapsed = elapsed + 15
  local err, result = exec("vscode.java.test.findTestTypesAndMethods", { uri })
  local n = (result and #result) or -1
  log(string.format("+%ds findTestTypesAndMethods -> %s entries %s", elapsed, n, err and ("ERR " .. tostring(err.message)) or ""))
  if n > 0 then
    log("NON-EMPTY RESULT — full dump:")
    print(vim.inspect(result))
    break
  end
end
log("VERIFY DONE")
vim.cmd("qa!")
