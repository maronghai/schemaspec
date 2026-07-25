const std = @import("std");

pub const Severity = enum {
    warning,
    @"error",
    note,
};

pub const Diagnostic = struct {
    severity: Severity,
    line_no: usize,
    col: ?usize = null,
    file: []const u8 = "input.ss",
    message: []const u8,
    expected: ?[]const u8 = null,
    actual: ?[]const u8 = null,
    source_line: ?[]const u8 = null,
};

/// Compute 1-based column of `tok` within `raw_line`.
/// Since tokens are sub-slices of the trimmed line (separate allocation from raw_line),
/// we use safe string slicing instead of pointer arithmetic.
pub fn tokenColumn(tok: []const u8, raw_line: []const u8) usize {
    if (raw_line.len == 0 or tok.len == 0) return 1;
    // Find where trimmed content starts (skip leading spaces/tabs)
    var trim_start: usize = 0;
    while (trim_start < raw_line.len and (raw_line[trim_start] == ' ' or raw_line[trim_start] == '\t')) {
        trim_start += 1;
    }
    // The trimmed portion is a separate allocation whose tokens include `tok`.
    // Search for tok within the trimmed portion of raw_line.
    const trimmed_part = raw_line[trim_start..];
    if (std.mem.indexOf(u8, trimmed_part, tok)) |pos| {
        return trim_start + pos + 1;
    }
    return 1;
}

/// Format a single diagnostic to any writer. Shared by printDiagnostic and formatTerminal.
fn formatDiagnosticTo(w: anytype, d: Diagnostic) !void {
    const sev_str: []const u8 = switch (d.severity) {
        .warning => "warning",
        .@"error" => "error",
        .note => "note",
    };

    // Header: "warning: message — expected '...', got '...'"
    if (d.expected) |exp| {
        if (d.actual) |act| {
            try w.print("{s}: {s} — expected {s}, got '{s}'\n", .{ sev_str, d.message, exp, act });
        } else {
            try w.print("{s}: {s} — expected {s}\n", .{ sev_str, d.message, exp });
        }
    } else if (d.actual) |act| {
        try w.print("{s}: {s}, got '{s}'\n", .{ sev_str, d.message, act });
    } else {
        try w.print("{s}: {s}\n", .{ sev_str, d.message });
    }

    // Location: "  --> file:line:col"
    if (d.col) |col| {
        try w.print("  --> {s}:{d}:{d}\n", .{ d.file, d.line_no, col });
    } else {
        try w.print("  --> {s}:{d}\n", .{ d.file, d.line_no });
    }

    // Source context with caret pointer
    if (d.source_line) |raw| {
        try w.writeAll("   |\n");
        try w.print(" {d} | {s}\n", .{ d.line_no, raw });
        if (d.col) |col| {
            const indent = digitCount(d.line_no) + 3; // " N | " prefix width
            var j: usize = 0;
            while (j < indent + col - 1) : (j += 1) {
                try w.writeAll(" ");
            }
            const width: usize = if (d.actual) |a| blk: {
                if (std.mem.indexOfScalar(u8, a, ' ') != null or a.len > 20) break :blk 1;
                break :blk a.len;
            } else 1;
            var k: usize = 0;
            while (k < width) : (k += 1) {
                try w.writeAll("^");
            }
            try w.writeAll("\n");
        }
    }
}

pub fn printDiagnostic(d: Diagnostic) void {
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    const w = &aw.writer;
    formatDiagnosticTo(w, d) catch return;
    const out = aw.toArrayList();
    std.debug.print("{s}", .{out.items});
}

fn digitCount(n: usize) usize {
    if (n == 0) return 1;
    var count: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) {
        count += 1;
    }
    return count;
}

// ─── Diagnostic Collector (Phase 4: Error Recovery) ──────────

/// Collects diagnostics during compilation, allowing continued parsing after errors.
pub const DiagnosticCollector = struct {
    diagnostics: std.ArrayList(Diagnostic),
    alloc: std.mem.Allocator,
    max_errors: usize = 100,
    overflow: bool = false,

    pub fn init(alloc: std.mem.Allocator) !DiagnosticCollector {
        return .{
            .diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 8),
            .alloc = alloc,
        };
    }

    /// Record a diagnostic (warning, error, or note).
    /// Stops recording when max_errors is exceeded.
    pub fn push(self: *DiagnosticCollector, d: Diagnostic) void {
        if (self.overflow) return;
        if (d.severity == .@"error" and self.errorCount() >= self.max_errors) {
            self.overflow = true;
            std.debug.print("error: too many errors ({d}), stopping\n", .{self.max_errors});
            return;
        }
        self.diagnostics.append(self.alloc, d) catch {};
    }

    /// Record a diagnostic using the existing printDiagnostic + store pattern.
    pub fn record(self: *DiagnosticCollector, d: Diagnostic) void {
        printDiagnostic(d);
        self.push(d);
    }

    /// Returns true if any error-severity diagnostics have been recorded.
    pub fn hasErrors(self: *const DiagnosticCollector) bool {
        for (self.diagnostics.items) |d| {
            if (d.severity == .@"error") return true;
        }
        return false;
    }

    /// Returns the count of error-severity diagnostics.
    pub fn errorCount(self: *const DiagnosticCollector) usize {
        var count: usize = 0;
        for (self.diagnostics.items) |d| {
            if (d.severity == .@"error") count += 1;
        }
        return count;
    }

    /// Print all collected diagnostics.
    pub fn printAll(self: *const DiagnosticCollector) void {
        for (self.diagnostics.items) |d| {
            printDiagnostic(d);
        }
    }

    /// Take ownership of the diagnostics slice (for returning from parsers).
    pub fn toOwnedSlice(self: *DiagnosticCollector, alloc: std.mem.Allocator) ![]const Diagnostic {
        return try self.diagnostics.toOwnedSlice(alloc);
    }

    /// Print a summary line after all diagnostics.
    pub fn printSummary(self: *const DiagnosticCollector) void {
        const errs = self.errorCount();
        const warns: usize = blk: {
            var w: usize = 0;
            for (self.diagnostics.items) |d| {
                if (d.severity == .warning) w += 1;
            }
            break :blk w;
        };
        if (errs > 0 or warns > 0) {
            std.debug.print("\n{d} error(s), {d} warning(s)\n", .{ errs, warns });
        }
    }

    /// Format all diagnostics as a JSON array to the given writer.
    /// Useful for LSP integration and machine-readable output.
    pub fn formatJson(self: *const DiagnosticCollector, writer: anytype) !void {
        try writer.writeAll("[\n");
        for (self.diagnostics.items, 0..) |d, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("  {");
            // severity
            try writer.writeAll("\"severity\":\"");
            switch (d.severity) {
                .@"error" => try writer.writeAll("error"),
                .warning => try writer.writeAll("warning"),
                .note => try writer.writeAll("note"),
            }
            try writer.writeAll("\"");
            // line_no
            try writer.print(",\"line\":{d}", .{d.line_no});
            // col (optional)
            if (d.col) |col| {
                try writer.print(",\"col\":{d}", .{col});
            }
            // file
            try writer.print(",\"file\":\"{s}\"", .{d.file});
            // message
            try writer.print(",\"message\":\"{s}\"", .{d.message});
            // expected (optional)
            if (d.expected) |exp| {
                try writer.print(",\"expected\":\"{s}\"", .{exp});
            }
            // actual (optional)
            if (d.actual) |act| {
                try writer.print(",\"actual\":\"{s}\"", .{act});
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("\n]");
    }

    /// Format all diagnostics in terminal-friendly format with colors and source context.
    pub fn formatTerminal(self: *const DiagnosticCollector, writer: anytype) !void {
        for (self.diagnostics.items) |d| {
            try formatDiagnosticTo(writer, d);
        }
        // Summary
        const errs = self.errorCount();
        var warns: usize = 0;
        for (self.diagnostics.items) |d| {
            if (d.severity == .warning) warns += 1;
        }
        if (errs > 0 or warns > 0) {
            try writer.print("\n{d} error(s), {d} warning(s)\n", .{ errs, warns });
        }
    }
};

// ─── Unit Tests ─────────────────────────────────────────────

const testing = std.testing;

test "tokenColumn: basic" {
    try testing.expectEqual(@as(usize, 1), tokenColumn("hello", "hello world"));
    try testing.expectEqual(@as(usize, 7), tokenColumn("world", "hello world"));
    try testing.expectEqual(@as(usize, 3), tokenColumn("world", "  world"));
}

test "tokenColumn: empty inputs" {
    try testing.expectEqual(@as(usize, 1), tokenColumn("", "hello"));
    try testing.expectEqual(@as(usize, 1), tokenColumn("hello", ""));
    try testing.expectEqual(@as(usize, 1), tokenColumn("", ""));
}

test "DiagnosticCollector: init starts empty" {
    var dc = try DiagnosticCollector.init(testing.allocator);
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push warning" {
    var dc = try DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "test warning" });
    try testing.expect(!dc.hasErrors());
    try testing.expectEqual(@as(usize, 0), dc.errorCount());
}

test "DiagnosticCollector: push error" {
    var dc = try DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .@"error", .line_no = 5, .message = "test error" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 1), dc.errorCount());
}

test "DiagnosticCollector: mixed severity" {
    var dc = try DiagnosticCollector.init(testing.allocator);
    dc.push(.{ .severity = .warning, .line_no = 1, .message = "w1" });
    dc.push(.{ .severity = .@"error", .line_no = 2, .message = "e1" });
    dc.push(.{ .severity = .warning, .line_no = 3, .message = "w2" });
    dc.push(.{ .severity = .@"error", .line_no = 4, .message = "e2" });
    try testing.expect(dc.hasErrors());
    try testing.expectEqual(@as(usize, 2), dc.errorCount());
}

test "DiagnosticCollector: formatJson" {
    var dc = try DiagnosticCollector.init(testing.allocator);
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
    var dc = try DiagnosticCollector.init(testing.allocator);
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

test "DiagnosticCollector: formatJson empty" {
    var dc = try DiagnosticCollector.init(testing.allocator);

    var buf = try std.ArrayList(u8).initCapacity(testing.allocator, 64);
    defer buf.deinit();

    try dc.formatJson(buf.writer());
    const json = try buf.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expectEqualStrings("[\n]", json);
}

test "DiagnosticCollector: max_errors stops recording" {
    var dc = try DiagnosticCollector.init(testing.allocator);
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
    var dc = try DiagnosticCollector.init(testing.allocator);
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
