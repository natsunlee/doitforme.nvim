---UI components for doitforme.nvim
local config = require("doitforme.config")

local M = {}

---Namespace for extmarks
M.ns_id = vim.api.nvim_create_namespace("doitforme")

---Highlight groups
local highlight_groups = {
  DoItForMeSpinner = { link = "Comment" },
  DoItForMeSuccess = { link = "DiagnosticOk" },
  DoItForMeError = { link = "DiagnosticError" },
  DoItForMeWarning = { link = "DiagnosticWarn" },
  DoItForMeDiffAdd = { link = "DiffAdd" },
  DoItForMeDiffDelete = { link = "DiffDelete" },
  DoItForMeDiffChange = { link = "DiffChange" },
}

---Setup highlight groups
function M.setup_highlights()
  for name, def in pairs(highlight_groups) do
    vim.api.nvim_set_hl(0, name, def)
  end
end

---Show spinner indicator for a task
---@param task doitforme.Task Task to show indicator for
function M.show_indicator(task)
  if not vim.api.nvim_buf_is_valid(task.bufnr) then
    return
  end

  local cfg = config.get()
  local indicator = cfg.ui.indicator

  -- Calculate line for indicator
  local line
  if indicator.position == "above" then
    line = math.max(0, task.selection.start_line - 2)
  else
    line = task.selection.end_line
  end

  -- Ensure line is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(task.bufnr)
  line = math.min(line, line_count - 1)

  -- Create extmark with virtual text
  task.mark_id = vim.api.nvim_buf_set_extmark(task.bufnr, M.ns_id, line, 0, {
    virt_text = { { indicator.spinner[1] .. " AI processing...", "DoItForMeSpinner" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })

  -- Start spinner animation
  M.start_spinner(task)
end

---Start spinner animation for a task
---@param task doitforme.Task Task to animate spinner for
function M.start_spinner(task)
  local cfg = config.get()
  local spinner = cfg.ui.indicator.spinner
  local idx = 1

  task.spinner_timer = vim.uv.new_timer()
  task.spinner_timer:start(0, 100, function()
    vim.schedule(function()
      -- Stop if task is no longer running
      if task.status ~= "pending" and task.status ~= "running" then
        if task.spinner_timer then
          task.spinner_timer:stop()
          task.spinner_timer:close()
          task.spinner_timer = nil
        end
        return
      end

      -- Stop if buffer is invalid
      if not vim.api.nvim_buf_is_valid(task.bufnr) then
        if task.spinner_timer then
          task.spinner_timer:stop()
          task.spinner_timer:close()
          task.spinner_timer = nil
        end
        return
      end

      idx = (idx % #spinner) + 1

      -- Update extmark with new spinner frame
      if task.mark_id then
        local ok = pcall(function()
          -- Get current extmark position
          local mark = vim.api.nvim_buf_get_extmark_by_id(task.bufnr, M.ns_id, task.mark_id, {})
          if mark and #mark > 0 then
            vim.api.nvim_buf_set_extmark(task.bufnr, M.ns_id, mark[1], 0, {
              id = task.mark_id,
              virt_text = { { spinner[idx] .. " AI processing...", "DoItForMeSpinner" } },
              virt_text_pos = "eol",
              hl_mode = "combine",
            })
          end
        end)

        if not ok then
          -- Mark was deleted, stop animation
          if task.spinner_timer then
            task.spinner_timer:stop()
            task.spinner_timer:close()
            task.spinner_timer = nil
          end
        end
      end
    end)
  end)
end

---Hide indicator for a task
---@param task doitforme.Task Task to hide indicator for
function M.hide_indicator(task)
  -- Stop spinner timer
  if task.spinner_timer then
    task.spinner_timer:stop()
    task.spinner_timer:close()
    task.spinner_timer = nil
  end

  -- Remove extmark
  if task.mark_id and vim.api.nvim_buf_is_valid(task.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, task.bufnr, M.ns_id, task.mark_id)
    task.mark_id = nil
  end
end

---Show success indicator (briefly)
---@param task doitforme.Task Task to show success for
function M.show_success(task)
  M.hide_indicator(task)

  if not vim.api.nvim_buf_is_valid(task.bufnr) then
    return
  end

  local cfg = config.get()

  -- Calculate line for indicator
  local line
  if cfg.ui.indicator.position == "above" then
    line = math.max(0, task.selection.start_line - 2)
  else
    line = task.selection.end_line
  end

  local line_count = vim.api.nvim_buf_line_count(task.bufnr)
  line = math.min(line, line_count - 1)

  -- Show success indicator
  local mark_id = vim.api.nvim_buf_set_extmark(task.bufnr, M.ns_id, line, 0, {
    virt_text = { { " Changes applied", "DoItForMeSuccess" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })

  -- Remove after 2 seconds
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(task.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, task.bufnr, M.ns_id, mark_id)
    end
  end, 2000)
end

---Show error indicator (briefly)
---@param task doitforme.Task Task to show error for
---@param message string Error message
function M.show_error(task, message)
  M.hide_indicator(task)

  if not vim.api.nvim_buf_is_valid(task.bufnr) then
    return
  end

  local cfg = config.get()

  -- Calculate line for indicator
  local line
  if cfg.ui.indicator.position == "above" then
    line = math.max(0, task.selection.start_line - 2)
  else
    line = task.selection.end_line
  end

  local line_count = vim.api.nvim_buf_line_count(task.bufnr)
  line = math.min(line, line_count - 1)

  -- Show error indicator
  local short_msg = message:sub(1, 50)
  if #message > 50 then
    short_msg = short_msg .. "..."
  end

  local mark_id = vim.api.nvim_buf_set_extmark(task.bufnr, M.ns_id, line, 0, {
    virt_text = { { " Error: " .. short_msg, "DoItForMeError" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })

  -- Remove after 5 seconds
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(task.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, task.bufnr, M.ns_id, mark_id)
    end
  end, 5000)
end

---Show diff preview window
---@param task doitforme.Task The task
---@param new_content string The new content to preview
---@param callback fun(accepted: boolean) Callback when user accepts/rejects
function M.show_diff_preview(task, new_content, callback)
  -- Create a scratch buffer for the diff
  local diff_bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer content with original and new
  local original_lines = vim.split(task.original_content, "\n")
  local new_lines = vim.split(new_content, "\n")

  -- Create a simple side-by-side preview
  local content = {
    "┌─────────────────────────────────────────────────────────────────┐",
    "│ ORIGINAL (lines " .. task.selection.start_line .. "-" .. task.selection.end_line .. "):",
    "├─────────────────────────────────────────────────────────────────┤",
  }

  for _, line in ipairs(original_lines) do
    table.insert(content, "│ " .. line)
  end

  table.insert(content, "├─────────────────────────────────────────────────────────────────┤")
  table.insert(content, "│ NEW:")
  table.insert(content, "├─────────────────────────────────────────────────────────────────┤")

  for _, line in ipairs(new_lines) do
    table.insert(content, "│ " .. line)
  end

  table.insert(content, "└─────────────────────────────────────────────────────────────────┘")
  table.insert(content, "")
  table.insert(content, "Press 'y' to accept, 'n' to reject, 'q' to cancel")

  vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, content)
  vim.bo[diff_bufnr].modifiable = false
  vim.bo[diff_bufnr].buftype = "nofile"
  vim.bo[diff_bufnr].bufhidden = "wipe"
  vim.bo[diff_bufnr].filetype = "doitforme_diff"

  -- Calculate window size
  local width = 70
  local height = #content
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local win = vim.api.nvim_open_win(diff_bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Review Changes ",
    title_pos = "center",
  })

  -- Set keymaps for accept/reject
  local function close_and_callback(accepted)
    vim.api.nvim_win_close(win, true)
    callback(accepted)
  end

  vim.keymap.set("n", "y", function() close_and_callback(true) end, { buffer = diff_bufnr })
  vim.keymap.set("n", "n", function() close_and_callback(false) end, { buffer = diff_bufnr })
  vim.keymap.set("n", "q", function() close_and_callback(false) end, { buffer = diff_bufnr })
  vim.keymap.set("n", "<Esc>", function() close_and_callback(false) end, { buffer = diff_bufnr })
end

---Clear all indicators from a buffer
---@param bufnr number Buffer number
function M.clear_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)
  end
end

return M
