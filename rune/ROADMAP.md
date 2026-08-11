# Rune Roadmap

## v0.258.0 (2026-08-12) ✅

- Pipeline boundary cleanup: move `compileSqlToAst` from forward.zig to diff.zig
- Allocator consistency: fix page_allocator usage in diagnostic/format.zig and pipeline/stats.zig
- Dead code removal: remove unused mmap code from io.zig

## v0.259.0 (planned)

- Add `--show-rules` flag for `rune lint` to list all available rules with descriptions and fixability
- Add `--init` flag for `rune lint` to generate starter `.rune-lint.toml` config file
- Add `validate_unused_enums` semantic pass (detect unused custom type definitions)

## v0.260.0 (planned)

- Config double-parsing optimization: merge `warnUnknownKeys` + `parseConfig` into single pass
- `generators/common.zig` deduplication: consolidate `hasAnyEnums`/`hasAnyCompositeFks` scans
- Add colocated tests for `diff/plan.zig` (572 lines, no test coverage)

## Future

- LSP: workspace-wide schema validation
- LSP: cross-file rename support
- WASM: add colocated test coverage for wasm/ sub-modules
- Performance: arena allocator batching for hot paths (diff output, lint output)
