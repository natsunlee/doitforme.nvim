---OpenCode server connection and management
local config = require("doitforme.config")
local util = require("doitforme.util")

local M = {}

---@type number|nil Job ID of spawned server process
M.server_job = nil

---@type boolean Whether server is confirmed ready
M.is_ready = false

---@type string|nil Current session ID
M.session_id = nil

---Get the base URL for the server
---@return string
function M.get_base_url()
  local cfg = config.get()
  return string.format("http://%s:%d", cfg.server.host, cfg.server.port)
end

---Check if server is healthy
---@param callback? fun(healthy: boolean, version?: string)
---@return boolean|nil Returns boolean if no callback (sync mode)
function M.health_check(callback)
  local url = M.get_base_url() .. "/health"

  if callback then
    util.http_request("GET", url, nil, function(err, response)
      if err then
        callback(false, nil)
        return
      end
      callback(response and response.healthy == true, response and response.version)
    end)
  else
    local err, response = util.http_request_sync("GET", url, nil, 2000)
    if err then
      return false
    end
    return response and response.healthy == true
  end
end

---Spawn the opencode server process
---@return boolean success
function M.spawn_server()
  if not util.command_exists("opencode") then
    util.error("opencode command not found. Please install opencode first.")
    return false
  end

  local cfg = config.get()

  -- Spawn opencode serve in background
  M.server_job = vim.fn.jobstart({
    "opencode",
    "serve",
    "--port", tostring(cfg.server.port),
    "--hostname", cfg.server.host,
  }, {
    detach = true,
    on_exit = function(_, code)
      if code ~= 0 then
        util.warn("OpenCode server exited with code: " .. code)
      end
      M.server_job = nil
      M.is_ready = false
    end,
    on_stderr = function(_, data)
      -- Log stderr for debugging but don't show to user
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            vim.api.nvim_echo({{ "[doitforme debug] " .. line, "Comment" }}, false, {})
          end
        end
      end
    end,
  })

  if M.server_job <= 0 then
    util.error("Failed to start opencode server")
    M.server_job = nil
    return false
  end

  util.notify("Starting OpenCode server...")
  return true
end

---Wait for server to become ready
---@param callback fun(success: boolean)
function M.wait_for_ready(callback)
  local cfg = config.get()
  local timeout = cfg.server.startup_timeout
  local interval = 500
  local elapsed = 0

  local timer = vim.uv.new_timer()
  timer:start(0, interval, function()
    elapsed = elapsed + interval

    vim.schedule(function()
      M.health_check(function(healthy)
        if healthy then
          timer:stop()
          timer:close()
          M.is_ready = true
          util.notify("OpenCode server is ready")
          callback(true)
        elseif elapsed >= timeout then
          timer:stop()
          timer:close()
          util.error("Timeout waiting for OpenCode server to start")
          callback(false)
        end
      end)
    end)
  end)
end

---Ensure server is connected and ready
---@param callback fun(success: boolean)
function M.ensure_connected(callback)
  -- First, check if server is already running
  M.health_check(function(healthy)
    if healthy then
      M.is_ready = true
      callback(true)
      return
    end

    -- Server not running, try to start it if auto_start is enabled
    local cfg = config.get()
    if not cfg.server.auto_start then
      util.error("OpenCode server is not running. Start it with: opencode serve")
      callback(false)
      return
    end

    -- Spawn server and wait for it
    if M.spawn_server() then
      M.wait_for_ready(callback)
    else
      callback(false)
    end
  end)
end

---Create a new session
---@param callback fun(err: string|nil, session_id: string|nil)
function M.create_session(callback)
  local url = M.get_base_url() .. "/session"
  local body = {
    title = "doitforme-" .. os.date("%Y%m%d-%H%M%S"),
  }

  util.http_request("POST", url, body, function(err, response)
    if err then
      callback(err, nil)
      return
    end

    if response and response.id then
      M.session_id = response.id
      callback(nil, response.id)
    else
      callback("Invalid session response", nil)
    end
  end)
end

---Send a prompt to the current session
---@param session_id string Session ID
---@param prompt string The prompt text
---@param model? table Model specification { providerID, modelID }
---@param callback fun(err: string|nil, response: table|nil)
function M.send_prompt(session_id, prompt, model, callback)
  local url = M.get_base_url() .. "/session/" .. session_id .. "/prompt"

  local body = {
    parts = {
      { type = "text", text = prompt },
    },
  }

  if model then
    body.model = model
  end

  util.http_request("POST", url, body, callback)
end

---Abort a running session
---@param session_id string Session ID
---@param callback? fun(err: string|nil, success: boolean)
function M.abort_session(session_id, callback)
  local url = M.get_base_url() .. "/session/" .. session_id .. "/abort"

  util.http_request("POST", url, nil, function(err, response)
    if callback then
      callback(err, not err)
    end
  end)
end

---Cleanup server on plugin unload
function M.cleanup()
  if M.server_job then
    vim.fn.jobstop(M.server_job)
    M.server_job = nil
  end
  M.is_ready = false
  M.session_id = nil
end

return M
