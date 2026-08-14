// Test module index — imports colocated test files so zig build test discovers them.
// ─── Section comments group tests by module for easy navigation. ────────────

comptime {
    // ── ast_visitor ──────────────────────────────────────────────
    _ = @import("ast_visitor_test.zig");
    // ── bench ────────────────────────────────────────────────────
    _ = @import("bench_test.zig");
    // ── cli ──────────────────────────────────────────────────────
    _ = @import("cli_test.zig");
    _ = @import("cli/lint_cmd_test.zig");
    _ = @import("cli/init_test.zig");
    _ = @import("cli/parse_test.zig");
    _ = @import("cli/types_test.zig");
    _ = @import("cli/errors.zig");
    _ = @import("cli/flag_registry.zig");
    _ = @import("cli/hooks_test.zig");
    // ── color ────────────────────────────────────────────────────
    _ = @import("color_test.zig");
    // ── completions ──────────────────────────────────────────────
    _ = @import("completions_test.zig");
    // ── config ───────────────────────────────────────────────────
    _ = @import("config.zig");
    _ = @import("config_merge.zig");
    _ = @import("diagnostic/format.zig");
    // ── codegen ──────────────────────────────────────────────────
    _ = @import("codegen/codegen_test.zig");
    _ = @import("codegen/columns_test.zig");
    _ = @import("codegen/indexes_test.zig");
    _ = @import("codegen/interleave.zig");
    _ = @import("codegen/streaming_test.zig");
    _ = @import("codegen/parallel.zig");
    _ = @import("codegen/deps.zig");
    _ = @import("golden_test.zig");
    // ── dialect ──────────────────────────────────────────────────
    _ = @import("dialect/dialect_test.zig");
    _ = @import("dialect/common_test.zig");
    _ = @import("dialect/enum_test.zig");
    _ = @import("dialect/mysql_test.zig");
    _ = @import("dialect/pg_test.zig");
    _ = @import("dialect/sqlite_test.zig");
    _ = @import("dialect/mssql_test.zig");
    _ = @import("dialect/oracle_test.zig");
    _ = @import("dialect/db2_test.zig");
    _ = @import("dialect/sqlite_hints_test.zig");
    // ── diff ─────────────────────────────────────────────────────
    _ = @import("diff/diff_test.zig");
    _ = @import("diff/engine_test.zig");
    _ = @import("diff/fields_test.zig");
    _ = @import("diff/fks_test.zig");
    _ = @import("diff/indexes_test.zig");
    _ = @import("diff/semantic_test.zig");
    _ = @import("diff/migrate_test.zig");
    _ = @import("diff/migrate_json_test.zig");
    _ = @import("diff/migrate_graph_test.zig");
    _ = @import("diff/types_test.zig");
    _ = @import("diff/rename_test.zig");
    _ = @import("diff/plan.zig");
    _ = @import("diff/format/text_test.zig");
    _ = @import("diff/format/sarif_test.zig");
    _ = @import("diff/format/json_test.zig");
    _ = @import("diff/format/markdown_test.zig");
    // ── formatter ────────────────────────────────────────────────
    _ = @import("formatter_test.zig");
    // ── io ───────────────────────────────────────────────────────
    _ = @import("io_test.zig");
    // ── watch ────────────────────────────────────────────────────
    _ = @import("watch_test.zig");
    // ── generators ───────────────────────────────────────────────
    _ = @import("generators/json_schema_test.zig");
    _ = @import("generators/common_test.zig");
    _ = @import("generators/sql_ddl_test.zig");
    _ = @import("generators/prisma_test.zig");
    _ = @import("generators/docs_test.zig");
    _ = @import("generators/drizzle_test.zig");
    _ = @import("generators/typeorm_test.zig");
    _ = @import("generators/sqlalchemy_test.zig");
    _ = @import("generators/knex_test.zig");
    _ = @import("generators/openapi_test.zig");
    _ = @import("generators/graphql_test.zig");
    _ = @import("generators/pydantic_test.zig");
    _ = @import("generators/symbol_index_test.zig");
    _ = @import("generators/common_check_test.zig");
    _ = @import("generators/common_defaults_test.zig");
    _ = @import("generator_test.zig");
    // ── lint ─────────────────────────────────────────────────────
    _ = @import("lint/rules_structural_test.zig");
    _ = @import("lint/rules_naming_test.zig");
    _ = @import("lint/rules_validation_test.zig");
    _ = @import("lint/rules_fk_test.zig");
    _ = @import("lint/rules_compat_test.zig");
    _ = @import("lint/rules_index_test.zig");
    _ = @import("lint/rules_view_enum_test.zig");
    _ = @import("lint/format_test.zig");
    _ = @import("lint/config_test.zig");
    _ = @import("lint/fix.zig");
    _ = @import("lint/fix_helpers.zig");
    _ = @import("lint/fix_index.zig");
    _ = @import("lint/fix_modifier.zig");
    _ = @import("lint/fix_structural.zig");
    // ── parser ───────────────────────────────────────────────────
    _ = @import("parser/tokenizer_test.zig");
    _ = @import("parser/parser_test.zig");
    _ = @import("parser/parse_check_test.zig");
    _ = @import("parser/parse_fk_test.zig");
    _ = @import("parser/parse_index_test.zig");
    _ = @import("parser/parse_recovery_test.zig");
    _ = @import("parser/parse_table_test.zig");
    _ = @import("parser/parse_template_test.zig");
    _ = @import("parser/sql_parser_test.zig");
    _ = @import("parser/sql_parser_helpers_test.zig");
    // ── pipeline ─────────────────────────────────────────────────
    _ = @import("pipeline/diff_test.zig");
    _ = @import("pipeline/forward_test.zig");
    _ = @import("pipeline/handlers_test.zig");
    _ = @import("pipeline/generate.zig");
    _ = @import("pipeline/compile_helper.zig");
    _ = @import("pipeline/validation.zig");
    _ = @import("pipeline/validation_test.zig");
    _ = @import("pipeline/import_resolver_test.zig");
    _ = @import("pipeline/stats_test.zig");
    _ = @import("pipeline/audit.zig");
    _ = @import("pipeline/reverse_test.zig");
    _ = @import("pipeline/export.zig");
    _ = @import("pipeline/migrate_test.zig");
    // ── reverse ──────────────────────────────────────────────────
    _ = @import("reverse/map_test.zig");
    _ = @import("reverse/column_test.zig");
    _ = @import("reverse/check_test.zig");
    _ = @import("reverse/codegen_test.zig");
    _ = @import("reverse/dialect_detect_test.zig");
    _ = @import("reverse/fk_test.zig");
    _ = @import("reverse/template_extraction_test.zig");
    // ── semantic ─────────────────────────────────────────────────
    _ = @import("semantic/analyzer_test.zig");
    _ = @import("diagnostic_test.zig");
    _ = @import("semantic/pass_manager_test.zig");
    _ = @import("semantic/template_test.zig");
    _ = @import("semantic/pass/validate_duplicates.zig");
    _ = @import("semantic/pass/validate_circular_fk.zig");
    _ = @import("semantic/pass/validate_fk_targets.zig");
    _ = @import("semantic/pass/validate_unused_templates.zig");
    _ = @import("semantic/pass/validate_index_names.zig");
    _ = @import("semantic/pass/autofk.zig");
    _ = @import("semantic/pass/resolve_names.zig");
    _ = @import("semantic/pass/resolve_conditionals.zig");
    _ = @import("semantic/pass/suffix_inference.zig");
    _ = @import("semantic/pass/validate.zig");
    _ = @import("semantic/pass/validate_indexes.zig");
    _ = @import("semantic/pass/validate_type_modifiers.zig");
    _ = @import("semantic/pass/validate_template_types.zig");
    _ = @import("semantic/pass/validate_fk_types.zig");
    _ = @import("semantic/pass/validate_views.zig");
    _ = @import("semantic/pass/template_type_conflict.zig");
    _ = @import("semantic/pass/validate_unused_enums.zig");
    // ── types ────────────────────────────────────────────────────
    _ = @import("types/ast_test.zig");
    _ = @import("types/ir_version.zig");
    _ = @import("types/type_resolver_test.zig");
    _ = @import("types/type_registry_test.zig");
    _ = @import("types/sql_type_test.zig");
    _ = @import("types/symbol_table_test.zig");
    _ = @import("types/typed_ast_test.zig");
    _ = @import("types/resolved_ast_test.zig");
    // ── utils ────────────────────────────────────────────────────
    _ = @import("utils_test.zig");
    _ = @import("utils/edit_distance_test.zig");
    // ── version ──────────────────────────────────────────────────
    _ = @import("version.zig");
    // ── tune ─────────────────────────────────────────────────────
    _ = @import("tune.zig");
    // ── lsp ──────────────────────────────────────────────────────
    _ = @import("lsp/protocol.zig");
    _ = @import("lsp/protocol_test.zig");
    _ = @import("lsp/server.zig");
    _ = @import("lsp/hover.zig");
    _ = @import("lsp/go_to_definition.zig");
    _ = @import("lsp/go_to_definition_test.zig");
    _ = @import("lsp/completions.zig");
    _ = @import("lsp/document_symbols.zig");
    _ = @import("lsp/code_actions.zig");
    _ = @import("lsp/compile_service.zig");
    _ = @import("lsp/documents.zig");
    _ = @import("lsp/references.zig");
    _ = @import("lsp/highlights.zig");
    _ = @import("lsp/workspace_symbol.zig");
    _ = @import("lsp/signature_help.zig");
    _ = @import("lsp/json.zig");
    _ = @import("lsp/message.zig");
    _ = @import("lsp/features_test.zig");
    _ = @import("lsp/folding_range.zig");
    _ = @import("lsp/folding_range_test.zig");
    _ = @import("lsp/type_definition.zig");
    _ = @import("lsp/type_definition_test.zig");
    _ = @import("lsp/inlay_hints.zig");
    _ = @import("lsp/inlay_hints_test.zig");
    _ = @import("lsp/helpers_test.zig");
    _ = @import("lsp/handlers_test.zig");
    _ = @import("lsp/handlers.zig");
    _ = @import("lsp/code_lens.zig");
    _ = @import("lsp/rename.zig");
    _ = @import("lsp/rename_test.zig");
    _ = @import("lsp/references_test.zig");
    _ = @import("lsp/highlights_test.zig");
    // ── wasm ──────────────────────────────────────────────────────
    _ = @import("wasm.zig");
    _ = @import("wasm_test.zig");
    // ── architecture ────────────────────────────────────────────
    _ = @import("tests/architecture_test.zig");
}
