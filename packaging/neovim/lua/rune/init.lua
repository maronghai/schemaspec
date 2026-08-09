-- lua/rune/init.lua
-- Rune LSP client and keybindings for Neovim.
--
-- Usage:
--   require("rune").setup({
--     cmd = { "rune", "lsp" },  -- custom binary path
--     diagnostics = true,         -- enable diagnostics
--   })

local M = {}

-- Default configuration
M.config = {
  -- Command to start the LSP server
  cmd = { "rune", "lsp" },
  -- File types associated with Rune
  filetypes = { "ss" },
  -- Root directory markers
  root_markers = { ".git", "rune.toml", "schema.ss" },
  -- Enable real-time diagnostics
  diagnostics = true,
  -- Enable keybindings
  keybindings = true,
  -- Custom keybinding prefix (false to disable)
  keymap_prefix = "<leader>",
}

-- Setup the Rune LSP client
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Check if vim.lsp.config is available (Neovim 0.11+)
  if vim.lsp and vim.lsp.config then
    M.setup_lsp_config()
  else
    -- Fallback for older Neovim versions
    M.setup_lspconfig()
  end

  -- Set up keybindings
  if M.config.keybindings then
    M.setup_keybindings()
  end

  -- Add generate command
  M.setup_commands()
end

-- Modern Neovim LSP setup (0.11+)
function M.setup_lsp_config()
  vim.lsp.config("rune_ls", {
    cmd = M.config.cmd,
    filetypes = M.config.filetypes,
    root_markers = M.config.root_markers,
  })

  vim.lsp.enable("rune_ls")
end

-- Fallback LSP setup via lspconfig
function M.setup_lspconfig()
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    vim.notify("rune: lspconfig not found, LSP features disabled", vim.log.levels.WARN)
    return
  end

  lspconfig.rune_ls.setup({
    cmd = M.config.cmd,
    filetypes = M.config.filetypes,
    root_dir = lspconfig.util.root_pattern(unpack(M.config.root_markers)),
  })
end

-- Set up keybindings for .ss files
function M.setup_keybindings()
  local buf = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = true,
      desc = "Rune: " .. desc,
      silent = true,
    })
  end

  -- Navigation
  buf("n", "gd", vim.lsp.buf.definition, "Go to definition")
  buf("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
  buf("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
  buf("n", "gr", vim.lsp.buf.references, "Find references")

  -- Information
  buf("n", "K", vim.lsp.buf.hover, "Hover documentation")
  buf("n", "<C-k>", vim.lsp.buf.signature_help, "Signature help")

  -- Refactoring
  buf("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
  buf("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")

  -- Diagnostics
  buf("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
  buf("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
  buf("n", "<leader>d", vim.diagnostic.open_float, "Show diagnostic")

  -- Formatting
  buf("n", "<leader>f", function()
    vim.lsp.buf.format({ async = true })
  end, "Format document")
end

-- Set up custom commands
function M.setup_commands()
  -- Generate SQL from current schema
  vim.api.nvim_create_user_command("RuneGenerate", function(opts)
    local args = opts.fargs
    local dialect = args[1] or "mysql"
    local cmd = { "rune", vim.fn.expand("%:p"), "-d", dialect }
    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify("rune generate failed:\n" .. table.concat(output, "\n"), vim.log.levels.ERROR)
      return
    end
    -- Write output to a split
    vim.cmd("vnew")
    vim.bo.filetype = "sql"
    vim.api.nvim_put(output, "l", true, true)
  end, {
    nargs = "?",
    complete = function()
      return { "mysql", "pg", "sqlite", "mssql", "oracle", "db2" }
    end,
    desc = "Rune: Generate SQL from current schema",
  })

  -- Validate current schema
  vim.api.nvim_create_user_command("RuneValidate", function()
    local cmd = { "rune", "validate", vim.fn.expand("%:p") }
    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify("Schema validation failed:\n" .. table.concat(output, "\n"), vim.log.levels.ERROR)
    else
      vim.notify("Schema is valid!", vim.log.levels.INFO)
    end
  end, { desc = "Rune: Validate current schema" })

  -- Lint current schema
  vim.api.nvim_create_user_command("RuneLint", function()
    local cmd = { "rune", "lint", vim.fn.expand("%:p") }
    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify("Lint issues found:\n" .. table.concat(output, "\n"), vim.log.levels.WARN)
    else
      vim.notify("No lint issues!", vim.log.levels.INFO)
    end
  end, { desc = "Rune: Lint current schema" })
end

return M
