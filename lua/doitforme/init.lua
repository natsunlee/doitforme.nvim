---doitforme.nvim - AI-powered code modification via OpenCode
---@module doitforme

local M = {}

local config = require("doitforme.config")
local server = require("doitforme.server")
local task_mod = require("doitforme.task")
local prompt_mod = require("doitforme.prompt")
local apply = require("doitforme.apply")
local ui = require("doitforme.ui")
local util = require("doitforme.util")

---@type boolean
M.initialized = false

---Setup the plugin
---@param opts? doitforme.Config
function M.setup(opts)
  config.setup(opts)
  ui.setup_highlights()
  M.initialized = true

  -- Setup cleanup on VimLeavePre
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("doitforme_cleanup", { clear = true }),
    callback = function()
      server.cleanup()
    end,
  })
end

---Check if snacks.nvim is available
---@return boolean
local function has_snacks()
  local ok, _ = pcall(require, "snacks")
  return ok
end

---Get selection based on current mode
---@return doitforme.Selection|nil
local function get_selection()
  local mode = vim.fn.mode()

  -- Check if we're in visual mode or have a recent visual selection
  if mode == "v" or mode == "V" or mode == "\22" then
    -- We're in visual mode
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")

    -- Ensure start is before end
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end

    return {
      start_line = start_pos[2],
      start_col = start_pos[3],
      end_line = end_pos[2],
      end_col = end_pos[3],
      bufnr = vim.api.nvim_get_current_buf(),
    }
  end

  -- Check for visual selection marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  if start_pos[2] > 0 and end_pos[2] > 0 then
    return {
      start_line = start_pos[2],
      start_col = start_pos[3],
      end_line = end_pos[2],
      end_col = end_pos[3],
      bufnr = vim.api.nvim_get_current_buf(),
    }
  end

  -- Fall back to cursor line
  return util.get_cursor_line_selection()
end

---Run a task - create session and send prompt
---@param task doitforme.Task The task to run
local function run_task(task)
  local cfg = config.get()

  -- Build the full prompt
  local full_prompt = prompt_mod.build_prompt(task)

  -- Create a new session for this task
  server.create_session(function(err, session_id)
    if err then
      task_mod.update_status(task.id, "failed", { error = "Failed to create session: " .. err })
      ui.show_error(task, "Failed to create session")
      return
    end

    task_mod.update_status(task.id, "running", { session_id = session_id })

    -- Parse model config if specified
    local model = nil
    if cfg.model then
      local provider, model_id = cfg.model:match("([^/]+)/(.+)")
      if provider and model_id then
        model = { providerID = provider, modelID = model_id }
      end
    end

    -- Send the prompt
    server.send_prompt(session_id, full_prompt, model, function(prompt_err, response)
      if prompt_err then
        task_mod.update_status(task.id, "failed", { error = "AI request failed: " .. prompt_err })
        ui.show_error(task, "AI request failed")
        return
      end

      -- Apply the changes
      apply.apply(task, response)
    end)
  end)
end

---Main entry point - open prompt for AI modification
---@param opts? { selection?: doitforme.Selection }
function M.prompt(opts)
  opts = opts or {}

  if not M.initialized then
    util.error("doitforme.nvim is not initialized. Call setup() first.")
    return
  end

  -- Check for snacks.nvim
  if not has_snacks() then
    util.error("snacks.nvim is required but not installed")
    return
  end

  local Snacks = require("snacks")

  -- Get selection
  local selection = opts.selection or get_selection()

  if not selection then
    util.error("No selection found")
    return
  end

  local bufnr = selection.bufnr

  -- Exit visual mode if we're in it
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd("normal! ")
  end

  -- Get config
  local cfg = config.get()

  -- Open snacks input
  Snacks.input({
    prompt = cfg.ui.input.prompt,
    win = {
      border = cfg.ui.input.border,
    },
  }, function(user_prompt)
    if not user_prompt or user_prompt == "" then
      return
    end

    -- Ensure server is connected
    server.ensure_connected(function(connected)
      if not connected then
        util.error("Failed to connect to OpenCode server")
        return
      end

      -- Create the task
      local task = task_mod.create(bufnr, selection, user_prompt)

      -- Show indicator
      ui.show_indicator(task)

      -- Run the task asynchronously
      run_task(task)
    end)
  end)
end

---Cancel a specific task
---@param task_id string Task ID to cancel
---@return boolean success
function M.cancel(task_id)
  local task = task_mod.get(task_id)
  if not task then
    util.warn("Task not found: " .. task_id)
    return false
  end

  local success = task_mod.cancel(task_id)
  if success then
    ui.hide_indicator(task)
    util.notify("Task cancelled")
  end

  return success
end

---Cancel all active tasks for the current buffer
function M.cancel_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local tasks = task_mod.get_by_buffer(bufnr)
  local cancelled = 0

  for _, task in ipairs(tasks) do
    if task.status == "pending" or task.status == "running" then
      if task_mod.cancel(task.id) then
        ui.hide_indicator(task)
        cancelled = cancelled + 1
      end
    end
  end

  if cancelled > 0 then
    util.notify(string.format("Cancelled %d task(s)", cancelled))
  else
    util.notify("No active tasks to cancel")
  end
end

---Get list of all active tasks
---@return doitforme.Task[]
function M.tasks()
  return task_mod.get_active()
end

---Show status of active tasks
function M.status()
  local active = task_mod.get_active()

  if #active == 0 then
    util.notify("No active tasks")
    return
  end

  local lines = { "Active tasks:" }
  for _, task in ipairs(active) do
    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(task.bufnr), ":t")
    table.insert(lines, string.format(
      "  [%s] %s (lines %d-%d) - %s",
      task.status,
      filename,
      task.selection.start_line,
      task.selection.end_line,
      task.prompt:sub(1, 30) .. (task.prompt:len() > 30 and "..." or "")
    ))
  end

  util.notify(table.concat(lines, "\n"))
end

return M
