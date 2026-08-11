; ── Rune Schema Language — Treesitter Highlights ──────────────
;
; Mappings follow Neovim / Helix conventions.
; Attach via: vim.treesitter.language.add("rune", { ... })
; or via tree-sitter CLI for highlighting.

; ── Comments ─────────────────────────────────────────────────

(comment) @comment

; ── Keywords ─────────────────────────────────────────────────

(schema_declaration
  "$" @keyword)

(type_definition
  "~" @keyword)

(template_declaration
  "%" @keyword)

(table_declaration
  "#" @keyword)

(view_declaration
  "&" @keyword)

(conditional_if
  "@if" @keyword
  "dialect" @keyword
  "=" @operator)

(conditional_end
  "@endif" @keyword)

(import_directive
  "@import" @keyword)

(version_directive
  "@version" @keyword)

(doc_directive
  "+" @keyword)

(fk_declaration
  ">" @keyword)

(index_declaration
  "@" @keyword)

(composite_pk
  "!" @keyword)

(slot_marker
  "..." @keyword)

; ── Identifiers ──────────────────────────────────────────────

(schema_declaration
  (identifier) @type)

(type_definition
  name: (identifier) @type.definition)

(template_declaration
  name: (identifier) @type.definition)

(table_declaration
  name: (identifier) @type)

(table_declaration
  template_ref: (identifier) @type.builtin)

(view_declaration
  name: (identifier) @type)

(import_directive
  path: (identifier) @string)

(version_directive
  version: (number) @number)

; ── Type Symbols ─────────────────────────────────────────────

(simple_type) @type.builtin
(int_type) @type.builtin
(decimal_type) @type.builtin
(varchar_type) @type.builtin
(enum_type) @type.builtin
(passthrough_type) @type)

; ── Modifiers ────────────────────────────────────────────────

(auto_increment_pk) @keyword.modifier
(auto_increment) @keyword.modifier
(primary_key) @keyword.modifier
(nullable) @keyword.modifier
(unique_index) @keyword.modifier
(index) @keyword.modifier

; ── Operators ────────────────────────────────────────────────

"=" @operator

; ── Default Values ───────────────────────────────────────────

(default_null) @constant.builtin
(default_current_timestamp) @constant.builtin

; ── Numbers ──────────────────────────────────────────────────

(numeric) @number
(int_type) @number

; ── Strings ──────────────────────────────────────────────────

(string) @string

; ── Field Names ──────────────────────────────────────────────

(field_declaration
  name: (identifier) @variable)

; ── Dialect Overrides ────────────────────────────────────────

(dialect_override
  dialect: (identifier) @label)

; ── Table References ─────────────────────────────────────────

(fk_declaration
  table: (identifier) @type)

(table_declaration
  view: (identifier) @type)

; ── Enum Values ──────────────────────────────────────────────

(enum_type
  (string) @string)

; ── SQL Content ──────────────────────────────────────────────

(view_declaration
  query: (sql_text) @string.special)

; ── Check Constraints ────────────────────────────────────────

(range_check) @punctuation.bracket
(in_list_check) @punctuation.bracket
(comparison_check) @punctuation.bracket

; ── Punctuation ──────────────────────────────────────────────

"," @punctuation.delimiter
"." @punctuation.delimiter
"(" @punctuation.bracket
")" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"^" @punctuation
