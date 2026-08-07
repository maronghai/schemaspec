const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Range = protocol.Range;
const CodeAction = protocol.CodeAction;
const Diagnostic = protocol.Diagnostic;
const TextEdit = protocol.TextEdit;
const makeRange = @import("helpers.zig").makeRange;

// ─── Code Actions ──────────────────────────────────────────

/// Generate code actions (quick fixes) for a given range and diagnostics.
pub fn getCodeActions(
    alloc: std.mem.Allocator,
    ast: TypedAst,
    diagnostics: []const Diagnostic,
    range: Range,
) []CodeAction {
    var actions = std.ArrayList(CodeAction).initCapacity(alloc, 8) catch return &.{};

    for (diagnostics) |diag| {
        if (diag.range.start.line < range.start.line or diag.range.end.line > range.end.line) continue;

        // Missing PK suggestion
        if (std.mem.indexOf(u8, diag.message, "no primary key") != null) {
            for (ast.tables) |table| {
                const table_line: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
                if (table_line == diag.range.start.line and table.columns.len > 0) {
                    const first_col = table.columns[0];
                    const col_line: u32 = if (first_col.line_no > 0) @intCast(first_col.line_no - 1) else table_line;
                    var new_text_buf = std.Io.Writer.Allocating.init(alloc);
                    new_text_buf.writer.print("{s} ++", .{first_col.name}) catch continue;
                    const new_text = new_text_buf.toOwnedSlice() catch continue;

                    actions.append(alloc, .{
                        .title = "Add primary key to first column",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = makeRange(col_line, 0, col_line, @intCast(first_col.name.len)),
                            .new_text = new_text,
                        }} },
                    }) catch {};
                    break;
                }
            }
        }

        // Missing table comment suggestion
        if (std.mem.indexOf(u8, diag.message, "missing table comment") != null or
            std.mem.indexOf(u8, diag.message, "lacks a comment") != null)
        {
            for (ast.tables) |table| {
                const table_line: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
                if (table_line == diag.range.start.line) {
                    const name_end: u32 = @intCast(table.name.len);
                    actions.append(alloc, .{
                        .title = "Add table comment",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = makeRange(table_line, name_end, table_line, name_end),
                            .new_text = " # Add a description here",
                        }} },
                    }) catch {};
                    break;
                }
            }
        }

        // Naming convention suggestion
        if (std.mem.indexOf(u8, diag.message, "should be snake_case") != null) {
            if (std.mem.indexOf(u8, diag.message, "\"")) |start_q| {
                const rest = diag.message[start_q + 1 ..];
                if (std.mem.indexOf(u8, rest, "\"")) |end_q| {
                    const name = rest[0..end_q];
                    const snake = toSnakeCase(alloc, name) catch continue;
                    actions.append(alloc, .{
                        .title = "Rename to snake_case",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = diag.range,
                            .new_text = snake,
                        }} },
                    }) catch {};
                }
            }
        }
    }

    // FK index code action
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            if (fk.fields.len == 0) continue;
            const fk_col = fk.fields[0];

            var has_index = false;
            for (table.columns) |col| {
                if (std.mem.eql(u8, col.name, fk_col) and (col.flags.inline_index or col.flags.inline_unique)) {
                    has_index = true;
                    break;
                }
            }
            if (!has_index) {
                for (table.indexes) |idx| {
                    for (idx.fields) |f| {
                        if (std.mem.eql(u8, f, fk_col)) {
                            has_index = true;
                            break;
                        }
                    }
                    if (has_index) break;
                }
            }

            if (!has_index) {
                for (table.columns) |col| {
                    if (std.mem.eql(u8, col.name, fk_col)) {
                        const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
                        const col_name_end: u32 = @intCast(col.name.len);
                        actions.append(alloc, .{
                            .title = "Add index for FK column",
                            .kind = .quick_fix,
                            .edit = .{ .changes = &.{.{
                                .range = makeRange(col_line, col_name_end, col_line, col_name_end),
                                .new_text = " +",
                            }} },
                        }) catch {};
                        break;
                    }
                }
            }
        }
    }

    return actions.items;
}

/// Convert camelCase or PascalCase to snake_case.
pub fn toSnakeCase(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).initCapacity(alloc, input.len * 2) catch return error.OutOfMemory;
    for (input, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) try result.append(alloc, '_');
            try result.append(alloc, std.ascii.toLower(c));
        } else {
            try result.append(alloc, c);
        }
    }
    return try result.toOwnedSlice(alloc);
}

// ─── Tests ──────────────────────────────────────────────────

test "CodeActions: empty diagnostics" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const actions = getCodeActions(std.testing.allocator, ast, &.{}, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 10, .character = 0 },
    });
    try std.testing.expectEqual(@as(usize, 0), actions.len);
}

test "CodeActions: missing PK suggestion" {
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
                        .flags = .{},
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
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const diags = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .warning,
            .message = "Table 'users' has no primary key",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    try std.testing.expect(actions.len > 0);
}

test "CodeActions: multiple diagnostics" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "orders",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{},
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
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const diags = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .warning,
            .message = "Table 'orders' has no primary key",
        },
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .info,
            .message = "Consider adding timestamps",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    try std.testing.expect(actions.len > 0);
}

test "toSnakeCase" {
    const result1 = try toSnakeCase(std.testing.allocator, "userName");
    defer std.testing.allocator.free(result1);
    try std.testing.expectEqualStrings("user_name", result1);

    const result2 = try toSnakeCase(std.testing.allocator, "UserName");
    defer std.testing.allocator.free(result2);
    try std.testing.expectEqualStrings("user_name", result2);

    const result3 = try toSnakeCase(std.testing.allocator, "already_snake");
    defer std.testing.allocator.free(result3);
    try std.testing.expectEqualStrings("already_snake", result3);
}
