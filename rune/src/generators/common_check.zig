const std = @import("std");

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
