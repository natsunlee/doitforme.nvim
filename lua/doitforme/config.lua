---@class doitforme.ServerConfig
---@field host string Server hostname
---@field port number Server port
---@field auto_start boolean Start server if not running
---@field startup_timeout number Timeout waiting for server to start (ms)

---@class doitforme.ContextConfig
---@field include_full_file boolean Send entire file for context
---@field lines_before number Lines before selection (when not full file)
---@field lines_after number Lines after selection (when not full file)

---@class doitforme.BehaviorConfig
---@field review_mode boolean Show diff before applying changes
---@field warn_on_conflict boolean Warn if user edits during AI work
---@field cancel_on_conflict boolean Cancel task if user edits during AI work

---@class doitforme.IndicatorConfig
---@field spinner string[] Spinner animation frames
---@field position "above"|"below" Position relative to selection
---@field hl_group string Highlight group for indicator

---@class doitforme.InputConfig
---@field prompt string Input prompt text
---@field border string Border style

---@class doitforme.UIConfig
---@field indicator doitforme.IndicatorConfig
---@field input doitforme.InputConfig

---@class doitforme.Config
---@field server doitforme.ServerConfig
---@field context doitforme.ContextConfig
---@field behavior doitforme.BehaviorConfig
---@field ui doitforme.UIConfig
---@field model string|nil Model to use (provider/model format)

local M = {}

---@type doitforme.Config
M.defaults = {
  server = {
    host = "127.0.0.1",
    port = 4096,
    auto_start = true,
    startup_timeout = 10000,
  },
  context = {
    include_full_file = true,
    lines_before = 50,
    lines_after = 50,
  },
  behavior = {
    review_mode = false,
    warn_on_conflict = true,
    cancel_on_conflict = false,
  },
  ui = {
    indicator = {
      spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      position = "above",
      hl_group = "Comment",
    },
    input = {
      prompt = "AI Prompt: ",
      border = "rounded",
    },
  },
  model = nil,
}

---@type doitforme.Config
M.options = {}

---Deep merge two tables
---@param t1 table Base table
---@param t2 table Override table
---@return table
local function deep_merge(t1, t2)
  local result = vim.deepcopy(t1)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---Setup configuration
---@param opts? doitforme.Config
function M.setup(opts)
  M.options = deep_merge(M.defaults, opts or {})
end

---Get current configuration
---@return doitforme.Config
function M.get()
  return M.options
end

return M
