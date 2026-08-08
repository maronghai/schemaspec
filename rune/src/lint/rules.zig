const std = @import("std");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../types/ast.zig");
const LintConfig = @import("config.zig").LintConfig;
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;

// ─── Lint Rules ───────────────────────────────────────────────
// Individual lint rule implementations. Each rule checks one
// specific schema anti-pattern and appends results if found.

/// Run all enabled lint checks on a resolved schema.
pub fn runAll(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (ast.tables) |table| {
        if (LintRule.no_pk.isEnabled(cfg)) try noPk(alloc, &results, table);
        if (LintRule.naming.isEnabled(cfg)) try namingConventions(alloc, &results, table);
        if (LintRule.no_index_fk.isEnabled(cfg)) try noIndexFk(alloc, &results, table);
        if (LintRule.no_timestamps.isEnabled(cfg)) try noTimestamps(alloc, &results, table);
        if (LintRule.wide_table.isEnabled(cfg)) try wideTable(alloc, &results, table, cfg.wide_table_max);
        if (LintRule.count.isEnabled(cfg)) try count(alloc, &results, table, cfg.count_min);
        if (LintRule.fk_cascade.isEnabled(cfg)) try noFkCascade(alloc, &results, table);
        if (LintRule.nullable_pk.isEnabled(cfg)) try nullablePk(alloc, &results, table);
    }
    if (LintRule.enum_case.isEnabled(cfg)) {
        for (ast.custom_types) |ct| {
            try enumCase(alloc, &results, ct);
        }
    }
    if (LintRule.orphan_type.isEnabled(cfg)) {
        for (ast.custom_types) |ct| {
            try orphanType(alloc, &results, ast, ct);
        }
    }
    if (LintRule.index_unused.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try indexUnused(alloc, &results, table);
        }
    }
    if (LintRule.circular_fk.isEnabled(cfg)) {
        try circularFk(alloc, &results, ast);
    }
    if (LintRule.duplicate_index.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try duplicateIndex(alloc, &results, table);
        }
    }
    if (LintRule.empty_table.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try emptyTable(alloc, &results, table);
        }
    }
    if (LintRule.table_comment.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try tableComment(alloc, &results, table);
        }
    }
    if (LintRule.serial_type.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try serialType(alloc, &results, table);
        }
    }
    if (LintRule.table_name_length.isEnabled(cfg)) {
        for (ast.tables) |table| {
            try tableNameLength(alloc, &results, table, cfg.table_name_max);
        }
    }

    return results;
}

// ─── Individual Rules ─────────────────────────────────────────

fn noPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return;
        }
    }
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) return;
    }
    try results.append(alloc, .{
        .rule = "no-pk",
        .table = table.name,
        .message = "table has no primary key",
        .severity = .warning,
    });
}

fn namingConventions(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (!isSnakeCase(table.name)) {
        const msg = try std.fmt.allocPrint(alloc, "table name '{s}' should use snake_case", .{table.name});
        try results.append(alloc, .{
            .rule = "naming",
            .table = table.name,
            .message = msg,
            .severity = .info,
        });
    }
    for (table.fields) |field| {
        if (!isSnakeCase(field.name)) {
            const msg = try std.fmt.allocPrint(alloc, "column name '{s}' should use snake_case", .{field.name});
            try results.append(alloc, .{
                .rule = "naming",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

fn noIndexFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

fn noTimestamps(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        if (std.mem.eql(u8, field.name, "created_at") or std.mem.eql(u8, field.name, "updated_at")) return;
    }
    try results.append(alloc, .{
        .rule = "no-timestamps",
        .table = table.name,
        .message = "no created_at/updated_at fields",
        .severity = .info,
    });
}

fn wideTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, max: usize) !void {
    if (table.fields.len > max) {
        const msg = try std.fmt.allocPrint(alloc, "table has {d} fields (threshold: {d})", .{ table.fields.len, max });
        try results.append(alloc, .{
            .rule = "wide-table",
            .table = table.name,
            .message = msg,
            .severity = .warning,
        });
    }
}

fn enumCase(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), custom_type: ast_mod.CustomType) !void {
    if (!isUpperSnakeCase(custom_type.name)) {
        const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' should use UPPER_CASE naming", .{custom_type.name});
        try results.append(alloc, .{
            .rule = "enum-case",
            .table = custom_type.name,
            .message = msg,
            .severity = .info,
        });
    }
}

fn count(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, min: usize) !void {
    var non_pk_count: usize = 0;
    for (table.fields) |field| {
        var is_pk = false;
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) {
                is_pk = true;
                break;
            }
        }
        if (!is_pk) non_pk_count += 1;
    }
    if (non_pk_count < min) {
        const msg = try std.fmt.allocPrint(alloc, "table has only {d} non-PK field(s) — is this a junction table?", .{non_pk_count});
        try results.append(alloc, .{
            .rule = "count",
            .table = table.name,
            .message = msg,
            .severity = .info,
        });
    }
}

fn noFkCascade(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

fn nullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        var is_pk = false;
        var is_nullable = false;
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) is_pk = true;
            if (mod.kind == .nullable) is_nullable = true;
        }
        if (is_pk and is_nullable) {
            const msg = try std.fmt.allocPrint(alloc, "primary key column '{s}' should not be nullable", .{field.name});
            try results.append(alloc, .{
                .rule = "nullable-pk",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

fn orphanType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, ct: ast_mod.CustomType) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .simple => |s| if (std.mem.eql(u8, s, ct.name)) return,
                else => {},
            }
        }
    }
    const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is defined but never used by any table", .{ct.name});
    try results.append(alloc, .{
        .rule = "orphan-type",
        .table = ct.name,
        .message = msg,
        .severity = .info,
    });
}

fn indexUnused(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    var fk_fields = std.StringHashMap(void).init(alloc);
    defer fk_fields.deinit();
    for (table.fields) |field| {
        if (field.fk != null) {
            try fk_fields.put(field.name, {});
        }
    }
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key or idx.kind == .unique) continue;
        var covers_fk = false;
        for (idx.fields) |idx_field| {
            if (fk_fields.contains(idx_field)) {
                covers_fk = true;
                break;
            }
        }
        if (!covers_fk) {
            const field_name = if (idx.fields.len > 0) idx.fields[0] else "??";
            const msg = try std.fmt.allocPrint(alloc, "index '{s}' on [{s}] may be unused (no FK or unique constraint)", .{ idx.name, field_name });
            try results.append(alloc, .{
                .rule = "index-unused",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

fn circularFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst) !void {
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

fn duplicateIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (table.indexes.len < 2) return;

    var i: usize = 0;
    while (i < table.indexes.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < table.indexes.len) : (j += 1) {
            if (indexesEqual(table.indexes[i], table.indexes[j])) {
                const msg = try std.fmt.allocPrint(alloc, "index '{s}' duplicates index '{s}' (same columns and type)", .{ table.indexes[j].name, table.indexes[i].name });
                try results.append(alloc, .{
                    .rule = "duplicate-index",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

fn indexesEqual(a: ast_mod.IndexDecl, b: ast_mod.IndexDecl) bool {
    if (a.kind != b.kind) return false;
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, 0..) |field_a, idx| {
        if (!std.mem.eql(u8, field_a, b.fields[idx])) return false;
    }
    return true;
}

fn emptyTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (table.fields.len == 0) {
        try results.append(alloc, .{
            .rule = "empty-table",
            .table = table.name,
            .message = "table has no fields",
            .severity = .warning,
        });
    }
}

fn tableComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (table.comment == null or (table.comment != null and table.comment.?.len == 0)) {
        const msg = try std.fmt.allocPrint(alloc, "table '{s}' has no comment", .{table.name});
        try results.append(alloc, .{
            .rule = "table-comment",
            .table = table.name,
            .message = msg,
            .severity = .info,
        });
    }
}

fn serialType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        switch (field.type_info) {
            .simple => |s| {
                if (std.mem.eql(u8, s, "serial") or std.mem.eql(u8, s, "bigserial")) {
                    const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses PostgreSQL-specific type '{s}' — use auto_increment modifier for cross-dialect compatibility", .{ field.name, s });
                    try results.append(alloc, .{
                        .rule = "serial-type",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            },
            else => {},
        }
    }
}

fn tableNameLength(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, max: usize) !void {
    if (table.name.len > max) {
        const msg = try std.fmt.allocPrint(alloc, "table name '{s}' is {d} chars (max: {d})", .{ table.name, table.name.len, max });
        try results.append(alloc, .{
            .rule = "table-name-length",
            .table = table.name,
            .message = msg,
            .severity = .warning,
        });
    }
}

// ─── Helpers ──────────────────────────────────────────────────

fn isSnakeCase(name: []const u8) bool {
    for (name) |c| {
        if (std.ascii.isUpper(c)) return false;
    }
    return true;
}

fn isUpperSnakeCase(name: []const u8) bool {
    var has_upper = false;
    for (name) |c| {
        if (std.ascii.isUpper(c)) has_upper = true;
        if (std.ascii.isLower(c)) return false;
    }
    return has_upper;
}

fn fieldHasIndex(table: ResolvedTable, field_name: []const u8) bool {
    for (table.indexes) |idx| {
        for (idx.fields) |idx_field| {
            if (std.mem.eql(u8, idx_field, field_name)) return true;
        }
    }
    return false;
}
