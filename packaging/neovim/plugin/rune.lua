-- plugin/rune.lua
-- Neovim plugin entry point for Rune schema language support.
-- Provides LSP integration for .ss files via the `rune lsp` server.
--
-- Installation:
--   lazy.nvim: { "rune-lang/rune", ft = "ss" }
--   packer.nvim: use { "rune-lang/rune", ft = "ss" }
--   Manual: clone and add to runtimepath

if vim.g.loaded_rune then
  return
end
vim.g.loaded_rune = true

local ok, rune = pcall(require, "rune")
if ok then
  rune.setup()
end
