---Prompt and context building for doitforme.nvim
local config = require("doitforme.config")
local util = require("doitforme.util")

local M = {}

---Build the system context for the AI prompt
---@param task doitforme.Task The task to build prompt for
---@return string The full prompt to send to OpenCode
function M.build_prompt(task)
  local cfg = config.get()
  local bufnr = task.bufnr

  -- Get file info
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local filetype = vim.bo[bufnr].filetype

  -- Get file content based on config
  local file_content
  local context_info

  if cfg.context.include_full_file then
    file_content = util.get_buffer_text(bufnr)
    context_info = "Full file content provided"
  else
    -- Get context lines before and after selection
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    local context_start = math.max(1, task.selection.start_line - cfg.context.lines_before)
    local context_end = math.min(total_lines, task.selection.end_line + cfg.context.lines_after)
    file_content = util.get_buffer_text(bufnr, context_start, context_end)
    context_info = string.format("Lines %d-%d (context window)", context_start, context_end)
  end

  -- Build the prompt
  local prompt_parts = {
    "You are an expert code assistant helping to modify a specific section of code.",
    "",
    "## File Information",
    string.format("- **Filename**: %s", filename),
    string.format("- **Filepath**: %s", filepath),
    string.format("- **Language**: %s", filetype ~= "" and filetype or "unknown"),
    string.format("- **Context**: %s", context_info),
    "",
    "## Important Instructions",
    "",
    "1. **Focus on the selected region**: The user has selected lines " ..
      task.selection.start_line .. "-" .. task.selection.end_line .. ". " ..
      "Your primary task is to modify ONLY this selected region based on the user's instruction.",
    "",
    "2. **Allowed modifications outside selection**:",
    "   - You MAY add or update import/require statements at the top of the file if your changes require new dependencies",
    "   - You MAY update references to renamed variables, functions, or types elsewhere in the file",
    "   - You MUST NOT make any other changes outside the selected region",
    "",
    "3. **Response format**:",
    "   - Respond with ONLY the replacement code for the selected region (lines " ..
      task.selection.start_line .. "-" .. task.selection.end_line .. ")",
    "   - Do NOT include line numbers",
    "   - Do NOT include markdown code fences",
    "   - Do NOT include explanations - just the code",
    "   - If imports need to be added, include them as a comment at the very start: `-- IMPORTS: import x from 'y'`",
    "",
    "## File Content",
    "",
    "```" .. filetype,
    file_content,
    "```",
    "",
    "## Selected Region (Lines " .. task.selection.start_line .. "-" .. task.selection.end_line .. ")",
    "",
    "```" .. filetype,
    task.original_content,
    "```",
    "",
    "## User Instruction",
    "",
    task.prompt,
  }

  return table.concat(prompt_parts, "\n")
end

---Parse AI response to extract code and any import statements
---@param response string AI response text
---@return string code The code to insert
---@return string|nil imports Import statements to add (if any)
function M.parse_response(response)
  if not response or response == "" then
    return "", nil
  end

  -- Clean up response - remove markdown code fences if present
  local code = response

  -- Remove leading/trailing code fences
  code = code:gsub("^```[%w]*\n?", "")
  code = code:gsub("\n?```$", "")

  -- Check for import comments at the start
  local imports = nil
  local import_pattern = "^%-%-%s*IMPORTS:%s*(.-)[\n\r]"
  local import_match = code:match(import_pattern)

  if import_match then
    imports = import_match
    code = code:gsub(import_pattern, "")
  end

  -- Also check for other common import comment formats
  if not imports then
    import_pattern = "^//%s*IMPORTS:%s*(.-)[\n\r]"
    import_match = code:match(import_pattern)
    if import_match then
      imports = import_match
      code = code:gsub(import_pattern, "")
    end
  end

  -- Trim leading/trailing whitespace but preserve internal structure
  code = code:gsub("^[\n\r]+", ""):gsub("[\n\r]+$", "")

  return code, imports
end

---Extract the actual code content from assistant message parts
---@param response table OpenCode API response
---@return string|nil code The extracted code, or nil if not found
function M.extract_code_from_response(response)
  -- Response structure from OpenCode: { info: Message, parts: Part[] }
  if not response then
    return nil
  end

  -- Handle direct response format
  if type(response) == "string" then
    return response
  end

  -- Handle structured response
  local parts = response.parts or response

  if type(parts) ~= "table" then
    return nil
  end

  -- Look for text parts in the response
  local text_parts = {}

  for _, part in ipairs(parts) do
    if part.type == "text" and part.text then
      table.insert(text_parts, part.text)
    end
  end

  if #text_parts > 0 then
    return table.concat(text_parts, "\n")
  end

  return nil
end

return M
