const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Hover = protocol.Hover;
const MarkupKind = protocol.MarkupKind;
const makeRange = @import("helpers.zig").makeRange;
const formatFlagsForHover = @import("helpers.zig").formatFlagsForHover;
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── Hover ──────────────────────────────────────────────────

fn formatSqlTypeForHover(alloc: std.mem.Allocator, sql_type: anytype, dialect: Dialect) []const u8 {
    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    sql_type.toSql(dialect, &law.writer) catch return @tagName(sql_type);
    return law.toOwnedSlice() catch return @tagName(sql_type);
}

/// Generate hover information for a position in the document.
pub fn getHover(alloc: std.mem.Allocator, ast: TypedAst, position: Position, dialect: Dialect) ?Hover {
    const line = position.line;

    for (ast.tables) |table| {
        const table_start: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;

        if (line == table_start) {
            var aw = std.Io.Writer.Allocating.init(alloc);
            defer aw.deinit();
            aw.writer.print("**{s}**", .{table.name}) catch return null;
            if (table.comment) |c| {
                aw.writer.print("\n\n{s}", .{c}) catch {};
            }
            aw.writer.print("\n\n| Property | Value |", .{}) catch {};
            aw.writer.print("\n|----------|-------|", .{}) catch {};
            aw.writer.print("\n| Columns | {d} |", .{table.columns.len}) catch {};
            aw.writer.print("\n| Foreign Keys | {d} |", .{table.fks.len}) catch {};
            aw.writer.print("\n| Indexes | {d} |", .{table.indexes.len}) catch {};
            if (table.engine) |e| {
                aw.writer.print("\n| Engine | `{s}` |", .{e}) catch {};
            }
            if (table.fks.len > 0) {
                aw.writer.writeAll("\n\n**Relationships:**\n") catch {};
                for (table.fks) |fk| {
                    if (fk.fields.len > 0) {
                        aw.writer.print("- `{s}` → `{s}.{s}`", .{ fk.fields[0], fk.ref_table, if (fk.ref_fields.len > 0) fk.ref_fields[0] else "" }) catch {};
                        if (fk.actions.len > 0) {
                            aw.writer.writeAll(" (") catch {};
                            for (fk.actions, 0..) |action, ai| {
                                if (ai > 0) aw.writer.writeAll(", ") catch {};
                                aw.writer.print("{s} {s}", .{ @tagName(action.trigger), @tagName(action.action) }) catch {};
                            }
                            aw.writer.writeAll(")") catch {};
                        }
                        aw.writer.writeByte('\n') catch {};
                    }
                }
            }
            return .{
                .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                .range = makeRange(table_start, 0, table_start, @intCast(table.name.len)),
            };
        }

        for (table.columns) |col| {
            const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
            if (line == col_line) {
                var aw = std.Io.Writer.Allocating.init(alloc);
                defer aw.deinit();

                const sql_type_str = formatSqlTypeForHover(alloc, col.sql_type, dialect);
                defer alloc.free(sql_type_str);

                aw.writer.print("**{s}** : `{s}`", .{ col.name, sql_type_str }) catch return null;

                aw.writer.writeAll("\n\n```sql\n") catch {};
                aw.writer.print("{s} {s}", .{ col.name, sql_type_str }) catch {};
                const flags_str = formatFlagsForHover(alloc, col.flags);
                defer if (flags_str.len > 0) alloc.free(flags_str);
                if (flags_str.len > 0) {
                    aw.writer.print(" {s}", .{flags_str}) catch {};
                }
                if (col.default) |dflt| {
                    aw.writer.print(" DEFAULT {s}", .{dflt}) catch {};
                }
                aw.writer.writeAll("\n```\n") catch {};

                const detail_flags = formatFlagsForHover(alloc, col.flags);
                defer if (detail_flags.len > 0) alloc.free(detail_flags);
                if (detail_flags.len > 0) {
                    aw.writer.writeAll("**Flags:** ") catch {};
                    var detail_iter = std.mem.splitScalar(u8, detail_flags, ' ');
                    var first = true;
                    while (detail_iter.next()) |f| {
                        if (!first) aw.writer.writeAll(", ") catch {};
                        first = false;
                        aw.writer.print("`{s}`", .{f}) catch {};
                    }
                    aw.writer.writeByte('\n') catch {};
                }

                if (col.default) |dflt| {
                    aw.writer.print("\n**Default:** `{s}`", .{dflt}) catch {};
                }

                if (col.comment) |c| {
                    aw.writer.print("\n\n{s}", .{c}) catch {};
                }

                return .{
                    .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                    .range = makeRange(col_line, 0, col_line, @intCast(col.name.len)),
                };
            }
        }

        if (table_start <= line) {
            for (table.fks) |fk| {
                const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else 0;
                if (line == fk_line) {
                    var aw = std.Io.Writer.Allocating.init(alloc);
                    defer aw.deinit();
                    aw.writer.writeAll("**Foreign Key**\n\n") catch return null;
                    if (fk.fields.len > 0) {
                        aw.writer.print("Column: `{s}`\n", .{fk.fields[0]}) catch {};
                    }
                    aw.writer.print("Target: `{s}.{s}`\n", .{ fk.ref_table, if (fk.ref_fields.len > 0) fk.ref_fields[0] else "" }) catch {};

                    // Look up target column type and constraints
                    if (fk.ref_fields.len > 0) {
                        for (ast.tables) |ref_table| {
                            if (std.mem.eql(u8, ref_table.name, fk.ref_table)) {
                                for (ref_table.columns) |ref_col| {
                                    if (std.mem.eql(u8, ref_col.name, fk.ref_fields[0])) {
                                        aw.writer.writeAll("\n**Target Column:**\n") catch {};
                                        const ref_type_str = formatSqlTypeForHover(alloc, ref_col.sql_type, dialect);
                                        defer alloc.free(ref_type_str);
                                        aw.writer.print("- Type: `{s}`", .{ref_type_str}) catch {};
                                        aw.writer.writeByte('\n') catch {};
                                        if (ref_col.flags.primary_key) {
                                            aw.writer.writeAll("- `PRIMARY KEY`\n") catch {};
                                        }
                                        if (ref_col.flags.nullable) {
                                            aw.writer.writeAll("- `NULLABLE`\n") catch {};
                                        } else {
                                            aw.writer.writeAll("- `NOT NULL`\n") catch {};
                                        }
                                        break;
                                    }
                                }
                                break;
                            }
                        }
                    }

                    if (fk.actions.len > 0) {
                        aw.writer.writeAll("\n**Actions:**\n") catch {};
                        for (fk.actions) |action| {
                            aw.writer.print("- {s} {s}\n", .{ @tagName(action.trigger), @tagName(action.action) }) catch {};
                        }
                    }
                    return .{
                        .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                        .range = makeRange(fk_line, 0, fk_line, 4),
                    };
                }
            }
        }
    }

    for (ast.views) |view| {
        const view_line: u32 = if (view.line_no > 0) @intCast(view.line_no - 1) else 0;
        if (line == view_line) {
            var aw = std.Io.Writer.Allocating.init(alloc);
            defer aw.deinit();
            aw.writer.print("**View: {s}**", .{view.name}) catch return null;
            if (view.comment) |c| {
                aw.writer.print("\n\n{s}", .{c}) catch {};
            }
            aw.writer.writeAll("\n\n```sql\n") catch {};
            aw.writer.writeAll(view.query) catch {};
            aw.writer.writeAll("\n```\n") catch {};
            return .{
                .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                .range = makeRange(view_line, 0, view_line, @intCast(view.name.len)),
            };
        }
    }

    return null;
}

// ─── Tests ──────────────────────────────────────────────────

test "Hover: table hover" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = "User accounts",
                .engine = null,
                .columns = &.{.{
                    .name = "id",
                    .sql_type = .int,
                    .flags = .{ .primary_key = true },
                    .default = null,
                    .check = null,
                    .comment = null,
                    .enum_values = &.{},
                    .line_no = 2,
                }},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = getHover(std.testing.allocator, ast, .{ .line = 0, .character = 0 }, .mysql);
    try std.testing.expect(result != null);
    if (result) |h| {
        defer std.testing.allocator.free(h.contents.value);
        try std.testing.expectEqual(MarkupKind.markdown, h.contents.kind);
        try std.testing.expect(std.mem.indexOf(u8, h.contents.value, "users") != null);
    }
}

test "Hover: column hover" {
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
                        .name = "email",
                        .sql_type = .{ .varchar = 255 },
                        .flags = .{ .inline_unique = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 3,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = getHover(std.testing.allocator, ast, .{ .line = 2, .character = 2 }, .mysql);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.contents.value);
        try std.testing.expect(std.mem.indexOf(u8, r.contents.value, "email") != null);
    }
}
