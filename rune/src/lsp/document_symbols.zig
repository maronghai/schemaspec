const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const TypedColumn = @import("../types/typed_ast.zig").TypedColumn;
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const protocol = @import("protocol.zig");
const DocumentSymbol = protocol.DocumentSymbol;
const SymbolKind = protocol.SymbolKind;

pub const makeRange = @import("helpers.zig").makeRange;

// ─── Document Symbols ───────────────────────────────────────

/// Generate document symbols from a TypedAst for the outline view.
pub fn getDocumentSymbols(alloc: std.mem.Allocator, ast: TypedAst) []DocumentSymbol {
    var symbols = std.ArrayList(DocumentSymbol).initCapacity(alloc, ast.tables.len + ast.views.len) catch return &.{};

    for (ast.tables) |table| {
        const line_no: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
        const end_line: u32 = line_no + 1;

        var children = std.ArrayList(DocumentSymbol).initCapacity(alloc, table.columns.len + table.fks.len + table.indexes.len) catch null;

        if (children) |*ch| {
            for (table.columns) |col| {
                const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = col.name,
                    .detail = formatColumnDetail(alloc, col),
                    .kind = if (col.flags.primary_key) .constant else .field,
                    .range = makeRange(col_line, 0, col_line, 100),
                    .selection_range = makeRange(col_line, 0, col_line, @intCast(col.name.len)),
                }) catch {};
            }

            for (table.fks) |fk| {
                const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = if (fk.fields.len > 0) fk.fields[0] else "FK",
                    .detail = formatFkDetail(alloc, fk),
                    .kind = .constant,
                    .range = makeRange(fk_line, 0, fk_line, 100),
                    .selection_range = makeRange(fk_line, 0, fk_line, 4),
                }) catch {};
            }

            for (table.indexes) |idx| {
                const idx_line: u32 = if (idx.line_no > 0) @intCast(idx.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = idx.name,
                    .detail = formatIndexDetail(alloc, idx),
                    .kind = .key,
                    .range = makeRange(idx_line, 0, idx_line, 100),
                    .selection_range = makeRange(idx_line, 0, idx_line, 4),
                }) catch {};
            }
        }

        symbols.append(alloc, .{
            .name = table.name,
            .detail = if (table.comment) |c| alloc.dupe(u8, c) catch null else null,
            .kind = .class,
            .range = makeRange(line_no, 0, end_line, 0),
            .selection_range = makeRange(line_no, 0, line_no, @intCast(table.name.len)),
            .children = if (children) |*ch| ch.toOwnedSlice(alloc) catch null else null,
        }) catch {};
    }

    for (ast.views) |view| {
        const line_no: u32 = if (view.line_no > 0) @intCast(view.line_no - 1) else 0;
        symbols.append(alloc, .{
            .name = view.name,
            .detail = if (view.comment) |c| alloc.dupe(u8, c) catch null else null,
            .kind = .event,
            .range = makeRange(line_no, 0, line_no + 1, 0),
            .selection_range = makeRange(line_no, 0, line_no, @intCast(view.name.len)),
        }) catch {};
    }

    return symbols.toOwnedSlice(alloc) catch &.{};
}

/// Recursively free all allocations owned by document symbols.
pub fn freeDocumentSymbols(alloc: std.mem.Allocator, symbols: []DocumentSymbol) void {
    for (symbols) |*sym| {
        if (sym.detail) |d| alloc.free(d);
        if (sym.children) |children| {
            freeDocumentSymbols(alloc, @constCast(children));
        }
    }
    alloc.free(symbols);
}

pub fn formatColumnDetail(alloc: std.mem.Allocator, col: TypedColumn) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    aw.writer.print("{s}", .{@tagName(col.sql_type)}) catch return null;

    switch (col.sql_type) {
        .varchar => |n| {
            if (n > 0) {
                aw.writer.print("({d})", .{n}) catch {};
            }
        },
        .decimal => |ds| {
            aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
        },
        else => {},
    }

    if (col.flags.primary_key) aw.writer.writeAll(" PK") catch {};
    if (col.flags.auto_increment) aw.writer.writeAll(" AUTO_INCREMENT") catch {};
    if (col.flags.nullable) aw.writer.writeAll(" NULL") catch {};
    if (col.flags.unsigned) aw.writer.writeAll(" UNSIGNED") catch {};

    return aw.toOwnedSlice() catch return null;
}

fn formatFkDetail(alloc: std.mem.Allocator, fk: FkDecl) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    aw.writer.writeAll("-> ") catch return null;
    aw.writer.writeAll(fk.ref_table) catch return null;
    aw.writer.writeByte('.') catch return null;
    if (fk.ref_fields.len > 0) {
        aw.writer.writeAll(fk.ref_fields[0]) catch return null;
    }
    return aw.toOwnedSlice() catch return null;
}

fn formatIndexDetail(alloc: std.mem.Allocator, idx: IndexDecl) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    switch (idx.kind) {
        .unique => aw.writer.writeAll("UNIQUE ") catch {},
        .fulltext => aw.writer.writeAll("FULLTEXT ") catch {},
        .primary_key => aw.writer.writeAll("PRIMARY ") catch {},
        .regular => {},
    }
    aw.writer.writeAll("(") catch return null;
    for (idx.fields, 0..) |f, i| {
        if (i > 0) aw.writer.writeAll(", ") catch {};
        aw.writer.writeAll(f) catch {};
    }
    aw.writer.writeByte(')') catch return null;
    return aw.toOwnedSlice() catch return null;
}

test "DocumentSymbols: empty schema" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    try std.testing.expectEqual(@as(usize, 0), symbols.len);
}

test "DocumentSymbols: single table" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = "User accounts",
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                    .{
                        .name = "name",
                        .sql_type = .{ .varchar = 255 },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 3,
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 5,
                    },
                },
                .indexes = &.{
                    .{
                        .kind = .regular,
                        .name = "idx_name",
                        .fields = &.{"name"},
                        .descending = &.{false},
                        .line_no = 6,
                    },
                },
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    defer freeDocumentSymbols(std.testing.allocator, @constCast(symbols));

    try std.testing.expectEqual(@as(usize, 1), symbols.len);
    try std.testing.expectEqualStrings("users", symbols[0].name);
    try std.testing.expectEqual(SymbolKind.class, symbols[0].kind);
    try std.testing.expect(symbols[0].children != null);
    try std.testing.expectEqual(@as(usize, 4), symbols[0].children.?.len);
}

test "DocumentSymbols: multiple tables" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "posts",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 5,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 4,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    defer freeDocumentSymbols(std.testing.allocator, @constCast(symbols));
    try std.testing.expect(symbols.len >= 2);
}
