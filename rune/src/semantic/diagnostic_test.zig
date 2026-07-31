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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "test warning" });
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    dc.push(.{ .severity = .@"error", .line_no = 5, .message = "test error" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 1), dc.errorCount());
}

test "DiagnosticCollector: mixed severity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "w1" });
    dc.push(.{ .severity = .@"error", .line_no = 2, .message = "e1" });
    dc.push(.{ .severity = .warning, .line_no = 3, .message = "w2" });
    dc.push(.{ .severity = .@"error", .line_no = 4, .message = "e2" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 2), dc.errorCount());
}

test "DiagnosticCollector: formatJson" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
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

test "DiagnosticCollector: overflow stops at max_errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    dc.max_errors = 5;
    // Push exactly 5 errors
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        dc.push(.{ .severity = .@"error", .line_no = i, .message = "err" });
    }
    try testing.expectEqual(@as(usize, 5), dc.errorCount());
    try testing.expect(!dc.overflow);
    // 6th error should trigger overflow
    dc.push(.{ .severity = .@"error", .line_no = 5, .message = "overflow" });
    try testing.expect(dc.overflow);
    try testing.expectEqual(@as(usize, 5), dc.errorCount());
    // Subsequent errors should be dropped
    dc.push(.{ .severity = .@"error", .line_no = 6, .message = "dropped" });
    try testing.expectEqual(@as(usize, 5), dc.errorCount());
}

test "DiagnosticCollector: warnings don't count toward max_errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());
    dc.max_errors = 2;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        dc.push(.{ .severity = .warning, .line_no = i, .message = "warn" });
    }
    try testing.expect(!dc.overflow);
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: formatJson empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var dc = try diag.DiagnosticCollector.init(arena.allocator());

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try dc.formatJson(&aw.writer);
    try aw.writer.flush();
    const json = try aw.toOwnedSlice();
    defer testing.allocator.free(json);

    try testing.expectEqualStrings("[\n]", json);
}
