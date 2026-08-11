# Treesitter Grammar for Rune `.ss` Files

Treesitter grammar for syntax highlighting and code intelligence in Rune schema files.

## Supported Editors

- **Neovim** (via `nvim-treesitter`)
- **Helix** (built-in Treesitter support)
- **Zed** (built-in Treesitter support)
- **Any editor with Treesitter support**

## Installation

### Neovim (nvim-treesitter)

Add this grammar to your `nvim-treesitter` configuration:

```lua
-- In your treesitter config:
require("nvim-treesitter.install").define_grammar("rune", {
  install_info = {
    url = "https://github.com/rune-lang/tree-sitter-rune",
    branch = "main",
    files = { "src/parser.c", "src/scanner.c" },
  },
  filetype = "ss",
})
```

Or manually install from this directory:

```bash
cd packaging/treesitter/rune
tree-sitter generate
tree-sitter build
# Copy to nvim-treesitter directory
```

### Helix

Copy the `queries/` directory to your Helix runtime:

```bash
cp -r queries/* ~/.config/helix/runtime/queries/rune/
```

Then add to `~/.config/helix/languages.toml`:

```toml
[[language]]
name = "rune"
source = { git = "https://github.com/rune-lang/tree-sitter-rune" }
file-types = ["ss"]
```

### Zed

Add to your Zed `settings.json`:

```json
{
  "languages": {
    "Rune": {
      "file_types": ["ss"],
      "grammar": "rune"
    }
  }
}
```

## Building

Requires [tree-sitter CLI](https://tree-sitter.github.io/tree-sitter/):

```bash
cd packaging/treesitter/rune
tree-sitter generate
tree-sitter test
```

## Highlight Groups

The grammar defines highlight groups for:

| Element | Highlight Group |
|---------|----------------|
| `$` `#` `%` `~` `&` `>` `@` `!` `+` `...` | `@keyword` |
| `@if` `@endif` `@import` `@version` | `@keyword` |
| Field modifiers (`!` `?` `+` `++` `@` `@u`) | `@keyword.modifier` |
| Type symbols (`n` `N` `i` `s` etc.) | `@type.builtin` |
| Custom types (`~name`) | `@type.definition` |
| Table names | `@type` |
| Field names | `@variable` |
| Default values (`NULL` `CURRENT_TIMESTAMP`) | `@constant.builtin` |
| Strings | `@string` |
| Numbers | `@number` |
| Comments (`--` `;`) | `@comment` |
| Operators (`=`) | `@operator` |
| SQL in views | `@string.special` |

## File Type

Associated file extension: `.ss`
