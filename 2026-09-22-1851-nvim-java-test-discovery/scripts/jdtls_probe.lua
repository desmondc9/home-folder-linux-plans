-- Probe how the server/test-plugin views the project & the test file URI
local probe_file = os.getenv("PROBE_FILE")

local function log(msg) print("[PROBE] " .. msg) end

-- hard watchdog: force quit after 300s no matter what
vim.fn.timer_start(300000, function()
  log("WATCHDOG fired - quitting")
  vim.cmd("qa!")
end)

vim.cmd.edit(probe_file)
local ok = vim.wait(120000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "jdtls" }) > 0
end, 500)
log("attached=" .. tostring(ok))
local client = vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })[1]
log("root_dir=" .. tostring(client and client.config.root_dir))
-- wait for service ready-ish, then retry discovery until non-empty or 6 tries
vim.wait(15000)
local uri_pre = vim.uri_from_bufnr(0)
local function exec_pre(cmd_name, args)
  local result, err, done = nil, nil, false
  client:request("workspace/executeCommand", { command = cmd_name, arguments = args }, function(e, r)
    err, result, done = e, r, true
  end, 0)
  vim.wait(30000, function() return done end, 100)
  return err, result
end
for attempt = 1, 6 do
  local err, result = exec_pre("vscode.java.test.findTestTypesAndMethods", { uri_pre })
  local n = (result and type(result) == "table" and #result) or -1
  log("discovery attempt " .. attempt .. " -> entries=" .. n .. (err and (" ERR:" .. tostring(err.message)) or ""))
  if n > 0 then
    log("DISCOVERY OK")
    break
  end
  vim.wait(10000)
end

local uri = vim.uri_from_bufnr(0)
log("uri=" .. uri)

local function exec(cmd_name, args)
  local result, err, done = nil, nil, false
  client:request("workspace/executeCommand", { command = cmd_name, arguments = args }, function(e, r)
    err, result, done = e, r, true
  end, 0)
  vim.wait(30000, function() return done end, 100)
  if err then
    log(cmd_name .. " ERR: " .. vim.inspect(err))
  else
    log(cmd_name .. " ->")
    print(vim.inspect(result))
  end
end

exec("java.project.getAll", {})
exec("vscode.java.test.findJavaProjects", {})
exec("vscode.java.test.resolvePath", { uri })
exec("java.project.isTestFile", { uri })
exec("java.project.getClasspaths", { uri, vim.fn.json_encode({ scope = "test" }) })
exec("vscode.java.test.findTestPackagesAndTypes", { uri })
exec("vscode.java.test.findTestTypesAndMethods", { uri })
log("PROBE DONE")
vim.cmd("qa!")

