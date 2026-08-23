const std = @import("std");
const color = @import("color.zig");

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
    /// Enable ANSI color output for this diagnostic.
    use_color: bool = false,
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
    const c = d.use_color;
    const sev_str: []const u8 = switch (d.severity) {
        .warning => "warning",
        .@"error" => "error",
        .note => "note",
    };
    const sev_color: []const u8 = switch (d.severity) {
        .warning => color.YELLOW,
        .@"error" => color.RED,
        .note => color.GRAY,
    };

    // Header: "warning: message — expected '...', got '...'"
    if (c) try w.writeAll(sev_color);
    try w.writeAll(sev_str);
    if (c) try w.writeAll(color.RESET);
    if (d.expected) |exp| {
        if (d.actual) |act| {
            try w.print(": {s} — expected {s}, got '{s}'\n", .{ d.message, exp, act });
        } else {
            try w.print(": {s} — expected {s}\n", .{ d.message, exp });
        }
    } else if (d.actual) |act| {
        try w.print(": {s}, got '{s}'\n", .{ d.message, act });
    } else {
        try w.print(": {s}\n", .{d.message});
    }

    // Location: "  --> file:line:col"
    if (c) try w.writeAll(color.DIM);
    if (d.col) |col| {
        try w.print("  --> {s}:{d}:{d}\n", .{ d.file, d.line_no, col });
    } else {
        try w.print("  --> {s}:{d}\n", .{ d.file, d.line_no });
    }
    if (c) try w.writeAll(color.RESET);

    // Source context with caret pointer
    if (d.source_line) |raw| {
        if (c) try w.writeAll(color.DIM);
        try w.writeAll("   |\n");
        if (c) try w.writeAll(color.RESET);
        if (c) try w.writeAll(color.BOLD);
        try w.print(" {d} | ", .{d.line_no});
        if (c) try w.writeAll(color.RESET);
        try w.print("{s}\n", .{raw});
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
            if (c) try w.writeAll(sev_color);
            var k: usize = 0;
            while (k < width) : (k += 1) {
                try w.writeAll("^");
            }
            if (c) try w.writeAll(color.RESET);
            try w.writeAll("\n");
        }
    }
}

pub fn printDiagnostic(alloc: std.mem.Allocator, d: Diagnostic) void {
    // WASM builds have no stderr; std.debug.print's locked-writer path
    // overflows the stack there. Errors surface via rune_last_error().
    if (comptime @import("builtin").target.cpu.arch.isWasm()) return;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    formatDiagnosticTo(w, d) catch {
        aw.deinit();
        return;
    };
    var out = aw.toArrayList();
    defer out.deinit(alloc);
    std.debug.print("{s}", .{out.items});
}

/// Print a diagnostic with color support.
fn printDiagnosticColor(alloc: std.mem.Allocator, d: Diagnostic, use_color: bool) void {
    var diag = d;
    diag.use_color = use_color;
    printDiagnostic(alloc, diag);
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
    oom: bool = false,
    json_errors: bool = false,
    use_color: bool = false,
    cached_error_count: usize = 0,

    pub fn init(alloc: std.mem.Allocator) !DiagnosticCollector {
        return .{
            .diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 8),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *DiagnosticCollector) void {
        self.diagnostics.deinit(self.alloc);
    }

    /// Record a diagnostic (warning, error, or note).
    /// Stops recording when max_errors is exceeded.
    /// Sets `oom` flag if allocation fails — callers can check `hadOom()`.
    pub fn push(self: *DiagnosticCollector, d: Diagnostic) void {
        if (self.overflow) return;
        if (d.severity == .@"error" and self.cached_error_count >= self.max_errors) {
            self.overflow = true;
            return;
        }
        if (d.severity == .@"error") self.cached_error_count += 1;
        var diag = d;
        diag.use_color = self.use_color;
        self.diagnostics.append(self.alloc, diag) catch {
            self.oom = true;
        };
    }

    /// Record a diagnostic (alias for push). Prefer push() for new code.
    pub fn record(self: *DiagnosticCollector, d: Diagnostic) void {
        self.push(d);
    }

    /// Returns true if any error-severity diagnostics have been recorded.
    pub fn hasErrors(self: *const DiagnosticCollector) bool {
        return self.cached_error_count > 0;
    }

    /// Returns the count of error-severity diagnostics.
    pub fn errorCount(self: *const DiagnosticCollector) usize {
        return self.cached_error_count;
    }

    /// Returns true if any diagnostics were dropped due to allocation failure.
    pub fn hadOom(self: *const DiagnosticCollector) bool {
        return self.oom;
    }

    /// Print all collected diagnostics.
    pub fn printAll(self: *const DiagnosticCollector) void {
        if (self.json_errors) {
            var aw = std.Io.Writer.Allocating.init(self.alloc);
            self.formatJson(&aw.writer) catch return;
            aw.writer.flush() catch return;
            if (aw.toOwnedSlice()) |json| {
                defer self.alloc.free(json);
                std.debug.print("{s}\n", .{json});
            } else |_| {}
            return;
        }
        for (self.diagnostics.items) |d| {
            printDiagnostic(self.alloc, d);
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
        if (self.diagnostics.items.len > 0) try writer.writeAll("\n");
        try writer.writeAll("]");
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

    /// Format all diagnostics as LSP Diagnostic objects to the given writer.
    /// Each diagnostic includes range (start/end), severity, message, and source.
    pub fn formatLsp(self: *const DiagnosticCollector, writer: anytype) !void {
        try writer.writeAll("[\n");
        for (self.diagnostics.items, 0..) |d, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("  {\n");
            // range
            try writer.writeAll("    \"range\": {\n");
            try writer.writeAll("      \"start\": {\"line\": ");
            try writer.print("{d}", .{if (d.line_no > 0) d.line_no - 1 else 0});
            try writer.writeAll(", \"character\": ");
            try writer.print("{d}", .{if (d.col) |c| c -| 1 else 0});
            try writer.writeAll("},\n");
            try writer.writeAll("      \"end\": {\"line\": ");
            try writer.print("{d}", .{if (d.line_no > 0) d.line_no - 1 else 0});
            try writer.writeAll(", \"character\": ");
            try writer.print("{d}", .{if (d.col) |c| c -| 1 else 0});
            try writer.writeAll("}\n");
            try writer.writeAll("    },\n");
            // severity (1=Error, 2=Warning, 3=Information)
            try writer.writeAll("    \"severity\": ");
            switch (d.severity) {
                .@"error" => try writer.writeAll("1"),
                .warning => try writer.writeAll("2"),
                .note => try writer.writeAll("3"),
            }
            try writer.writeAll(",\n");
            // message
            try writer.writeAll("    \"message\": \"");
            // Escape JSON in message
            for (d.message) |ch| {
                switch (ch) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(ch),
                }
            }
            try writer.writeAll("\",\n");
            // source
            try writer.writeAll("    \"source\": \"rune\"\n");
            try writer.writeAll("  }");
        }
        try writer.writeAll("\n]\n");
    }
};
