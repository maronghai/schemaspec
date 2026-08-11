; ── Rune Schema Language — Treesitter Folds ──────────────────
;
; Define foldable regions for .ss files.

; ── Table blocks ─────────────────────────────────────────────

(table_declaration) @fold

; ── View declarations ────────────────────────────────────────

(view_declaration) @fold

; ── Conditional blocks ───────────────────────────────────────

(conditional_if) @fold
(conditional_end) @fold

; ── Comments ─────────────────────────────────────────────────

(comment) @fold
