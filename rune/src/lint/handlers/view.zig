const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── View Validation Rules ────────────────────────────────────
// Rules that validate view quality: missing SELECT, missing aliases,
// and SELECT * usage.

pub fn checkViewNoSelect(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    if (!cfg.include_views) return;
    for (ast.views) |view| {
        // Check if view query is empty or doesn't contain SELECT
        const query = view.query;
        if (query.len == 0) {
            const msg = try std.fmt.allocPrint(alloc, "view '{s}' has empty query", .{view.name});
            try results.append(alloc, .{
                .rule = "view-no-select",
                .table = view.name,
                .message = msg,
                .severity = .warning,
            });
            continue;
        }
        // Case-insensitive check for SELECT keyword
        if (!containsIgnoreCase(query, "select")) {
            const msg = try std.fmt.allocPrint(alloc, "view '{s}' query does not contain SELECT statement", .{view.name});
            try results.append(alloc, .{
                .rule = "view-no-select",
                .table = view.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

pub fn checkViewNoAlias(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    if (!cfg.include_views) return;
    for (ast.views) |view| {
        // Check if view has SELECT with expressions that lack aliases
        // This is a heuristic: if SELECT contains function calls or arithmetic without AS, warn
        const select = view.query;
        // Look for patterns like "COUNT(*)" or "a + b" without "AS alias"
        var i: usize = 0;
        while (i < select.len) {
            // Skip whitespace
            while (i < select.len and select[i] == ' ') i += 1;
            if (i >= select.len) break;

            // Check for function call pattern: word(
            const start = i;
            while (i < select.len and select[i] != ' ' and select[i] != ',') i += 1;
            const token = select[start..i];

            // Check if token contains a function call (has '(' but no 'AS' following)
            if (std.mem.indexOf(u8, token, "(")) |_| {
                // Check if there's an AS alias after the closing paren
                var j = i;
                while (j < select.len and select[j] == ' ') j += 1;
                // Check if next token is NOT "AS" or "as"
                const remaining = select[j..];
                if (!std.mem.startsWith(u8, remaining, "AS ") and !std.mem.startsWith(u8, remaining, "as ")) {
                    const msg = try std.fmt.allocPrint(alloc, "view '{s}' SELECT expression '{s}' lacks a column alias — add 'AS alias_name'", .{ view.name, token });
                    try results.append(alloc, .{
                        .rule = "view-no-alias",
                        .table = view.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            }

            // Skip to next comma
            while (i < select.len and select[i] != ',') i += 1;
            if (i < select.len) i += 1; // skip comma
        }
    }
}

pub fn checkViewSelectStar(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    if (!cfg.include_views) return;
    for (ast.views) |view| {
        const query = view.query;
        if (query.len == 0) continue;
        // Check for SELECT * pattern (case-insensitive)
        if (containsIgnoreCase(query, "select *") or containsIgnoreCase(query, "select\t*") or containsIgnoreCase(query, "select\n*")) {
            const msg = try std.fmt.allocPrint(alloc, "view '{s}' uses SELECT * — prefer explicit column list for portability and schema evolution", .{view.name});
            try results.append(alloc, .{
                .rule = "view-select-star",
                .table = view.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const end = haystack.len - needle.len + 1;
    var i: usize = 0;
    while (i < end) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}
