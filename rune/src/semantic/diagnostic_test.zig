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

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try dc.formatJson(&aw.writer);
    try aw.writer.flush();
    const json = try aw.toOwnedSlice();
    defer testing.allocator.free(json);

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

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try dc.formatJson(&aw.writer);
    try aw.writer.flush();
    const json = try aw.toOwnedSlice();
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"expected\":\"integer\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"actual\":\"string\"") != null);
}

test "DiagnosticCollector: formatLsp produces LSP-compatible output" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .@"error", .line_no = 10, .col = 5, .message = "syntax error" });
    dc.push(.{ .severity = .warning, .line_no = 20, .col = 1, .message = "unused variable" });

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try dc.formatLsp(&aw.writer);
    try aw.writer.flush();
    const lsp = try aw.toOwnedSlice();
    defer testing.allocator.free(lsp);

    try testing.expect(std.mem.indexOf(u8, lsp, "\"range\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"severity\": 1") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"severity\": 2") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"source\": \"rune\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"message\": \"syntax error\"") != null);
    try testing.expect(std.mem.indexOf(u8, lsp, "\"message\": \"unused variable\"") != null);
}

test "DiagnosticCollector: formatJson empty" {
    var dc = try diag.DiagnosticCollector.init(testing.allocator);

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try dc.formatJson(&aw.writer);
    try aw.writer.flush();
    const json = try aw.toOwnedSlice();
    defer testing.allocator.free(json);

    try testing.expectEqualStrings("[\n]", json);
}
