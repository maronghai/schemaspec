const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Range = protocol.Range;
const CodeAction = protocol.CodeAction;
const Diagnostic = protocol.Diagnostic;
const TextEdit = protocol.TextEdit;
const helpers = @import("helpers.zig");
const makeRange = helpers.makeRange;
const lineNoToZeroBased = helpers.lineNoToZeroBased;

// ─── Code Actions ──────────────────────────────────────────

/// Append one code action, deep-copying the edit's changes slice and the
/// diagnostics slice onto the heap. The anonymous-literal form
/// (`changes = &.{...}`) materializes a stack temporary that dies at the end
/// of the append statement — every action built that way carried a dangling
/// pointer that corrupted the JSON serialized to the editor (and crashed
/// tests that free the action). Ownership: `new_text` strings stay owned by
/// the caller-side allocator and are freed by freeCodeActions.
fn appendCodeAction(
    alloc: std.mem.Allocator,
    actions: *std.ArrayList(CodeAction),
    title: []const u8,
    diag: ?Diagnostic,
    range: Range,
    new_text: []const u8,
) void {
    const changes = alloc.dupe(TextEdit, &.{.{ .range = range, .new_text = new_text }}) catch return;
    const diags: ?[]const Diagnostic = if (diag) |d| alloc.dupe(Diagnostic, &.{d}) catch null else null;
    actions.append(alloc, .{
        .title = title,
        .kind = .quick_fix,
        .diagnostics = diags,
        .edit = .{ .changes = changes },
    }) catch {
        alloc.free(changes);
        if (diags) |d| alloc.free(d);
    };
}

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
                const table_line = lineNoToZeroBased(table.line_no);
                if (table_line == diag.range.start.line and table.columns.len > 0) {
                    const first_col = table.columns[0];
                    const col_line = lineNoToZeroBased(first_col.line_no);
                    var new_text_buf = std.Io.Writer.Allocating.init(alloc);
                    new_text_buf.writer.print("{s} ++", .{first_col.name}) catch continue;
                    const new_text = new_text_buf.toOwnedSlice() catch continue;

                    appendCodeAction(alloc, &actions, "Add primary key to first column", diag, makeRange(col_line, 0, col_line, @intCast(first_col.name.len)), new_text);
                    break;
                }
            }
        }

        // Missing table comment suggestion
        if (std.mem.indexOf(u8, diag.message, "missing table comment") != null or
            std.mem.indexOf(u8, diag.message, "lacks a comment") != null)
        {
            for (ast.tables) |table| {
                const table_line = lineNoToZeroBased(table.line_no);
                if (table_line == diag.range.start.line) {
                    const name_end: u32 = @intCast(table.name.len);
                    const duped = alloc.dupe(u8, " # Add a description here") catch continue;
                    appendCodeAction(alloc, &actions, "Add table comment", diag, makeRange(table_line, name_end, table_line, name_end), duped);
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
                    appendCodeAction(alloc, &actions, "Rename to snake_case", diag, diag.range, snake);
                }
            }
        }

        // Missing timestamps suggestion
        if (std.mem.indexOf(u8, diag.message, "no timestamps") != null or
            std.mem.indexOf(u8, diag.message, "missing created_at") != null)
        {
            for (ast.tables) |table| {
                const table_line = lineNoToZeroBased(table.line_no);
                if (table_line == diag.range.start.line) {
                    // Find the last column line to insert after it
                    var last_col_line: u32 = table_line;
                    if (table.columns.len > 0) {
                        last_col_line = lineNoToZeroBased(table.columns[table.columns.len - 1].line_no);
                    }
                    const duped = alloc.dupe(u8, "  created_at t @u\n  updated_at t @u\n") catch continue;
                    appendCodeAction(alloc, &actions, "Add created_at and updated_at timestamps", diag, makeRange(last_col_line, 0, last_col_line, 0), duped);
                    break;
                }
            }
        }

        // Bool default suggestion
        if (std.mem.indexOf(u8, diag.message, "boolean") != null and
            std.mem.indexOf(u8, diag.message, "no default") != null)
        {
            for (ast.tables) |table| {
                for (table.columns) |col| {
                    if (col.sql_type == .boolean and col.default == null) {
                        const col_line = lineNoToZeroBased(col.line_no);
                        const col_name_end: u32 = @intCast(col.name.len);
                        // Find the end of the line
                        const line_end: u32 = diag.range.end.character;
                        const new_text = std.fmt.allocPrint(alloc, "{s} = false", .{col.name}) catch continue;
                        appendCodeAction(alloc, &actions, "Add default value (false)", diag, makeRange(col_line, col_name_end, col_line, line_end), new_text);
                        break;
                    }
                }
            }
        }

        // Nullable column default suggestion
        if (std.mem.indexOf(u8, diag.message, "nullable") != null and
            std.mem.indexOf(u8, diag.message, "no default") != null)
        {
            for (ast.tables) |table| {
                for (table.columns) |col| {
                    if (col.flags.nullable and col.default == null and !col.flags.primary_key) {
                        const col_line = lineNoToZeroBased(col.line_no);
                        const col_name_end: u32 = @intCast(col.name.len);
                        const line_end: u32 = diag.range.end.character;
                        const new_text = std.fmt.allocPrint(alloc, "{s} = null", .{col.name}) catch continue;
                        appendCodeAction(alloc, &actions, "Add default value (null)", diag, makeRange(col_line, col_name_end, col_line, line_end), new_text);
                        break;
                    }
                }
            }
        }

        // Serial type suggestion (cross-dialect)
        if (std.mem.indexOf(u8, diag.message, "serial") != null and
            std.mem.indexOf(u8, diag.message, "not portable") != null)
        {
            for (ast.tables) |table| {
                for (table.columns) |col| {
                    if (col.sql_type == .serial) {
                        const col_line = lineNoToZeroBased(col.line_no);
                        const new_text = std.fmt.allocPrint(alloc, "{s} n ++", .{col.name}) catch continue;
                        appendCodeAction(alloc, &actions, "Replace serial with int auto_increment", diag, makeRange(col_line, 0, col_line, @intCast(col.name.len + 8)), new_text); // name + " serial"
                        break;
                    }
                }
            }
        }

        // Duplicate index suggestion
        if (std.mem.indexOf(u8, diag.message, "duplicate index") != null) {
            const duped = alloc.dupe(u8, "") catch continue;
            appendCodeAction(alloc, &actions, "Remove duplicate index", diag, diag.range, duped);
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
                        const col_line = lineNoToZeroBased(col.line_no);
                        const col_name_end: u32 = @intCast(col.name.len);
                        const duped = alloc.dupe(u8, " +") catch continue;
                        appendCodeAction(alloc, &actions, "Add index for FK column", null, makeRange(col_line, col_name_end, col_line, col_name_end), duped);
                        break;
                    }
                }
            }
        }
    }

    return actions.toOwnedSlice(alloc) catch &.{};
}

/// Free all allocations owned by code actions: each change's new_text, the
/// changes slices, the diagnostics slices, and the action array itself.
pub fn freeCodeActions(alloc: std.mem.Allocator, actions: []CodeAction) void {
    for (actions) |*action| {
        if (action.diagnostics) |diags| alloc.free(diags);
        if (action.edit) |edit| {
            if (edit.changes) |changes| {
                for (changes) |*change| {
                    alloc.free(change.new_text);
                }
                alloc.free(changes);
            }
        }
    }
    alloc.free(actions);
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
    defer freeCodeActions(std.testing.allocator, @constCast(actions));
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
            .severity = .information,
            .message = "Consider adding timestamps",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    defer freeCodeActions(std.testing.allocator, @constCast(actions));
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

test "CodeActions: duplicate index suggestion" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const diags = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 2, .character = 0 },
                .end = .{ .line = 2, .character = 20 },
            },
            .severity = .warning,
            .message = "duplicate index 'idx_name' on table 'users'",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    defer freeCodeActions(std.testing.allocator, @constCast(actions));
    try std.testing.expect(actions.len > 0);
    try std.testing.expectEqualStrings("Remove duplicate index", actions[0].title);
}

test "CodeActions: FK index suggestion" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "orders",
                .comment = null,
                .doc = null,
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
                        .name = "user_id",
                        .sql_type = .int,
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
                        .line_no = 3,
                    },
                },
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const actions = getCodeActions(std.testing.allocator, ast, &.{}, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 10, .character = 0 },
    });
    defer freeCodeActions(std.testing.allocator, @constCast(actions));
    // Should have FK index action
    var found_fk_index = false;
    for (actions) |action| {
        if (std.mem.indexOf(u8, action.title, "FK") != null) {
            found_fk_index = true;
            break;
        }
    }
    try std.testing.expect(found_fk_index);
}
