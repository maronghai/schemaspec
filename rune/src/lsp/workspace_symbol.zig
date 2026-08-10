const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Location = protocol.Location;
const SymbolKind = protocol.SymbolKind;

// ─── Workspace Symbol Search ─────────────────────────────────
// Provides workspace/symbol support for searching all tables,
// templates, views, and custom types by name query.
// Since Rune is typically single-file, searches the open document.

pub const WorkspaceSymbol = struct {
    name: []const u8,
    kind: SymbolKind,
    location: Location,
    container_name: ?[]const u8 = null,
};

/// Search all symbols in the AST matching a query (case-insensitive substring match).
pub fn getWorkspaceSymbols(
    alloc: std.mem.Allocator,
    ast: TypedAst,
    uri: []const u8,
    query: []const u8,
) []WorkspaceSymbol {
    var results = std.ArrayList(WorkspaceSymbol).initCapacity(alloc, 16) catch return &.{};

    // Search tables
    for (ast.tables) |table| {
        if (matchQuery(table.name, query)) {
            const line_no: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
            results.append(alloc, .{
                .name = table.name,
                .kind = .class,
                .location = .{
                    .uri = uri,
                    .range = .{
                        .start = .{ .line = line_no, .character = 0 },
                        .end = .{ .line = line_no + 1, .character = 0 },
                    },
                },
            }) catch {};
        }

        // Always search columns regardless of table name match
        for (table.columns) |col| {
            if (matchQuery(col.name, query)) {
                const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
                results.append(alloc, .{
                    .name = col.name,
                    .kind = if (col.flags.primary_key) .constant else .field,
                    .location = .{
                        .uri = uri,
                        .range = .{
                            .start = .{ .line = col_line, .character = 0 },
                            .end = .{ .line = col_line, .character = @intCast(col.name.len) },
                        },
                    },
                    .container_name = table.name,
                }) catch {};
            }
        }
    }

    // Search views
    for (ast.views) |view| {
        if (matchQuery(view.name, query)) {
            const line_no: u32 = if (view.line_no > 0) @intCast(view.line_no - 1) else 0;
            results.append(alloc, .{
                .name = view.name,
                .kind = .event,
                .location = .{
                    .uri = uri,
                    .range = .{
                        .start = .{ .line = line_no, .character = 0 },
                        .end = .{ .line = line_no + 1, .character = 0 },
                    },
                },
            }) catch {};
        }
    }

    return results.toOwnedSlice(alloc) catch &.{};
}

/// Case-insensitive substring match for query filtering.
fn matchQuery(name: []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    if (name.len < query.len) return false;

    // Case-insensitive comparison without allocation
    for (0..name.len - query.len + 1) |offset| {
        var matched = true;
        for (0..query.len) |qi| {
            const nc = std.ascii.toLower(name[offset + qi]);
            const qc = std.ascii.toLower(query[qi]);
            if (nc != qc) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

/// Write WorkspaceSymbol array as JSON array.
pub fn writeWorkspaceSymbols(w: anytype, symbols: []const WorkspaceSymbol) !void {
    try w.writeByte('[');
    for (symbols, 0..) |sym, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeByte('{');
        try protocol.json_utils.writeJsonField(w, "name", sym.name);
        try w.writeByte(',');
        try protocol.json_utils.writeJsonInt(w, "kind", @intFromEnum(sym.kind));
        try w.writeAll(",\"location\":{");
        try protocol.json_utils.writeJsonField(w, "uri", sym.location.uri);
        try w.writeByte(',');
        try protocol.writeRange(w, "range", sym.location.range);
        try w.writeByte('}');
        if (sym.container_name) |cn| {
            try w.writeByte(',');
            try protocol.json_utils.writeJsonField(w, "containerName", cn);
        }
        try w.writeByte('}');
    }
    try w.writeByte(']');
}

// ─── Tests ───────────────────────────────────────────────────

test "WorkspaceSymbol: empty query matches all" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getWorkspaceSymbols(std.testing.allocator, ast, "file:///test.ss", "");
    defer std.testing.allocator.free(symbols);
    try std.testing.expectEqual(@as(usize, 1), symbols.len);
    try std.testing.expectEqualStrings("users", symbols[0].name);
    try std.testing.expectEqual(SymbolKind.class, symbols[0].kind);
}

test "WorkspaceSymbol: query filter" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "posts",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 5,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getWorkspaceSymbols(std.testing.allocator, ast, "file:///test.ss", "user");
    defer std.testing.allocator.free(symbols);
    try std.testing.expectEqual(@as(usize, 1), symbols.len);
    try std.testing.expectEqualStrings("users", symbols[0].name);
}

test "WorkspaceSymbol: case insensitive" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "UserAccounts",
                .comment = null,
                .engine = null,
                .columns = &.{},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getWorkspaceSymbols(std.testing.allocator, ast, "file:///test.ss", "user");
    defer std.testing.allocator.free(symbols);
    try std.testing.expectEqual(@as(usize, 1), symbols.len);
}

test "WorkspaceSymbol: columns indexed" {
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
    const symbols = getWorkspaceSymbols(std.testing.allocator, ast, "file:///test.ss", "email");
    defer std.testing.allocator.free(symbols);
    try std.testing.expectEqual(@as(usize, 1), symbols.len);
    try std.testing.expectEqualStrings("email", symbols[0].name);
    try std.testing.expectEqual(SymbolKind.field, symbols[0].kind);
    try std.testing.expectEqualStrings("users", symbols[0].container_name.?);
}
