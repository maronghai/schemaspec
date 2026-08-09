const std = @import("std");
const protocol = @import("protocol.zig");
const testing = std.testing;

// ─── Write Function Tests ──────────────────────────────────────

test "writeNotification: produces valid JSON-RPC notification" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeNotification(&aw.writer, "textDocument/publishDiagnostics", .{});

    const output = aw.written();
    // Should contain "method" field
    try testing.expect(std.mem.indexOf(u8, output, "\"method\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "textDocument/publishDiagnostics") != null);
    // Notifications have no "id" field
    try testing.expect(std.mem.indexOf(u8, output, "\"id\"") == null);
}

test "writeRange: produces correct JSON" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeRange(&aw.writer, "range", .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 1, .character = 10 },
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"line\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"character\"") != null);
}

test "writeDocumentSymbol: produces valid symbol" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeDocumentSymbol(&aw.writer, .{
        .name = "users",
        .detail = "table",
        .kind = .struct_kind,
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 5, .character = 1 },
        },
        .selection_range = .{
            .start = .{ .line = 0, .character = 6 },
            .end = .{ .line = 0, .character = 11 },
        },
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"table\"") != null);
}

test "writeCompletionList: produces valid list" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeCompletionList(&aw.writer, .{
        .is_incomplete = false,
        .items = &[_]protocol.CompletionItem{
            .{
                .label = "users",
                .kind = .struct_kind,
            },
        },
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"isIncomplete\"") != null);
}

test "writeHover: produces valid hover" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeHover(&aw.writer, .{
        .contents = .{ .kind = .markdown, .value = "Table: users" },
        .range = null,
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "Table: users") != null);
}

test "writeLocation: produces valid location" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeLocation(&aw.writer, .{
        .uri = "file:///tmp/schema.ss",
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 0, .character = 5 },
        },
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "file:///tmp/schema.ss") != null);
}

test "writeTextEdit: produces valid edit" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeTextEdit(&aw.writer, .{
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 0, .character = 5 },
        },
        .new_text = "posts",
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"posts\"") != null);
}

test "writeDocumentHighlight: produces valid highlight" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeDocumentHighlight(&aw.writer, .{
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 0, .character = 5 },
        },
        .kind = .read,
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"range\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"kind\"") != null);
}

test "writeReference: produces valid reference" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeReference(&aw.writer, .{
        .range = .{
            .start = .{ .line = 5, .character = 0 },
            .end = .{ .line = 5, .character = 10 },
        },
        .is_definition = true,
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"range\"") != null);
}

test "writeCodeAction: produces valid code action" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeCodeAction(&aw.writer, .{
        .title = "Add primary key",
        .kind = .quick_fix,
        .diagnostics = &[_]protocol.Diagnostic{},
    }, "file:///tmp/schema.ss");

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"Add primary key\"") != null);
}

test "writeCompletionItem: produces valid item" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try protocol.writeCompletionItem(&aw.writer, .{
        .label = "table",
        .kind = .keyword,
        .detail = "Table declaration",
    });

    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"table\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"Table declaration\"") != null);
}
