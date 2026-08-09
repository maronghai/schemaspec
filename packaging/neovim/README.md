# Rune for Neovim

LSP-powered schema language support for `.ss` files in Neovim.

## Features

- **LSP Integration** — Real-time diagnostics, completion, hover, go-to-definition, rename
- **Keybindings** — Standard LSP keybindings (`gd`, `K`, `<leader>rn`, etc.)
- **Commands** — `RuneGenerate`, `RuneValidate`, `RuneLint`
- **Zero Dependencies** — Uses Neovim's built-in LSP client (no lspconfig required)

## Installation

### lazy.nvim

```lua
{
  "rune-lang/rune",
  ft = "ss",
  config = function()
    require("rune").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "rune-lang/rune",
  ft = "ss",
  config = function()
    require("rune").setup()
  end,
}
```

### Manual

```bash
git clone https://github.com/rune-lang/rune.git
cd rune/packaging/neovim
```

Add to your Neovim config:

```lua
vim.opt.rtp:prepend("/path/to/rune/packaging/neovim")
require("rune").setup()
```

## Configuration

```lua
require("rune").setup({
  -- Custom binary path (default: { "rune", "lsp" })
  cmd = { "/usr/local/bin/rune", "lsp" },

  -- Enable real-time diagnostics (default: true)
  diagnostics = true,

  -- Enable keybindings (default: true)
  keybindings = true,
})
```

## Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `gd` | n | Go to definition |
| `gD` | n | Go to declaration |
| `gi` | n | Go to implementation |
| `gr` | n | Find references |
| `K` | n | Hover documentation |
| `<C-k>` | n | Signature help |
| `<leader>rn` | n | Rename symbol |
| `<leader>ca` | n | Code action |
| `[d` | n | Previous diagnostic |
| `]d` | n | Next diagnostic |
| `<leader>d` | n | Show diagnostic float |
| `<leader>f` | n | Format document |

## Commands

| Command | Description |
|---------|-------------|
| `:RuneGenerate [dialect]` | Generate SQL from current schema (default: mysql) |
| `:RuneValidate` | Validate current schema |
| `:RuneLint` | Lint current schema for quality issues |

## Requirements

- Neovim 0.9+ (for built-in LSP)
- `rune` binary in PATH (see [installation](https://github.com/rune-lang/rune#installation))
