const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved = @import("../types/resolved_ast.zig");
const sp = @import("../parser/sql_parser.zig");

const Allocator = std.mem.Allocator;
const Field = ast_mod.Field;
const TypeInfo = ast_mod.TypeInfo;
const Modifier = ast_mod.Modifier;
const ModifierType = ast_mod.ModifierType;
const DefaultVal = ast_mod.DefaultVal;
const CheckConstraint = ast_mod.CheckConstraint;
const CheckKind = ast_mod.CheckKind;
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
const ResolvedTable = resolved.ResolvedTable;
const ResolvedAst = resolved.ResolvedAst;

// ─── SqlSchema → ResolvedAst Adapter ──────────────────────────
//
// Converts the reverse pipeline's SqlSchema (SQL-level IR) into the
// forward pipeline's ResolvedAst, enabling cross-format comparison
// (e.g. diff old.ss vs new.sql).
//
// Limitations:
//   - No view conversion (SqlSchema has no view info)
//   - No custom_type conversion (~ directives are SS-specific)
//   - line_no is always 0 (not available from SQL)

pub fn convert(sql: sp.SqlSchema, alloc: Allocator) !ResolvedAst {
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, sql.tables.len);
    for (sql.tables) |sql_table| {
        try tables.append(alloc, try convertTable(sql_table, alloc));
    }
    return .{
        .schema_name = sql.name,
        .schema_charset = sql.charset,
        .custom_types = &.{},
        .tables = try tables.toOwnedSlice(alloc),
        .views = &.{},
        .sql_comments = &.{},
    };
}

fn convertTable(sql_table: sp.SqlTable, alloc: Allocator) !ResolvedTable {
    var fields = try std.ArrayList(Field).initCapacity(alloc, sql_table.columns.len);
    for (sql_table.columns) |col| {
        try fields.append(alloc, try convertColumn(col, alloc));
    }

    var fks = try std.ArrayList(FkDecl).initCapacity(alloc, sql_table.foreign_keys.len);
    for (sql_table.foreign_keys) |fk| {
        try fks.append(alloc, convertFk(fk));
    }

    var indexes = try std.ArrayList(IndexDecl).initCapacity(alloc, sql_table.indexes.len);
    for (sql_table.indexes) |idx| {
        try indexes.append(alloc, convertIndex(idx));
    }

    return .{
        .name = sql_table.name,
        .comment = sql_table.comment,
        .engine = sql_table.engine,
        .fields = try fields.toOwnedSlice(alloc),
        .fks = try fks.toOwnedSlice(alloc),
        .indexes = try indexes.toOwnedSlice(alloc),
        .line_no = 0,
    };
}

fn convertColumn(col: sp.SqlColumn, alloc: Allocator) !Field {
    // Reconstruct TypeInfo: prefer sym_override (original SS symbol),
    // fall back to raw SQL type string.
    const type_info: TypeInfo = if (col.sym_override) |sym|
        .{ .simple = sym }
    else
        .{ .simple = col.type_sql };

    // Reconstruct modifiers from boolean flags
    var mods = std.ArrayList(Modifier).init(alloc);
    if (col.primary_key) {
        try mods.append(.{ .kind = if (col.auto_increment) .auto_inc_pk else .primary_key, .line_no = 0 });
    } else if (col.auto_increment) {
        try mods.append(.{ .kind = .auto_inc, .line_no = 0 });
    }
    if (!col.nullable and !col.primary_key) {
        try mods.append(.{ .kind = .not_null, .line_no = 0 });
    }
    if (col.unsigned) {
        try mods.append(.{ .kind = .unsigned, .line_no = 0 });
    }

    // Reconstruct default value
    const default_val: ?DefaultVal = if (col.default_val) |dv|
        .{ .value = dv, .line_no = 0 }
    else
        null;

    // Reconstruct CHECK constraint from check_expr
    const check: ?CheckConstraint = if (col.check_expr) |expr|
        .{ .kind = .comparison, .expr = expr, .line_no = 0 }
    else
        null;

    return .{
        .name = col.name,
        .type_info = type_info,
        .modifiers = try mods.toOwnedSlice(),
        .default_val = default_val,
        .check = check,
        .fk = null, // FKs are at table level in SqlSchema
        .comment = col.comment,
        .line_no = 0,
    };
}

fn convertFk(fk: sp.SqlForeignKey) FkDecl {
    return .{
        .fields = fk.fields,
        .ref_table = fk.ref_table,
        .ref_fields = fk.ref_fields,
        .actions = fk.actions,
        .line_no = 0,
    };
}

fn convertIndex(idx: sp.SqlIndex) IndexDecl {
    return .{
        .kind = idx.kind,
        .name = idx.name,
        .fields = idx.fields,
        .descending = idx.descending,
        .line_no = 0,
    };
}

// ─── Tests ────────────────────────────────────────────────────

const testing = std.testing;

test "convert basic SqlSchema" {
    const alloc = testing.allocator;

    const sql = sp.SqlSchema{
        .name = null,
        .charset = null,
        .tables = &.{
            .{
                .name = "users",
                .engine = null,
                .charset = null,
                .comment = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .type_sql = "INTEGER",
                        .nullable = false,
                        .unsigned = false,
                        .auto_increment = true,
                        .primary_key = true,
                        .on_update_current_timestamp = false,
                        .default_val = null,
                        .check_expr = null,
                        .comment = null,
                        .sym_override = "n",
                    },
                    .{
                        .name = "name",
                        .type_sql = "VARCHAR(255)",
                        .nullable = false,
                        .unsigned = false,
                        .auto_increment = false,
                        .primary_key = false,
                        .on_update_current_timestamp = false,
                        .default_val = null,
                        .check_expr = null,
                        .comment = null,
                        .sym_override = null,
                    },
                },
                .indexes = &.{},
                .foreign_keys = &.{},
                .checks = &.{},
            },
        },
    };

    const result = try convert(sql, alloc);
    defer {
        for (result.tables) |t| {
            for (t.fields) |f| {
                alloc.free(f.modifiers);
            }
            alloc.free(t.fields);
            alloc.free(t.fks);
            alloc.free(t.indexes);
        }
        alloc.free(result.tables);
    }

    try testing.expectEqual(@as(usize, 1), result.tables.len);
    try testing.expectEqualStrings("users", result.tables[0].name);

    const fields = result.tables[0].fields;
    try testing.expectEqual(@as(usize, 2), fields.len);

    // id column: sym_override "n" → TypeInfo.simple = "n"
    try testing.expectEqualStrings("id", fields[0].name);
    try testing.expectEqualStrings("n", fields[0].type_info.simple);

    // name column: no sym_override → TypeInfo.simple = "VARCHAR(255)"
    try testing.expectEqualStrings("name", fields[1].name);
    try testing.expectEqualStrings("VARCHAR(255)", fields[1].type_info.simple);
}
