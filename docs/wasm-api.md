# Rune WASM API Contract

The WASM build (`rune.wasm`, produced by `zig build -Dtarget=wasm32-wasi`) exposes the
compiler as a flat C ABI. This document is the stability contract for consumers:
[playground/index.html](../playground/index.html), the JS wrapper
[rune/wasm/rune.js](../rune/wasm/rune.js), and any third-party Web/Deno integration.

Source of truth: `rune/src/wasm.zig` + `rune/src/wasm/*.zig`. Any signature or semantic
change there must be reflected here and in `rune/wasm/rune.js` in the same release.

---

## Loading Model

- The module is a wasm32-wasi executable with `.entry = .disabled` and `-rdynamic`;
  exports survive GC because of the latter (unreferenced `export fn`s are otherwise stripped).
- Hosts need only a minimal WASI stub (`wasi_snapshot_preview1`): entropy + clocks.
  Everything else can return ENOSYS — the compiler pipelines touch nothing else
  (see `rune/wasm/rune.js` for a working stub).
- Load path: browser uses `fetch(WASM_PATH)`; Deno reads the file. Both instantiate via
  `WebAssembly.instantiate`.

## Memory Protocol

1. Call `rune_wasm_alloc(len)` → pointer into module-managed arena memory.
2. Write your input string (UTF-8, no NUL needed) into that buffer with `Uint8Array`.
3. Call the desired `rune_*` function passing `(ptr, len)` pairs.
4. **Copy** the returned string out before any further call: results live in the same
   arena and are invalidated by the next call or `rune_reset()`.
5. There is no per-string free — memory is reclaimed wholesale by `rune_reset()`.

## Calling Convention

All schema-taking functions share this shape:

```
?[*:0]const u8 rune_X(input_ptr, input_len, options_ptr, options_len)
```

- Returns a pointer to a NUL-terminated result string, or **null on error**
  (then consult `rune_last_error()` / `rune_last_error_code()`).
- `options` is a plain space-separated `"key=value"` string, e.g. `"dialect=pg"`.
  Empty string is always valid; every key has a default.

## Error Model

| Export | Returns | Meaning |
|--------|---------|---------|
| `rune_last_error() -> ?[*:0]const u8` | last error message | null when the last operation succeeded (or after reset) |
| `rune_last_error_code() -> i32` | numeric code | see table below |

| Code | Class |
|------|-------|
| 0 | success |
| 1 | syntax / parse error |
| 2 | type error |
| 3 | FK error |
| 4 | semantic / diagnostic error |
| 5 | unknown error |

Note: `rune_compile` on a semantically-invalid schema surfaces the full diagnostics as a
validate-style JSON report inside `rune_last_error()` (stderr printing is compiled out on
wasm32). `rune_validate` itself never returns null for invalid schemas — it reports
`"valid":false` in its JSON instead.

---

## Exports (17)

### Memory & lifecycle

| Export | Signature | Notes |
|--------|-----------|-------|
| `rune_wasm_alloc` | `(len) -> ?[*]u8` | arena-backed caller buffer; len=0 yields a valid 1-byte buffer |
| `rune_reset` | `() -> void` | clears error state + reclaims all arena memory (retains capacity) |

### Introspection

| Export | Signature | Notes |
|--------|-----------|-------|
| `rune_version` | `() -> ?[*:0]const u8` | e.g. `"0.326.0"` |

### Compile pipeline

| Export | Options keys | Result | Notes |
|--------|-------------|--------|-------|
| `rune_compile` | `dialect=` | SQL DDL text | forward pipeline: tokenizer → parser → semantic → type resolve → codegen |
| `rune_validate` | `dialect=` | JSON report | `{ "valid": bool, "error_count": n, ...stats }`; never null on DiagnosticsError |
| `rune_stats` | `dialect=` | JSON stats | table/field/view/constraint counts |

`dialect=` accepts `mysql` (default), `pg`, `sqlite`, `mssql`, `oracle`, `db2`.

### Diff family (two schemas)

```
?[*:0]const u8 rune_diff(schema1_ptr, len1, schema2_ptr, len2, options_ptr, options_len)
?[*:0]const u8 rune_migrate(schema1_ptr, len1, schema2_ptr, len2, options_ptr, options_len)
```

| Export | Options keys | Result | Notes |
|--------|-------------|--------|-------|
| `rune_diff` | `dialect=`, `format=` (`text` default / `json`) | diff report | human-readable ALTER comments or structured JSON |
| `rune_migrate` | `dialect=`, `rollback` (presence = true) | migration SQL | `rollback` emits the down-migration instead |

### Utilities

| Export | Options keys | Result | Notes |
|--------|-------------|--------|-------|
| `rune_lint` | `dialect=`, `format=json` | lint findings (text or JSON) | presence-check on `format`, not value compare beyond `json` |
| `rune_format` | *(ignored)* | formatted `.ss` source | canonical formatter output |
| `rune_tune` | *(ignored)* | `.ss` with templates extracted | common fields hoisted into `%` templates |
| `rune_docs` | `dialect=` | Markdown documentation | per-table docs from the schema |
| `rune_export` | `format=` (`json` default / `text` / `markdown`) | structured export | machine-readable schema dump |
| `rune_generate` | `dialect=`, `generator=<name>` | generated artifact | generator name required; unknown name → error via `rune_last_error` |
| `rune_reverse` | `dialect=`, `templates` (presence = true) | `.ss` source | input is SQL DDL, not `.ss`; `templates` enables template extraction |

---

## JS Wrapper Surface (rune/wasm/rune.js)

The wrapper maps snake_case exports to camelCase async functions with automatic
memory staging (alloc/write/copy/reset handled internally):

| JS function | Backing export |
|-------------|----------------|
| `compile(schema, { dialect })` | `rune_compile` |
| `validate(schema, { dialect })` | `rune_validate` |
| `stats(schema, { dialect })` | `rune_stats` |
| `diff(oldSchema, newSchema, opts)` | `rune_diff` |
| `migrate(oldSchema, newSchema, opts)` | `rune_migrate` |
| `lint(schema, opts)` | `rune_lint` |
| `format(schema)` | `rune_format` |
| `tune(schema)` | `rune_tune` |
| `generate(schema, generator, opts)` | `rune_generate` |
| `exportJson(schema, { format })` | `rune_export` |
| `docs(schema, { dialect })` | `rune_docs` |
| `reverse(sql, opts)` | `rune_reverse` |
| `version()` | `rune_version` |
| `reset()` | `rune_reset` |

Errors are thrown as JS exceptions carrying the message from `rune_last_error()`.

## Stability Rules

1. Existing exports are never removed or re-signatured within a minor version.
2. New options keys must default to current behavior when absent (empty options string
   is forever valid).
3. Adding an export requires: implementation in `rune/src/wasm/<module>.zig`, a wrapper
   in `rune/wasm/rune.js`, a row here, and a unit test colocated with the export.
4. The playground depends only on this contract plus the file layout
   (`playground/index.html` + `../rune/wasm/rune.js` + `../rune/zig-out/bin/rune.wasm`);
   that relative layout is load-bearing for the GitHub Pages deploy tree.
