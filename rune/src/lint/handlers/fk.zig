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

pub fn checkFkDuplicate(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Count FK references per target table
        var target_counts = std.StringHashMap(u32).init(alloc);
        defer target_counts.deinit();

        for (table.fields) |field| {
            if (field.fk) |fk| {
                const entry = try target_counts.getOrPut(fk.ref_table);
                if (!entry.found_existing) entry.value_ptr.* = 0;
                entry.value_ptr.* += 1;
            }
        }

        var it = target_counts.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > 1) {
                const msg = try std.fmt.allocPrint(alloc, "table has {d} foreign keys referencing '{s}' — consider if a junction table is needed", .{ entry.value_ptr.*, entry.key_ptr.* });
                try results.append(alloc, .{
                    .rule = "fk-duplicate",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

/// Check if FK column type matches the referenced column type.
/// Warns when a FK column's SS type doesn't match the referenced column's type,
/// which could cause runtime errors or data truncation.
pub fn checkFkColumnTypeMismatch(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            // Skip if FK data is invalid
            if (fk.ref_table.len == 0 or fk.ref_fields.len == 0 or fk.fields.len == 0) continue;
            const fk_col_name = fk.fields[0];
            const ref_col_name = fk.ref_fields[0];
            if (fk_col_name.len == 0 or ref_col_name.len == 0) continue;

            // Find the FK column in this table to get its type
            var fk_col_type: ?ast_mod.TypeInfo = null;
            for (table.fields) |field| {
                if (field.name.len > 0 and std.mem.eql(u8, field.name, fk_col_name)) {
                    fk_col_type = field.type_info;
                    break;
                }
            }
            if (fk_col_type == null) continue;

            // Find the referenced table and column to get its type
            for (ast.tables) |ref_table| {
                if (ref_table.name.len == 0) continue;
                if (std.mem.eql(u8, ref_table.name, fk.ref_table)) {
                    for (ref_table.fields) |ref_field| {
                        if (ref_field.name.len == 0) continue;
                        if (std.mem.eql(u8, ref_field.name, ref_col_name)) {
                            // Compare types
                            if (!fk_col_type.?.eql(ref_field.type_info)) {
                                const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' type doesn't match referenced '{s}.{s}'", .{ fk_col_name, fk.ref_table, ref_col_name });
                                try results.append(alloc, .{
                                    .rule = "fk-column-type-mismatch",
                                    .table = table.name,
                                    .message = msg,
                                    .severity = .warning,
                                });
                            }
                            break;
                        }
                    }
                    break;
                }
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

/// Check if FK uses ON DELETE CASCADE (potential data loss risk).
/// CASCADE deletes can propagate unintended data removal across tables.
pub fn checkFkOnDeleteCascade(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.fk) |fk| {
                for (fk.actions) |action| {
                    if (action.trigger == .on_delete and action.action == .cascade) {
                        const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' uses ON DELETE CASCADE — consider ON DELETE RESTRICT or SET NULL for safety", .{field.name});
                        try results.append(alloc, .{
                            .rule = "fk-on-delete-cascade",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    }
                }
            }
        }
    }
}

/// Check if a table has FKs but no index covers FK columns.
/// Distinct from no-index-fk (checks individual FK columns).
/// This rule flags tables where FK columns exist but lack any supporting index.
pub fn checkFkMissingIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Collect all FK column names from both inline FKs and table-level FK declarations
        var has_any_fk = false;
        var has_unindexed_fk = false;

        // Check inline FKs on fields
        for (table.fields) |field| {
            if (field.fk != null) {
                has_any_fk = true;
                // Check if this column has an index
                var col_indexed = false;
                for (table.indexes) |idx| {
                    for (idx.fields) |idx_field| {
                        if (std.mem.eql(u8, idx_field, field.name)) {
                            col_indexed = true;
                            break;
                        }
                    }
                    if (col_indexed) break;
                }
                if (!col_indexed) {
                    has_unindexed_fk = true;
                }
            }
        }

        // Check table-level FK declarations
        for (table.fks) |fk| {
            has_any_fk = true;
            for (fk.fields) |fk_field| {
                var col_indexed = false;
                for (table.indexes) |idx| {
                    for (idx.fields) |idx_field| {
                        if (std.mem.eql(u8, idx_field, fk_field)) {
                            col_indexed = true;
                            break;
                        }
                    }
                    if (col_indexed) break;
                }
                if (!col_indexed) {
                    has_unindexed_fk = true;
                    break;
                }
            }
        }

        if (has_any_fk and has_unindexed_fk) {
            const msg = try std.fmt.allocPrint(alloc, "Table has foreign keys but FK columns lack supporting indexes", .{});
            try results.append(alloc, .{
                .rule = "fk-missing-index",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}
