const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const utils = @import("../utils.zig");
const Writer = std.Io.Writer;
const FkDecl = ast_mod.FkDecl;

// ─── Shared Generator Helpers ────────────────────────────────
// Common utilities used by multiple generators. Eliminates
// duplicated patterns for table analysis and default formatting.

/// Count tables that have at least one non-primary-key index.
pub fn tableHasNonPkIndexes(table: typed_ast.TypedTable) bool {
    for (table.indexes) |idx| {
        if (idx.kind != .primary_key) return true;
    }
    return false;
}

/// Count tables that have at least one composite (multi-column) FK.
pub fn tableHasCompositeFks(table: typed_ast.TypedTable) bool {
    for (table.fks) |fk| {
        if (fk.fields.len > 1) return true;
    }
    return false;
}

// ─── Default Value Formatting ────────────────────────────────
// Shared by ORM generators (drizzle, knex, typeorm, sqlalchemy).
// Each generator provides language-specific formatting callbacks
// via a DefaultFormatter config struct.

/// Language-specific formatting callbacks for default values.
pub const DefaultFormatter = struct {
    /// Output for SQL `true` / `TRUE` (e.g. "true", "'true'")
    boolTrue: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `false` / `FALSE` (e.g. "false", "'false'")
    boolFalse: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `null` / `NULL` (e.g. "null", "None")
    nullValue: *const fn (w: *Writer) anyerror!void,
    /// Output for `NOW()` / `now()` / `CURRENT_TIMESTAMP`
    now: *const fn (w: *Writer) anyerror!void,
    /// Format a string default (e.g. "'foo'", `"foo"`)
    formatString: *const fn (w: *Writer, dflt: []const u8) anyerror!void,
};

/// Shared default value writer. Parses the raw SQL default value and
/// delegates formatting to language-specific callbacks.
pub fn writeFormattedDefault(w: *Writer, dflt: []const u8, fmt: DefaultFormatter) !void {
    if (std.mem.eql(u8, dflt, "true") or std.mem.eql(u8, dflt, "TRUE")) {
        try fmt.boolTrue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "false") or std.mem.eql(u8, dflt, "FALSE")) {
        try fmt.boolFalse(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "null") or std.mem.eql(u8, dflt, "NULL")) {
        try fmt.nullValue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "NOW()") or std.mem.eql(u8, dflt, "now()") or
        std.mem.eql(u8, dflt, "CURRENT_TIMESTAMP"))
    {
        try fmt.now(w);
        return;
    }
    if (std.fmt.parseInt(i64, dflt, 10)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, dflt)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}
    try fmt.formatString(w, dflt);
}

// ─── CHECK Constraint Parsers ──────────────────────────────────
// Shared by json_schema and openapi generators. Parses SS CHECK
// constraint expressions into structured ranges, comparisons, and lists.

pub const Range = struct {
    min: ?i64,
    max: ?i64,
};

pub fn parseRange(expr: []const u8) ?Range {
    var min_val: ?i64 = null;
    var max_val: ?i64 = null;

    var i: usize = 0;
    while (i < expr.len) {
        if (i + 1 < expr.len and expr[i] == '>' and expr[i + 1] == '=') {
            const num_start = i + 2;
            var num_end = num_start;
            if (num_end < expr.len and expr[num_end] == '-') num_end += 1;
            while (num_end < expr.len and (expr[num_end] >= '0' and expr[num_end] <= '9')) {
                num_end += 1;
            }
            if (num_end > num_start) {
                if (std.fmt.parseInt(i64, expr[num_start..num_end], 10)) |num| {
                    min_val = num;
                } else |_| {}
            }
            i = num_end;
        } else if (i + 1 < expr.len and expr[i] == '<' and expr[i + 1] == '=') {
            const num_start = i + 2;
            var num_end = num_start;
            if (num_end < expr.len and expr[num_end] == '-') num_end += 1;
            while (num_end < expr.len and (expr[num_end] >= '0' and expr[num_end] <= '9')) {
                num_end += 1;
            }
            if (num_end > num_start) {
                if (std.fmt.parseInt(i64, expr[num_start..num_end], 10)) |num| {
                    max_val = num;
                } else |_| {}
            }
            i = num_end;
        } else {
            i += 1;
        }
    }

    if (min_val != null or max_val != null) {
        return .{ .min = min_val, .max = max_val };
    }
    return null;
}

pub const Comparison = struct {
    op: []const u8,
    value: i64,
};

pub fn parseComparison(expr: []const u8) ?Comparison {
    var i: usize = 0;
    while (i < expr.len and expr[i] == ' ') : (i += 1) {}

    if (i < expr.len and (expr[i] == '>' or expr[i] == '<' or expr[i] == '=')) {
        const op_start = i;
        i += 1;
        if (i < expr.len and expr[i] == '=') i += 1;
        const op = expr[op_start..i];

        while (i < expr.len and expr[i] == ' ') : (i += 1) {}

        const num_start = i;
        if (i < expr.len and expr[i] == '-') i += 1;
        while (i < expr.len and ((expr[i] >= '0' and expr[i] <= '9') or expr[i] == '.')) {
            i += 1;
        }
        if (i > num_start) {
            if (std.fmt.parseInt(i64, expr[num_start..i], 10)) |num| {
                return .{ .op = op, .value = num };
            } else |_| {}
        }
    }
    return null;
}

pub fn parseInList(alloc: std.mem.Allocator, expr: []const u8) ?[]const []const u8 {
    const trimmed = std.mem.trim(u8, expr, " ");
    if (trimmed.len < 2) return null;

    const inner = if (trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')')
        trimmed[1 .. trimmed.len - 1]
    else
        trimmed;

    var items = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return null;
    var start: usize = 0;
    var in_quote = false;
    var i: usize = 0;

    while (i < inner.len) {
        if (inner[i] == '\'') {
            if (in_quote) {
                const item = std.mem.trim(u8, inner[start..i], " '");
                items.append(alloc, item) catch {
                    items.deinit(alloc);
                    return null;
                };
                in_quote = false;
                start = i + 1;
            } else {
                in_quote = true;
                start = i + 1;
            }
        } else if (inner[i] == ',' and !in_quote) {
            const item = std.mem.trim(u8, inner[start..i], " ");
            if (item.len > 0) {
                items.append(alloc, item) catch {
                    items.deinit(alloc);
                    return null;
                };
            }
            start = i + 1;
        }
        i += 1;
    }

    if (start < inner.len) {
        const item = std.mem.trim(u8, inner[start..], " '");
        if (item.len > 0) {
            items.append(alloc, item) catch {
                items.deinit(alloc);
                return null;
            };
        }
    }

    if (items.items.len == 0) {
        items.deinit(alloc);
        return null;
    }

    return items.toOwnedSlice(alloc) catch {
        items.deinit(alloc);
        return null;
    };
}

// ─── JSON Value Writer ────────────────────────────────────────

pub fn writeJsonValue(w: *Writer, val: []const u8) !void {
    if (std.mem.eql(u8, val, "NULL") or std.mem.eql(u8, val, "null")) {
        try w.writeAll("null");
    } else if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "TRUE")) {
        try w.writeAll("true");
    } else if (std.mem.eql(u8, val, "false") or std.mem.eql(u8, val, "FALSE")) {
        try w.writeAll("false");
    } else if (std.fmt.parseInt(i64, val, 10)) |num| {
        try w.print("{d}", .{num});
    } else |_| {
        if (std.fmt.parseFloat(f64, val)) |num| {
            try w.print("{d}", .{num});
        } else |_| {
            try w.writeAll("\"");
            try utils.jsonEscapeString(w, val);
            try w.writeAll("\"");
        }
    }
}

// ─── FK Reference Lookup ──────────────────────────────────────

pub fn findFkRefTable(col_name: []const u8, fks: []const FkDecl) ?[]const u8 {
    for (fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col_name)) {
            return fk.ref_table;
        }
    }
    return null;
}
