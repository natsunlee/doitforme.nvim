# doitforme.nvim

A Neovim plugin for AI-powered code modification via [OpenCode](https://opencode.ai). Select code, describe what you want, and let AI modify just that selection.

## Features

- **Targeted modifications**: AI changes only the selected region (plus imports/references when needed)
- **Asynchronous execution**: Continue editing while AI processes your request
- **Visual feedback**: Animated spinner shows progress above/below the selection
- **Multiple concurrent tasks**: Submit prompts for different selections simultaneously
- **Conflict detection**: Warns if you edit the target region while AI is working
- **Optional review mode**: Preview changes in a diff before applying
- **Auto server management**: Automatically connects to or starts OpenCode server

## Requirements

- Neovim >= 0.9.4
- [snacks.nvim](https://github.com/folke/snacks.nvim) (for input UI)
- [OpenCode](https://opencode.ai) CLI installed and configured

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "natsunlee/doitforme.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = {
    { "<leader>ai", function() require("doitforme").prompt() end, mode = { "n", "v" }, desc = "AI Modify" },
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "natsunlee/doitforme.nvim",
  requires = { "folke/snacks.nvim" },
  config = function()
    require("doitforme").setup()
  end
}
```

## Usage

1. **Select code** in visual mode (or place cursor on a line)
2. **Trigger the plugin** with your keybind or `:DoItForMe`
3. **Type your instruction** in the popup (e.g., "add error handling", "convert to async/await")
4. **Continue editing** - AI works asynchronously with a spinner indicator
5. **Changes are applied** automatically when AI finishes

### Commands

| Command | Description |
|---------|-------------|
| `:DoItForMe` | Open AI prompt for selected code |
| `:DoItForMeCancel` | Cancel all active tasks for current buffer |
| `:DoItForMeStatus` | Show status of active tasks |
| `:DIFM` | Shorthand for `:DoItForMe` |

### Lua API

```lua
local doitforme = require("doitforme")

-- Open prompt for current selection/cursor line
doitforme.prompt()

-- Cancel all active tasks in current buffer
doitforme.cancel_all()

-- Cancel a specific task
doitforme.cancel(task_id)

-- Get list of active tasks
doitforme.tasks()

-- Show status of active tasks
doitforme.status()
```

## Configuration

```lua
require("doitforme").setup({
  -- Server settings
  server = {
    host = "127.0.0.1",      -- OpenCode server host
    port = 4096,              -- OpenCode server port
    auto_start = true,        -- Start server if not running
    startup_timeout = 10000,  -- Timeout for server startup (ms)
  },

  -- Context settings
  context = {
    include_full_file = true, -- Send entire file as context
    lines_before = 50,        -- Lines before selection (when not full file)
    lines_after = 50,         -- Lines after selection (when not full file)
  },

  -- Behavior settings
  behavior = {
    review_mode = false,      -- Show diff preview before applying
    warn_on_conflict = true,  -- Warn if selection modified during AI work
    cancel_on_conflict = false, -- Cancel task if selection modified
  },

  -- UI settings
  ui = {
    indicator = {
      spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      position = "above",     -- "above" or "below" selection
      hl_group = "Comment",   -- Highlight group for spinner
    },
    input = {
      prompt = "AI Prompt: ",
      border = "rounded",
    },
  },

  -- Model settings
  model = nil,  -- Use OpenCode default, or specify "provider/model"
})
```

### Example Configurations

#### Always review changes before applying

```lua
require("doitforme").setup({
  behavior = {
    review_mode = true,
  },
})
```

#### Use limited context window

```lua
require("doitforme").setup({
  context = {
    include_full_file = false,
    lines_before = 100,
    lines_after = 100,
  },
})
```

#### Use a specific model

```lua
require("doitforme").setup({
  model = "anthropic/claude-3-5-sonnet-20241022",
})
```

## How It Works

1. When you trigger the plugin, it captures your visual selection (or cursor line)
2. A snacks.nvim input prompt appears for your instruction
3. The plugin connects to OpenCode server (starting it if needed)
4. Your file content and selection are sent with a carefully crafted prompt
5. AI is instructed to modify only the selection (plus imports/references)
6. Changes are applied atomically once AI completes
7. A success/error indicator briefly appears

## Highlight Groups

| Group | Default | Description |
|-------|---------|-------------|
| `DoItForMeSpinner` | `Comment` | Spinner indicator |
| `DoItForMeSuccess` | `DiagnosticOk` | Success message |
| `DoItForMeError` | `DiagnosticError` | Error message |
| `DoItForMeWarning` | `DiagnosticWarn` | Warning message |

## License

Apache-2.0
