---Change application logic for doitforme.nvim
local config = require("doitforme.config")
local task_mod = require("doitforme.task")
local prompt_mod = require("doitforme.prompt")
local ui = require("doitforme.ui")
local util = require("doitforme.util")

local M = {}

---Apply changes from AI response to the buffer
---@param task doitforme.Task The task with AI response
---@param response table The raw API response
---@return boolean success
function M.apply(task, response)
  -- Extract code from response
  local raw_code = prompt_mod.extract_code_from_response(response)

  if not raw_code then
    task_mod.update_status(task.id, "failed", { error = "No code in AI response" })
    ui.show_error(task, "No code in AI response")
    return false
  end

  -- Parse response to get clean code and imports
  local code, imports = prompt_mod.parse_response(raw_code)

  if not code or code == "" then
    task_mod.update_status(task.id, "failed", { error = "Empty code response" })
    ui.show_error(task, "Empty code response")
    return false
  end

  -- Check for conflicts
  local cfg = config.get()
  if task_mod.is_selection_modified(task) then
    if cfg.behavior.warn_on_conflict then
      util.warn("Selection was modified while AI was processing")
    end
    if cfg.behavior.cancel_on_conflict then
      task_mod.update_status(task.id, "cancelled", { error = "Cancelled due to conflict" })
      ui.hide_indicator(task)
      return false
    end
  end

  -- Check if buffer is still valid
  if not vim.api.nvim_buf_is_valid(task.bufnr) then
    task_mod.update_status(task.id, "failed", { error = "Buffer no longer valid" })
    return false
  end

  -- Review mode: show diff first
  if cfg.behavior.review_mode then
    ui.hide_indicator(task)
    ui.show_diff_preview(task, code, function(accepted)
      if accepted then
        M.do_apply(task, code, imports)
      else
        task_mod.update_status(task.id, "cancelled", { error = "User rejected changes" })
        util.notify("Changes rejected")
      end
    end)
    return true
  end

  -- Apply directly
  return M.do_apply(task, code, imports)
end

---Actually apply the changes to the buffer
---@param task doitforme.Task The task
---@param code string The code to insert
---@param imports string|nil Import statements to add
---@return boolean success
function M.do_apply(task, code, imports)
  local bufnr = task.bufnr

  -- Ensure buffer is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    task_mod.update_status(task.id, "failed", { error = "Buffer no longer valid" })
    return false
  end

  -- Split code into lines
  local new_lines = vim.split(code, "\n")

  -- Apply the changes to the selection region
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_lines(
      bufnr,
      task.selection.start_line - 1,
      task.selection.end_line,
      false,
      new_lines
    )
  end)

  if not ok then
    task_mod.update_status(task.id, "failed", { error = "Failed to apply changes: " .. tostring(err) })
    ui.show_error(task, "Failed to apply changes")
    return false
  end

  -- Handle imports if any
  if imports then
    M.add_imports(bufnr, imports)
  end

  -- Success
  task_mod.update_status(task.id, "completed", { result = code })
  ui.show_success(task)

  return true
end

---Add import statements to the top of the file
---@param bufnr number Buffer number
---@param imports string Import statement(s)
function M.add_imports(bufnr, imports)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local filetype = vim.bo[bufnr].filetype

  -- Find the right place to insert imports based on filetype
  local insert_line = 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 50, false) -- Check first 50 lines

  -- Language-specific import detection
  local import_patterns = {
    -- JavaScript/TypeScript
    javascript = { "^import%s", "^const%s.+=%s*require", "^let%s.+=%s*require", "^var%s.+=%s*require" },
    typescript = { "^import%s", "^const%s.+=%s*require" },
    typescriptreact = { "^import%s", "^const%s.+=%s*require" },
    javascriptreact = { "^import%s", "^const%s.+=%s*require" },
    -- Python
    python = { "^import%s", "^from%s.+import" },
    -- Go
    go = { "^import%s" },
    -- Rust
    rust = { "^use%s" },
    -- Lua
    lua = { "^local%s.+=%s*require", "^require" },
    -- Ruby
    ruby = { "^require%s", "^require_relative%s" },
    -- PHP
    php = { "^use%s", "^require%s", "^include%s" },
  }

  local patterns = import_patterns[filetype] or {}

  -- Find the last import line
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(patterns) do
      if line:match(pattern) then
        insert_line = i
        break
      end
    end
  end

  -- Skip shebang, comments at top
  if insert_line == 0 then
    for i, line in ipairs(lines) do
      if not line:match("^#!") and not line:match("^%s*$") and not line:match("^%s*//") and not line:match("^%s*%-%-") and not line:match("^%s*/%*") and not line:match("^%s*#") then
        insert_line = i - 1
        break
      end
    end
  end

  -- Insert the import
  local import_lines = vim.split(imports, "\n")
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, import_lines)

  util.notify("Added import: " .. imports)
end

return M
