// Test module index — imports colocated test files so zig build test discovers them.
comptime {
    // ast_visitor
    _ = @import("ast_visitor_test.zig");
    // bench
    _ = @import("bench_test.zig");
    // cli
    _ = @import("cli_test.zig");
    // codegen
    _ = @import("codegen/codegen_test.zig");
    _ = @import("codegen/columns_test.zig");
    _ = @import("codegen/indexes_test.zig");
    // dialect
    _ = @import("dialect/common_test.zig");
    _ = @import("dialect/mysql_test.zig");
    _ = @import("dialect/pg_test.zig");
    _ = @import("dialect/sqlite_test.zig");
    _ = @import("dialect/mssql_test.zig");
    _ = @import("dialect/oracle_test.zig");
    _ = @import("dialect/db2_test.zig");
    _ = @import("dialect/sqlite_hints_test.zig");
    // diff
    _ = @import("diff/diff_test.zig");
    _ = @import("diff/engine_test.zig");
    _ = @import("diff/fields_test.zig");
    _ = @import("diff/fks_test.zig");
    _ = @import("diff/indexes_test.zig");
    _ = @import("diff/semantic_test.zig");
    _ = @import("diff/migrate_test.zig");
    _ = @import("diff/migrate_json_test.zig");
    _ = @import("diff/types_test.zig");
    _ = @import("diff/format/text_test.zig");
    _ = @import("diff/format/sarif_test.zig");
    _ = @import("diff/format/json_test.zig");
    // formatter
    _ = @import("formatter_test.zig");
    // io
    _ = @import("io_test.zig");
    // json_schema
    _ = @import("generators/json_schema_test.zig");
    // parser
    _ = @import("parser/tokenizer_test.zig");
    _ = @import("parser/parser_test.zig");
    _ = @import("parser/parse_check_test.zig");
    _ = @import("parser/parse_fk_test.zig");
    _ = @import("parser/parse_index_test.zig");
    _ = @import("parser/parse_recovery_test.zig");
    _ = @import("parser/parse_table_test.zig");
    _ = @import("parser/parse_template_test.zig");
    _ = @import("parser/sql_parser_test.zig");
    // pipeline
    _ = @import("pipeline/diff_test.zig");
    _ = @import("pipeline/forward_test.zig");
    _ = @import("pipeline/import_resolver_test.zig");
    // reverse
    _ = @import("reverse/map_test.zig");
    _ = @import("reverse/column_test.zig");
    _ = @import("reverse/check_test.zig");
    _ = @import("reverse/codegen_test.zig");
    _ = @import("reverse/dialect_detect_test.zig");
    _ = @import("reverse/fk_test.zig");
    _ = @import("reverse/template_extraction_test.zig");
    // semantic
    _ = @import("semantic/analyzer_test.zig");
    _ = @import("semantic/diagnostic_test.zig");
    _ = @import("semantic/pass_manager_test.zig");
    _ = @import("semantic/template_test.zig");
    // types
    _ = @import("types/type_map_test.zig");
    _ = @import("types/type_resolver_test.zig");
    _ = @import("types/type_registry_test.zig");
    _ = @import("types/sql_type_test.zig");
    // generators
    _ = @import("generators/sql_ddl_test.zig");
    _ = @import("generators/prisma_test.zig");
    _ = @import("generators/docs_test.zig");
    _ = @import("generators/drizzle_test.zig");
    _ = @import("generators/typeorm_test.zig");
    _ = @import("generators/sqlalchemy_test.zig");
    _ = @import("generators/knex_test.zig");
    _ = @import("generators/openapi_test.zig");
    _ = @import("generators/graphql_test.zig");
    // utils
    _ = @import("utils/edit_distance_test.zig");
}
