const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── FK Validation Rules ──────────────────────────────────────
// Rules that validate foreign key integrity: indexes, cascades,
// nullability, self-references, and circular dependencies.

pub fn checkNoIndexFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.fk != null and !fieldHasIndex(table, field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "foreign key column '{s}' has no index", .{field.name});
                try results.append(alloc, .{
                    .rule = "no-index-fk",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

pub fn checkFkCascade(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.fk) |fk| {
                var has_delete = false;
                var has_update = false;
                for (fk.actions) |action| {
                    if (action.trigger == .on_delete) has_delete = true;
                    if (action.trigger == .on_update) has_update = true;
                }
                if (!has_delete or !has_update) {
                    const msg = if (!has_delete and !has_update)
                        try std.fmt.allocPrint(alloc, "FK column '{s}' has no explicit ON DELETE/ON UPDATE actions", .{field.name})
                    else if (!has_delete)
                        try std.fmt.allocPrint(alloc, "FK column '{s}' has no explicit ON DELETE action", .{field.name})
                    else
                        try std.fmt.allocPrint(alloc, "FK column '{s}' has no explicit ON UPDATE action", .{field.name});
                    try results.append(alloc, .{
                        .rule = "fk-cascade",
                        .table = table.name,
                        .message = msg,
                        .severity = .info,
                    });
                }
            }
        }
    }
}

pub fn checkFkNull(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            // Check if field has a FK reference
            var has_fk = false;
            for (table.fks) |fk| {
                for (fk.fields) |col| {
                    if (std.mem.eql(u8, col, field.name)) {
                        has_fk = true;
                        break;
                    }
                }
                if (has_fk) break;
            }
            if (!has_fk) continue;

            // Check if FK column is nullable
            for (field.modifiers) |mod| {
                if (mod.kind == .nullable) {
                    const msg = try std.fmt.allocPrint(alloc, "foreign key column '{s}' is nullable — FK columns should typically be NOT NULL", .{field.name});
                    try results.append(alloc, .{
                        .rule = "fk-null",
                        .table = table.name,
                        .message = msg,
                        .severity = .info,
                    });
                    break;
                }
            }
        }
    }
}

pub fn checkFkSelfReference(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            // Check if FK references the same table
            if (std.mem.eql(u8, table.name, fk.ref_table)) {
                const msg = try std.fmt.allocPrint(alloc, "table '{s}' has a self-referencing foreign key — consider if this is intentional (hierarchical data pattern)", .{table.name});
                try results.append(alloc, .{
                    .rule = "fk-self-reference",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkCircularFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    var graph = std.StringHashMap(std.ArrayList([]const u8)).init(alloc);
    defer {
        var iter = graph.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(alloc);
        }
        graph.deinit();
    }

    for (ast.tables) |table| {
        var targets = try std.ArrayList([]const u8).initCapacity(alloc, 4);
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try targets.append(alloc, fk.ref_table);
            }
        }
        try graph.put(table.name, targets);
    }

    var visited = std.StringHashMap(void).init(alloc);
    defer visited.deinit();
    var path = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    defer path.deinit(alloc);

    for (ast.tables) |table| {
        if (!visited.contains(table.name)) {
            try detectCircularFkDfs(alloc, &visited, &path, &graph, table.name, results);
        }
    }
}

pub fn checkFkDepth(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    const max_depth = 3;

    // Build a map of table name -> FK target
    var graph = std.StringHashMap([]const u8).init(alloc);
    defer graph.deinit();

    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.fk) |fk| {
                try graph.put(field.name, fk.ref_table);
            }
        }
    }

    // For each FK column, compute the depth of the reference chain
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.fk == null) continue;

            var depth: u32 = 0;
            var current_table = table.name;
            var visited = std.StringHashMap(void).init(alloc);
            defer visited.deinit();

            // Walk the FK chain
            while (depth < max_depth + 1) : (depth += 1) {
                if (visited.contains(current_table)) break; // circular, already detected by circular-fk
                try visited.put(current_table, {});

                // Find FK from current_table
                var found = false;
                for (ast.tables) |t| {
                    if (std.mem.eql(u8, t.name, current_table)) {
                        for (t.fields) |f| {
                            if (f.fk) |fk| {
                                current_table = fk.ref_table;
                                found = true;
                                break;
                            }
                        }
                        break;
                    }
                }
                if (!found) break;
            }

            if (depth > max_depth) {
                const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' has reference chain depth of {d} (max recommended: {d})", .{ field.name, depth, max_depth });
                try results.append(alloc, .{
                    .rule = "fk-depth",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────

fn detectCircularFkDfs(
    alloc: std.mem.Allocator,
    visited: *std.StringHashMap(void),
    path: *std.ArrayList([]const u8),
    graph: *std.StringHashMap(std.ArrayList([]const u8)),
    current: []const u8,
    results: *std.ArrayList(LintResult),
) !void {
    try visited.put(current, {});
    try path.append(alloc, current);

    if (graph.get(current)) |targets| {
        for (targets.items) |target| {
            for (path.items) |path_node| {
                if (std.mem.eql(u8, path_node, target)) {
                    var cycle_desc = try std.ArrayList(u8).initCapacity(alloc, 128);
                    defer cycle_desc.deinit(alloc);
                    var in_cycle = false;
                    for (path.items) |pn| {
                        if (std.mem.eql(u8, pn, target)) in_cycle = true;
                        if (in_cycle) {
                            if (cycle_desc.items.len > 0) try cycle_desc.appendSlice(alloc, " -> ");
                            try cycle_desc.appendSlice(alloc, pn);
                        }
                    }
                    try cycle_desc.appendSlice(alloc, " -> ");
                    try cycle_desc.appendSlice(alloc, target);
                    const msg = try std.fmt.allocPrint(alloc, "circular FK chain detected: {s}", .{cycle_desc.items});
                    try results.append(alloc, .{
                        .rule = "circular-fk",
                        .table = current,
                        .message = msg,
                        .severity = .warning,
                    });
                    return;
                }
            }
            if (!visited.contains(target)) {
                try detectCircularFkDfs(alloc, visited, path, graph, target, results);
            }
        }
    }

    _ = path.pop();
}

fn fieldHasIndex(table: anytype, field_name: []const u8) bool {
    for (table.indexes) |idx| {
        for (idx.fields) |idx_field| {
            if (std.mem.eql(u8, idx_field, field_name)) return true;
        }
    }
    return false;
}
