const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── View Validation Rules ────────────────────────────────────
// Rules that validate view quality: missing SELECT, missing aliases,
// and SELECT * usage.

pub fn checkViewNoComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    if (!cfg.include_views) return;
    for (ast.views) |view| {
        if (view.comment == null or (view.comment != null and view.comment.?.len == 0)) {
            const msg = try std.fmt.allocPrint(alloc, "view '{s}' has no comment", .{view.name});
            try results.append(alloc, .{
                .rule = "view-no-comment",
                .table = view.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

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

pub fn checkViewDependencyCycle(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    if (!cfg.include_views) return;
    if (ast.views.len < 2) return;

    // Build dependency graph: view_name -> list of referenced view names
    var deps = std.StringHashMap(std.ArrayList([]const u8)).init(alloc);
    defer {
        var iter = deps.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(alloc);
        }
        deps.deinit();
    }

    for (ast.views) |view| {
        var view_deps = try std.ArrayList([]const u8).initCapacity(alloc, 4);
        // Check if view query references other views
        for (ast.views) |other| {
            if (std.mem.eql(u8, view.name, other.name)) continue;
            if (containsIgnoreCase(view.query, other.name)) {
                try view_deps.append(alloc, other.name);
            }
        }
        try deps.put(view.name, view_deps);
    }

    // Detect cycles using DFS
    var visited = std.StringHashMap(void).init(alloc);
    defer visited.deinit();
    var in_stack = std.StringHashMap(void).init(alloc);
    defer in_stack.deinit();

    for (ast.views) |view| {
        if (visited.contains(view.name)) continue;
        try detectCycle(alloc, view.name, &deps, &visited, &in_stack, results);
    }
}

fn detectCycle(
    alloc: std.mem.Allocator,
    node: []const u8,
    deps: *const std.StringHashMap(std.ArrayList([]const u8)),
    visited: *std.StringHashMap(void),
    in_stack: *std.StringHashMap(void),
    results: *std.ArrayList(LintResult),
) !void {
    if (in_stack.contains(node)) {
        // Found a cycle
        const msg = try std.fmt.allocPrint(alloc, "view '{s}' is part of a dependency cycle", .{node});
        try results.append(alloc, .{
            .rule = "view-dependency-cycle",
            .table = node,
            .message = msg,
            .severity = .warning,
        });
        return;
    }
    if (visited.contains(node)) return;

    try visited.put(node, {});
    try in_stack.put(node, {});

    if (deps.get(node)) |node_deps| {
        for (node_deps.items) |dep| {
            try detectCycle(alloc, dep, deps, visited, in_stack, results);
        }
    }

    _ = in_stack.fetchRemove(node);
}
