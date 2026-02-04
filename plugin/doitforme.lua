-- doitforme.nvim plugin loader
-- Registers user commands for the plugin

if vim.g.loaded_doitforme then
  return
end
vim.g.loaded_doitforme = true

-- User Commands

-- Main command to prompt AI
vim.api.nvim_create_user_command("DoItForMe", function(opts)
  local doitforme = require("doitforme")

  -- If called with a range (visual selection), the marks will be set
  if opts.range == 2 then
    -- Visual mode selection - marks are automatically set
    doitforme.prompt()
  else
    -- Normal mode - use cursor line
    doitforme.prompt()
  end
end, {
  range = true,
  desc = "Open AI prompt to modify selected code",
})

-- Cancel all active tasks for current buffer
vim.api.nvim_create_user_command("DoItForMeCancel", function()
  require("doitforme").cancel_all()
end, {
  desc = "Cancel all active AI tasks for current buffer",
})

-- Show status of active tasks
vim.api.nvim_create_user_command("DoItForMeStatus", function()
  require("doitforme").status()
end, {
  desc = "Show status of active AI tasks",
})

-- Shorthand aliases
vim.api.nvim_create_user_command("DIFM", function(opts)
  vim.cmd(opts.range == 2 and "'<,'>DoItForMe" or "DoItForMe")
end, {
  range = true,
  desc = "Shorthand for DoItForMe",
})
