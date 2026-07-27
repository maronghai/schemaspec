const std = @import("std");
const indexes_mod = @import("indexes.zig");
const codegen_mod = @import("codegen.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const Codegen = codegen_mod.Codegen;

const sql_type_mod = @import("../types/sql_type.zig");

const testing = std.testing;

fn makeTestColumn(name: []const u8, sql_type: sql_type_mod.SqlType) typed_ast_mod.TypedColumn {
    return .{
        .name = name,
        .sql_type = sql_type,
        .flags = .{},
        .default = null,
        .check = null,
        .comment = null,
        .enum_values = &.{},
        .line_no = 1,
    };
}

fn makeTestIndex(kind: ast_mod.IndexType, name: []const u8, fields: []const []const u8) ast_mod.IndexDecl {
    return .{
        .kind = kind,
        .name = name,
        .fields = fields,
        .descending = &.{},
        .line_no = 1,
    };
}

test "indexes: emitInlineIndexes emits UNIQUE for inline_unique columns" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const backend = dialect_mod.getBackend(.mysql);

    var col = makeTestColumn("email", .{ .varchar = 255 });
    col.flags.inline_unique = true;

    const table = typed_ast_mod.TypedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .columns = &.{col},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    var needs_comma = false;
    try indexes_mod.emitInlineIndexes(backend, w, table, &needs_comma);
    try w.flush();

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);

    try testing.expect(std.mem.indexOf(u8, result, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, result, "email") != null);
}

test "indexes: emitInlineIndexes skips when explicit index dominates" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const backend = dialect_mod.getBackend(.mysql);

    var col = makeTestColumn("email", .{ .varchar = 255 });
    col.flags.inline_unique = true;

    // Explicit unique index on the same column should suppress inline
    const idx = makeTestIndex(.unique, "idx_email", &.{"email"});

    const table = typed_ast_mod.TypedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .columns = &.{col},
        .fks = &.{},
        .indexes = &.{idx},
        .line_no = 1,
    };

    var needs_comma = false;
    try indexes_mod.emitInlineIndexes(backend, w, table, &needs_comma);
    try w.flush();

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);

    // Should not emit inline UNIQUE since explicit index dominates
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "indexes: emitStandaloneIndexes emits index definitions" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const backend = dialect_mod.getBackend(.mysql);

    const idx = makeTestIndex(.regular, "idx_name", &.{"name"});

    const table = typed_ast_mod.TypedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .columns = &.{},
        .fks = &.{},
        .indexes = &.{idx},
        .line_no = 1,
    };

    try indexes_mod.emitStandaloneIndexes(backend, w, table);
    try w.flush();

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);

    try testing.expect(std.mem.indexOf(u8, result, "INDEX") != null);
    try testing.expect(std.mem.indexOf(u8, result, "idx_name") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name") != null);
}

test "indexes: emitInlineColumnStandaloneIndexes emits for inline_index columns" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const backend = dialect_mod.getBackend(.mysql);

    var col = makeTestColumn("created_at", .datetime);
    col.flags.inline_index = true;

    const table = typed_ast_mod.TypedTable{
        .name = "logs",
        .comment = null,
        .engine = null,
        .columns = &.{col},
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    try indexes_mod.emitInlineColumnStandaloneIndexes(backend, w, table);
    try w.flush();

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);

    try testing.expect(std.mem.indexOf(u8, result, "INDEX") != null);
    try testing.expect(std.mem.indexOf(u8, result, "created_at") != null);
}

test "indexes: emitInlineColumnStandaloneIndexes skips when explicit index dominates" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    const backend = dialect_mod.getBackend(.mysql);

    var col = makeTestColumn("created_at", .datetime);
    col.flags.inline_index = true;

    const idx = makeTestIndex(.regular, "idx_created", &.{"created_at"});

    const table = typed_ast_mod.TypedTable{
        .name = "logs",
        .comment = null,
        .engine = null,
        .columns = &.{col},
        .fks = &.{},
        .indexes = &.{idx},
        .line_no = 1,
    };

    try indexes_mod.emitInlineColumnStandaloneIndexes(backend, w, table);
    try w.flush();

    var out = aw.toArrayList();
    const result = try out.toOwnedSlice(alloc);

    // Should not emit since explicit index dominates
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "indexes: MySQL UNIQUE INDEX vs PG UNIQUE" {
    const alloc = testing.allocator;

    // MySQL backend
    var aw_mysql = std.Io.Writer.Allocating.init(alloc);
    const w_mysql = &aw_mysql.writer;
    const backend_mysql = dialect_mod.getBackend(.mysql);

    const idx = makeTestIndex(.unique, "uq_email", &.{"email"});
    const table_mysql = typed_ast_mod.TypedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .columns = &.{},
        .fks = &.{},
        .indexes = &.{idx},
        .line_no = 1,
    };
    try indexes_mod.emitStandaloneIndexes(backend_mysql, w_mysql, table_mysql);
    try w_mysql.flush();
    var out_mysql = aw_mysql.toArrayList();
    const result_mysql = try out_mysql.toOwnedSlice(alloc);

    // PG backend
    var aw_pg = std.Io.Writer.Allocating.init(alloc);
    const w_pg = &aw_pg.writer;
    const backend_pg = dialect_mod.getBackend(.pg);

    const table_pg = typed_ast_mod.TypedTable{
        .name = "users",
        .comment = null,
        .engine = null,
        .columns = &.{},
        .fks = &.{},
        .indexes = &.{idx},
        .line_no = 1,
    };
    try indexes_mod.emitStandaloneIndexes(backend_pg, w_pg, table_pg);
    try w_pg.flush();
    var out_pg = aw_pg.toArrayList();
    const result_pg = try out_pg.toOwnedSlice(alloc);

    // Both should emit UNIQUE INDEX
    try testing.expect(std.mem.indexOf(u8, result_mysql, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, result_pg, "UNIQUE") != null);

    // MySQL uses backticks, PG uses double quotes
    try testing.expect(std.mem.indexOf(u8, result_mysql, "`users`") != null);
    try testing.expect(std.mem.indexOf(u8, result_pg, "\"users\"") != null);
}
