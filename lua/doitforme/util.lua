---Utility functions for doitforme.nvim
local M = {}

---Generate a unique task ID
---@return string
function M.generate_id()
  return string.format("%s-%s", os.time(), math.random(1000, 9999))
end

---Make an HTTP request using curl (async via vim.system)
---@param method string HTTP method
---@param url string Full URL
---@param body? table Request body (will be JSON encoded)
---@param callback fun(err: string|nil, response: table|nil)
function M.http_request(method, url, body, callback)
  local args = {
    "curl",
    "-s",
    "-X", method,
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
  }

  if body then
    table.insert(args, "-d")
    table.insert(args, vim.fn.json_encode(body))
  end

  table.insert(args, url)

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback("HTTP request failed: " .. (result.stderr or "unknown error"), nil)
        return
      end

      if not result.stdout or result.stdout == "" then
        callback("Empty response from server", nil)
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        callback("Failed to decode JSON response: " .. result.stdout, nil)
        return
      end

      callback(nil, decoded)
    end)
  end)
end

---Make a synchronous HTTP request (blocking)
---@param method string HTTP method
---@param url string Full URL
---@param body? table Request body
---@param timeout? number Timeout in ms
---@return string|nil err
---@return table|nil response
function M.http_request_sync(method, url, body, timeout)
  local args = {
    "curl",
    "-s",
    "-X", method,
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
    "--max-time", tostring((timeout or 5000) / 1000),
  }

  if body then
    table.insert(args, "-d")
    table.insert(args, vim.fn.json_encode(body))
  end

  table.insert(args, url)

  local result = vim.system(args, { text = true }):wait()

  if result.code ~= 0 then
    return "HTTP request failed: " .. (result.stderr or "unknown error"), nil
  end

  if not result.stdout or result.stdout == "" then
    return "Empty response from server", nil
  end

  local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
  if not ok then
    return "Failed to decode JSON response", nil
  end

  return nil, decoded
end

---Get buffer lines as a string
---@param bufnr number Buffer number
---@param start_line? number Start line (1-indexed, inclusive)
---@param end_line? number End line (1-indexed, inclusive)
---@return string
function M.get_buffer_text(bufnr, start_line, end_line)
  local lines
  if start_line and end_line then
    lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  else
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  return table.concat(lines, "\n")
end

---Get visual selection range
---@return table|nil selection { start_line, start_col, end_line, end_col, bufnr }
function M.get_visual_selection()
  local mode = vim.fn.mode()
  
  -- If we're in visual mode, get the current selection
  if mode == "v" or mode == "V" or mode == "\22" then
    -- Exit visual mode to set '< and '> marks
    vim.cmd('normal! "vy')
    vim.cmd('normal! gv')
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Check if marks are valid
  if start_pos[2] == 0 and end_pos[2] == 0 then
    return nil
  end

  return {
    start_line = start_pos[2],
    start_col = start_pos[3],
    end_line = end_pos[2],
    end_col = end_pos[3],
    bufnr = vim.api.nvim_get_current_buf(),
  }
end

---Get selection at cursor position (current line)
---@return table selection { start_line, start_col, end_line, end_col, bufnr }
function M.get_cursor_line_selection()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local bufnr = vim.api.nvim_get_current_buf()

  return {
    start_line = line,
    start_col = 1,
    end_line = line,
    end_col = vim.fn.col("$"),
    bufnr = bufnr,
  }
end

---Check if a command exists
---@param cmd string Command name
---@return boolean
function M.command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

---Debounce a function
---@param fn function Function to debounce
---@param ms number Delay in milliseconds
---@return function
function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

---Notify user with consistent formatting
---@param msg string Message
---@param level? number vim.log.levels.*
function M.notify(msg, level)
  vim.notify("[doitforme] " .. msg, level or vim.log.levels.INFO)
end

---Notify error
---@param msg string Message
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

---Notify warning
---@param msg string Message
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

return M
