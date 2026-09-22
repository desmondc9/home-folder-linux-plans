-- Probe binding resolution via hover on @Test annotation and class name
local probe_file = os.getenv("PROBE_FILE")

local function log(msg) print("[HOVER] " .. msg) end
vim.fn.timer_start(200000, function()
  log("WATCHDOG fired - quitting")
  vim.cmd("qa!")
end)

vim.cmd.edit(probe_file)
local ok = vim.wait(120000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "jdtls" }) > 0
end, 500)
log("attached=" .. tostring(ok))
local client = vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })[1]
vim.wait(20000)

local buf = vim.api.nvim_get_current_buf()
local function hover_at(line1, col1, label)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = line1 - 1, character = col1 - 1 } }
  local result, done = nil, false
  client:request("textDocument/hover", params, function(err, r)
    result = { err = err, r = r }
    done = true
  end, buf)
  vim.wait(15000, function() return done end, 100)
  local txt = ""
  if result and result.r then
    local h = result.r
    if h.contents then
      if type(h.contents) == "table" and h.contents.value then
        txt = h.contents.value
      elseif type(h.contents) == "string" then
        txt = h.contents
      else
        txt = vim.inspect(h.contents):sub(1, 400)
      end
    end
  end
  log(string.format("%s => err=%s len=%d :: %s", label, result and vim.inspect(result.err) or "TIMEOUT", #txt, txt:sub(1, 300):gsub("\n", " | ")))
end

-- FieldPositionUtilTest.java: line 9 = import org.junit.jupiter.api.Test; line 13 = @Test; line 11 = class decl
hover_at(9, 40, "hover on import Test")
hover_at(13, 6, "hover on @Test annotation")
hover_at(11, 14, "hover on class name")
hover_at(15, 45, "hover on getPosition() call")

log("HOVER DONE")
vim.cmd("qa!")
