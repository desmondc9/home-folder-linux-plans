-- Headless repro: capture raw lens data at the LSP executeCommand boundary
local path = "/home/desmond/Repos/ups-hms-all-in-one/.worktrees/2026-09-21-1726-lazyvim-java-lsp/backend/src/test/java/com/ups/upshmsbackend/FieldPositionUtilTest.java"

local function log(msg)
  print("[REPRO] " .. msg)
end

-- capture vim.notify output
local orig_notify = vim.notify
vim.notify = function(msg, lvl, _)
  log("NOTIFY(level=" .. tostring(lvl) .. "): " .. vim.inspect(msg))
  orig_notify(msg, lvl)
end

log("exepath jdtls = " .. vim.fn.exepath("jdtls"))
log("MASON env = " .. tostring(vim.env.MASON))

vim.cmd.edit(path)
log("opened file, ft=" .. vim.bo.filetype)

-- wait for jdtls to attach
local attached = vim.wait(120000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "jdtls" }) > 0
end, 500)
log("jdtls attached: " .. tostring(attached))

local client = vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })[1]
if not client then
  log("FATAL: no jdtls client")
  vim.cmd("qa!")
end

log("root_dir = " .. tostring(client.config.root_dir))
log("bundles = " .. vim.inspect(client.config.init_options and client.config.init_options.bundles))
local caps = client.server_capabilities.executeCommandProvider
local commands = caps and caps.commands or {}
log("advertised commands count = " .. #commands)
log("has search.codelens = " .. tostring(vim.tbl_contains(commands, "vscode.java.test.search.codelens")))
log("has findTestTypesAndMethods = " .. tostring(vim.tbl_contains(commands, "vscode.java.test.findTestTypesAndMethods")))

-- wait for server import readiness
for _, delay in ipairs({ 5, 15, 30 }) do
  vim.wait(delay * 1000)
  log("=== probe at +" .. delay .. "s after attach ===")

  local uri = vim.uri_from_bufnr(0)
  local function exec(cmd_name)
    local params = { command = cmd_name, arguments = { uri } }
    local result = nil
    local err = nil
    local done = false
    client:request("workspace/executeCommand", params, function(e, r)
      err = e
      result = r
      done = true
    end, 0)
    vim.wait(30000, function() return done end, 100)
    return err, result
  end

  for _, cmd_name in ipairs({ "vscode.java.test.search.codelens", "vscode.java.test.findTestTypesAndMethods" }) do
    local err, result = exec(cmd_name)
    if err then
      log(cmd_name .. " -> ERR: " .. vim.inspect(err))
    else
      log(cmd_name .. " -> RAW RESULT:")
      print(vim.inspect(result))
      if result then
        log(cmd_name .. " entry count = " .. #result)
        for _, lens in ipairs(result) do
          local range = lens.location and lens.location.range or lens.range
          log(string.format(
            "  lens: fullName=%s kind=%s level=%s testKind=%s testLevel=%s rangeStartLine=%s children=%s",
            tostring(lens.fullName), tostring(lens.kind), tostring(lens.level),
            tostring(lens.testKind), tostring(lens.testLevel),
            tostring(range and range.start and range.start.line),
            tostring(lens.children and #lens.children or nil)))
          for _, child in ipairs(lens.children or {}) do
            local cr = child.location and child.location.range or child.range
            log(string.format(
              "    child: fullName=%s kind=%s level=%s testKind=%s testLevel=%s rangeStartLine=%s",
              tostring(child.fullName), tostring(child.kind), tostring(child.level),
              tostring(child.testKind), tostring(child.testLevel),
              tostring(cr and cr.start and cr.start.line)))
          end
        end
      end
    end
  end
end

-- replicate get_method_lens_above_cursor for the user's scenario: cursor inside testGetPosition (line 15, 1-based)
local uri = vim.uri_from_bufnr(0)
local err2, lenses = nil, nil
local done2 = false
client:request("workspace/executeCommand", { command = "vscode.java.test.findTestTypesAndMethods", arguments = { uri } }, function(e, r)
  err2 = e
  lenses = r
  done2 = true
end, 0)
vim.wait(30000, function() return done2 end, 100)

local TestLevel = { Method = 6 }
local LegacyTestLevel = { Method = 4 }
local function find_best(lenses_tree, lnum)
  local best = nil
  local function walk(list)
    for _, lens in pairs(list) do
      local is_method = lens.level == LegacyTestLevel.Method or lens.testLevel == TestLevel.Method
      local range = lens.location and lens.location.range or lens.range
      local line = range and range.start and range.start.line
      if is_method and line and line <= lnum then
        if not best or line > (best.location and best.location.range.start.line or best.range.start.line) then
          best = lens
        end
      end
      if lens.children then
        walk(lens.children)
      end
    end
  end
  walk(lenses_tree or {})
  return best
end

for _, lnum in ipairs({ 12, 14, 15, 16, 21 }) do
  local best = find_best(lenses, lnum)
  log(string.format("cursor lnum(1-based)=%d -> best method lens: %s", lnum, best and best.fullName or "NONE (would notify 'No suitable test method found')"))
end

log("REPRO DONE")
vim.cmd("qa!")
