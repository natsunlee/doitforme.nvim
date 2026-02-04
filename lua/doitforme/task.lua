---Task management for doitforme.nvim
local config = require("doitforme.config")
local util = require("doitforme.util")
local server = require("doitforme.server")

local M = {}

---@alias TaskStatus "pending"|"running"|"completed"|"failed"|"cancelled"

---@class doitforme.Selection
---@field start_line number Start line (1-indexed)
---@field start_col number Start column
---@field end_line number End line (1-indexed)
---@field end_col number End column
---@field bufnr number Buffer number

---@class doitforme.Task
---@field id string Unique task ID
---@field bufnr number Buffer number
---@field selection doitforme.Selection Selection range
---@field prompt string User prompt
---@field status TaskStatus Current status
---@field original_content string Snapshot of original selection
---@field session_id string|nil OpenCode session ID
---@field result string|nil AI response
---@field error string|nil Error message if failed
---@field mark_id number|nil Extmark ID for indicator
---@field spinner_timer userdata|nil Timer for spinner animation

---@type table<string, doitforme.Task>
M.tasks = {}

---Create a new task
---@param bufnr number Buffer number
---@param selection doitforme.Selection Selection range
---@param prompt string User prompt
---@return doitforme.Task
function M.create(bufnr, selection, prompt)
  local task = {
    id = util.generate_id(),
    bufnr = bufnr,
    selection = vim.deepcopy(selection),
    prompt = prompt,
    status = "pending",
    original_content = util.get_buffer_text(bufnr, selection.start_line, selection.end_line),
    session_id = nil,
    result = nil,
    error = nil,
    mark_id = nil,
    spinner_timer = nil,
  }

  M.tasks[task.id] = task
  return task
end

---Get a task by ID
---@param task_id string Task ID
---@return doitforme.Task|nil
function M.get(task_id)
  return M.tasks[task_id]
end

---Get all tasks for a buffer
---@param bufnr number Buffer number
---@return doitforme.Task[]
function M.get_by_buffer(bufnr)
  local result = {}
  for _, task in pairs(M.tasks) do
    if task.bufnr == bufnr then
      table.insert(result, task)
    end
  end
  return result
end

---Get all active tasks (pending or running)
---@return doitforme.Task[]
function M.get_active()
  local result = {}
  for _, task in pairs(M.tasks) do
    if task.status == "pending" or task.status == "running" then
      table.insert(result, task)
    end
  end
  return result
end

---Update task status
---@param task_id string Task ID
---@param status TaskStatus New status
---@param data? table Additional data (result, error)
function M.update_status(task_id, status, data)
  local task = M.tasks[task_id]
  if not task then return end

  task.status = status

  if data then
    if data.result then task.result = data.result end
    if data.error then task.error = data.error end
    if data.session_id then task.session_id = data.session_id end
  end
end

---Cancel a task
---@param task_id string Task ID
---@return boolean success
function M.cancel(task_id)
  local task = M.tasks[task_id]
  if not task then
    return false
  end

  if task.status ~= "pending" and task.status ~= "running" then
    return false
  end

  -- Stop spinner timer
  if task.spinner_timer then
    task.spinner_timer:stop()
    task.spinner_timer:close()
    task.spinner_timer = nil
  end

  -- Abort OpenCode session if running
  if task.session_id and task.status == "running" then
    server.abort_session(task.session_id)
  end

  task.status = "cancelled"
  return true
end

---Remove a task from tracking
---@param task_id string Task ID
function M.remove(task_id)
  local task = M.tasks[task_id]
  if task then
    -- Cleanup timer
    if task.spinner_timer then
      task.spinner_timer:stop()
      task.spinner_timer:close()
    end
  end
  M.tasks[task_id] = nil
end

---Check if selection has been modified since task creation
---@param task doitforme.Task Task to check
---@return boolean modified
function M.is_selection_modified(task)
  if not vim.api.nvim_buf_is_valid(task.bufnr) then
    return true
  end

  local current_content = util.get_buffer_text(task.bufnr, task.selection.start_line, task.selection.end_line)
  return current_content ~= task.original_content
end

---Clear all tasks for a buffer
---@param bufnr number Buffer number
function M.clear_buffer(bufnr)
  for id, task in pairs(M.tasks) do
    if task.bufnr == bufnr then
      M.cancel(id)
      M.remove(id)
    end
  end
end

---Clear all completed/failed/cancelled tasks
function M.clear_finished()
  for id, task in pairs(M.tasks) do
    if task.status == "completed" or task.status == "failed" or task.status == "cancelled" then
      M.remove(id)
    end
  end
end

return M
