const std = @import("std");
const resolved_ast = @import("../types/resolved_ast.zig");
const codegen = @import("../codegen/codegen.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const dialect_enum = @import("../dialect/enum.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const emit = @import("emit.zig");

const Dialect = dialect_enum.Dialect;

// ─── Shared Migration Helpers ──────────────────────────────────
// Functions shared by both forward migration and rollback generation.
// Extracted from migrate.zig for single-responsibility.

/// Emit a single table's CREATE TABLE statement by resolving it from a full schema.
/// Used by both forward (create) and rollback (re-create dropped table) paths.
pub fn emitSingleTable(
    alloc: std.mem.Allocator,
    w: anytype,
    cg: *codegen.Codegen,
    resolved: resolved_ast.ResolvedAst,
    table_name: []const u8,
    dialect: Dialect,
) !void {
    if (emit.findResolvedTable(resolved, table_name)) |table| {
        var single_tables = try std.ArrayList(resolved_ast.ResolvedTable).initCapacity(alloc, 1);
        try single_tables.append(alloc, table);
        const single_resolved = resolved_ast.ResolvedAst{
            .schema_name = resolved.schema_name,
            .schema_charset = resolved.schema_charset,
            .custom_types = resolved.custom_types,
            .tables = try single_tables.toOwnedSlice(alloc),
            .views = &.{},
            .sql_comments = &.{},
        };
        const single_typed = try TypeResolver.resolve(alloc, single_resolved, dialect);
        if (single_typed.tables.len > 0) {
            try cg.generateTypedTable(w, single_typed.tables[0]);
        }
        try w.writeAll("\n\n");
    }
}
