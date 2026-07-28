const std = @import("std");
const diag = @import("diagnostic.zig");

const testing = std.testing;

test "tokenColumn: basic" {
    try testing.expectEqual(@as(usize, 1), diag.tokenColumn("hello", "hello world"));
    try testing.expectEqual(@as(usize, 7), diag.tokenColumn("world", "hello world"));
    try testing.expectEqual(@as(usize, 3), diag.tokenColumn("world", "  world"));
}

test "tokenColumn: empty inputs" {
    try testing.expectEqual(@as(usize, 1), diag.tokenColumn("", "hello"));
    try testing.expectEqual(@as(usize, 1), diag.tokenColumn("hello", ""));
    try testing.expectEqual(@as(usize, 1), diag.tokenColumn("", ""));
}

test "DiagnosticCollector: init starts empty" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push warning" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "test warning" });
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push error" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .@"error", .line_no = 5, .message = "test error" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 1), dc.errorCount());
}

test "DiagnosticCollector: mixed severity" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "w1" });
    dc.push(.{ .severity = .@"error", .line_no = 2, .message = "e1" });
    dc.push(.{ .severity = .warning, .line_no = 3, .message = "w2" });
    dc.push(.{ .severity = .@"error", .line_no = 4, .message = "e2" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 2), dc.errorCount());
}

test "DiagnosticCollector: formatJson" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .@"error", .line_no = 10, .col = 5, .message = "syntax error" });

    var buf = try std.ArrayList(u8).initCapacity(testing.allocator, 256);
    defer buf.deinit();

    const writer = buf.writer();
    try dc.formatJson(writer);
    const json = try buf.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(json);

    // Verify JSON contains expected fields
    try testing.expect(std.mem.indexOf(u8, json, "\"severity\":\"error\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"line\":10") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"col\":5") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"message\":\"syntax error\"") != null);
}

test "DiagnosticCollector: formatJson with expected/actual" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{
        .severity = .@"error",
        .line_no = 1,
        .message = "type mismatch",
        .expected = "integer",
        .actual = "string",
    });

    var buf = try std.ArrayList(u8).initCapacity(testing.allocator, 256);
    defer buf.deinit();

    try dc.formatJson(buf.writer());
    const json = try buf.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"expected\":\"integer\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"actual\":\"string\"") != null);
}

test "DiagnosticCollector: formatLsp produces LSP-compatible output" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .@"error", .line_no = 10, .col = 5, .message = "syntax error" });
    dc.push(.{ .severity = .warning, .line_no = 20, .col = 1, .message = "unused variable" });

    var buf = try std.ArrayList(u8).initCapacity(testing.allocator, 512);
    defer buf.deinit();

    try dc.formatLsp(buf.writer());
    const lsp = try buf.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(lsp);

    // Verify LSP structure
    try testing.expect(std.mem.indexOf(u8, lsp, "\"range\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"severity\": 1") != null); // Error
    try testing.expect(std.mem.indexOf(u8, lsp, "\"severity\": 2") != null); // Warning
    try testing.expect(std.mem.indexOf(u8, lsp, "\"source\": \"rune\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"message\": \"syntax error\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"message\": \"unused variable\"") != null);
}

test "DiagnosticCollector: formatJson empty" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);

    var buf = try std.ArrayList(u8).initCapacity(testing.allocator, 64);
    defer buf.deinit();

    try dc.formatJson(buf.writer());
    const json = try buf.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expectEqualStrings("[\n]", json);
}

test "DiagnosticCollector: max_errors stops recording" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.max_errors = 3;

    // Push 5 errors — only first 3 should be recorded
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        dc.push(.{ .severity = .@"error", .line_no = i, .message = "error" });
    }

    try testing.expectEqual(@as(usize, 3), dc.diagnostics.items.len);
    try testing.expect(dc.overflow);
}

test "DiagnosticCollector: max_errors does not limit warnings" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.max_errors = 2;

    // Push 2 errors + 5 warnings — all should be recorded
    dc.push(.{ .severity = .@"error", .line_no = 1, .message = "e1" });
    dc.push(.{ .severity = .@"error", .line_no = 2, .message = "e2" });
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        dc.push(.{ .severity = .warning, .line_no = i + 10, .message = "w" });
    }

    try testing.expectEqual(@as(usize, 7), dc.diagnostics.items.len);
    try testing.expect(!dc.overflow);
}
