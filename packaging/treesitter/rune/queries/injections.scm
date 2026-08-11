; ── Rune Schema Language — Treesitter Injections ─────────────
;
; Inject SQL highlighting into view query text.

; ── SQL in view queries ──────────────────────────────────────

(view_declaration
  query: (sql_text) @injection.content
  (#set! injection.language "sql"))
