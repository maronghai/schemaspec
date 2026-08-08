const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Hover = protocol.Hover;
const MarkupKind = protocol.MarkupKind;
const makeRange = @import("helpers.zig").makeRange;

// ─── Hover ──────────────────────────────────────────────────

fn formatSqlTypeForHover(alloc: std.mem.Allocator, sql_type: anytype) []const u8 {
    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    sql_type.toSql(.mysql, &law.writer) catch return @tagName(sql_type);
    return law.toOwnedSlice() catch return @tagName(sql_type);
}

fn formatFlagsForHover(alloc: std.mem.Allocator, flags: anytype) []const u8 {
    var parts = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return "";
    defer parts.deinit(alloc);
    if (flags.primary_key) parts.append(alloc, "PRIMARY KEY") catch {};
    if (flags.auto_increment) parts.append(alloc, "AUTO_INCREMENT") catch {};
    if (flags.nullable) parts.append(alloc, "NULL") catch {};
    if (flags.unsigned) parts.append(alloc, "UNSIGNED") catch {};
    if (flags.inline_unique) parts.append(alloc, "UNIQUE") catch {};
    if (flags.inline_index) parts.append(alloc, "INDEX") catch {};
    if (flags.is_enum) parts.append(alloc, "ENUM") catch {};
    if (flags.is_virtual) parts.append(alloc, "VIRTUAL") catch {};
    if (flags.is_stored) parts.append(alloc, "STORED") catch {};

    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    for (parts.items, 0..) |p, i| {
        if (i > 0) law.writer.writeAll(" ") catch {};
        law.writer.writeAll(p) catch {};
    }
    return law.toOwnedSlice() catch return "";
}

/// Generate hover information for a position in the document.
pub fn getHover(alloc: std.mem.Allocator, ast: TypedAst, position: Position) ?Hover {
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

                aw.writer.print("**{s}** : `{s}`", .{ col.name, @tagName(col.sql_type) }) catch return null;

                switch (col.sql_type) {
                    .varchar => |n| {
                        if (n > 0) aw.writer.print("({d})", .{n}) catch {};
                    },
                    .decimal => |ds| {
                        aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
                    },
                    else => {},
                }

                aw.writer.writeAll("\n\n```sql\n") catch {};
                aw.writer.print("{s} {s}", .{ col.name, @tagName(col.sql_type) }) catch {};
                switch (col.sql_type) {
                    .varchar => |n| {
                        if (n > 0) aw.writer.print("({d})", .{n}) catch {};
                    },
                    .decimal => |ds| {
                        aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
                    },
                    else => {},
                }
                const flags_str = formatFlagsForHover(alloc, col.flags);
                defer if (flags_str.len > 0) alloc.free(flags_str);
                if (flags_str.len > 0) {
                    aw.writer.print(" {s}", .{flags_str}) catch {};
                }
                if (col.default) |dflt| {
                    aw.writer.print(" DEFAULT {s}", .{dflt}) catch {};
                }
                aw.writer.writeAll("\n```\n") catch {};

                var flags = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return null;
                defer flags.deinit(alloc);
                if (col.flags.primary_key) flags.append(alloc, "PRIMARY KEY") catch {};
                if (col.flags.auto_increment) flags.append(alloc, "AUTO_INCREMENT") catch {};
                if (col.flags.nullable) flags.append(alloc, "NULLABLE") catch {};
                if (col.flags.unsigned) flags.append(alloc, "UNSIGNED") catch {};
                if (col.flags.inline_unique) flags.append(alloc, "UNIQUE") catch {};
                if (col.flags.inline_index) flags.append(alloc, "INDEXED") catch {};
                if (col.flags.is_enum) flags.append(alloc, "ENUM") catch {};
                if (col.flags.is_virtual) flags.append(alloc, "VIRTUAL") catch {};
                if (col.flags.is_stored) flags.append(alloc, "STORED") catch {};

                if (flags.items.len > 0) {
                    aw.writer.writeAll("**Flags:** ") catch {};
                    for (flags.items, 0..) |f, i| {
                        if (i > 0) aw.writer.writeAll(", ") catch {};
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
                                        aw.writer.print("- Type: `{s}`", .{@tagName(ref_col.sql_type)}) catch {};
                                        switch (ref_col.sql_type) {
                                            .varchar => |n| {
                                                if (n > 0) aw.writer.print("({d})", .{n}) catch {};
                                            },
                                            .decimal => |ds| {
                                                aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
                                            },
                                            else => {},
                                        }
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
    const result = getHover(std.testing.allocator, ast, .{ .line = 0, .character = 0 });
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
    const result = getHover(std.testing.allocator, ast, .{ .line = 2, .character = 2 });
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.contents.value);
        try std.testing.expect(std.mem.indexOf(u8, r.contents.value, "email") != null);
    }
}
