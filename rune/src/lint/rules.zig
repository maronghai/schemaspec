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

/// Handler function signature for data-driven dispatch.
const RuleHandler = *const fn (alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) anyerror!void;

/// Dispatch table entry: rule enum + handler function.
const RuleEntry = struct {
    rule: LintRule,
    handler: RuleHandler,
};

/// Table-driven rule dispatch — eliminates 22 repetitive guard-then-call blocks.
/// Adding a new rule = add entry to RULES + implement handler below.
const RULES = [_]RuleEntry{
    .{ .rule = .no_pk, .handler = checkNoPk },
    .{ .rule = .naming, .handler = checkNaming },
    .{ .rule = .no_index_fk, .handler = checkNoIndexFk },
    .{ .rule = .no_timestamps, .handler = checkNoTimestamps },
    .{ .rule = .wide_table, .handler = checkWideTable },
    .{ .rule = .count, .handler = checkCount },
    .{ .rule = .fk_cascade, .handler = checkFkCascade },
    .{ .rule = .nullable_pk, .handler = checkNullablePk },
    .{ .rule = .enum_case, .handler = checkEnumCase },
    .{ .rule = .orphan_type, .handler = checkOrphanType },
    .{ .rule = .index_unused, .handler = checkIndexUnused },
    .{ .rule = .circular_fk, .handler = checkCircularFk },
    .{ .rule = .duplicate_index, .handler = checkDuplicateIndex },
    .{ .rule = .empty_table, .handler = checkEmptyTable },
    .{ .rule = .table_comment, .handler = checkTableComment },
    .{ .rule = .serial_type, .handler = checkSerialType },
    .{ .rule = .table_name_length, .handler = checkTableNameLength },
    .{ .rule = .column_length, .handler = checkColumnLength },
    .{ .rule = .index_column_missing, .handler = checkIndexColumnMissing },
    .{ .rule = .naming_prefix, .handler = checkNamingPrefix },
    .{ .rule = .fk_naming, .handler = checkFkNaming },
    .{ .rule = .bool_default, .handler = checkBoolDefault },
};

/// Run all enabled lint checks on a resolved schema.
pub fn runAll(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (RULES) |entry| {
        if (entry.rule.isEnabled(cfg)) {
            try entry.handler(alloc, &results, ast, cfg);
        }
    }

    return results;
}

// ─── Individual Rules ─────────────────────────────────────────
// Each handler receives the full AST + config and iterates over
// the relevant entities (tables, custom types, or entire schema).

fn checkNoPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var has_pk = false;
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) {
                    has_pk = true;
                    break;
                }
            }
            if (has_pk) break;
        }
        if (!has_pk) {
            for (table.indexes) |idx| {
                if (idx.kind == .primary_key) {
                    has_pk = true;
                    break;
                }
            }
        }
        if (!has_pk) {
            try results.append(alloc, .{
                .rule = "no-pk",
                .table = table.name,
                .message = "table has no primary key",
                .severity = .warning,
            });
        }
    }
}

fn checkNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
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
}

fn checkNoIndexFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

fn checkNoTimestamps(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var has_ts = false;
        for (table.fields) |field| {
            if (std.mem.eql(u8, field.name, "created_at") or std.mem.eql(u8, field.name, "updated_at")) {
                has_ts = true;
                break;
            }
        }
        if (!has_ts) {
            try results.append(alloc, .{
                .rule = "no-timestamps",
                .table = table.name,
                .message = "no created_at/updated_at fields",
                .severity = .info,
            });
        }
    }
}

fn checkWideTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.fields.len > cfg.wide_table_max) {
            const msg = try std.fmt.allocPrint(alloc, "table has {d} fields (threshold: {d})", .{ table.fields.len, cfg.wide_table_max });
            try results.append(alloc, .{
                .rule = "wide-table",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

fn checkEnumCase(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        if (!isUpperSnakeCase(ct.name)) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' should use UPPER_CASE naming", .{ct.name});
            try results.append(alloc, .{
                .rule = "enum-case",
                .table = ct.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

fn checkCount(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
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
        if (non_pk_count < cfg.count_min) {
            const msg = try std.fmt.allocPrint(alloc, "table has only {d} non-PK field(s) — is this a junction table?", .{non_pk_count});
            try results.append(alloc, .{
                .rule = "count",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

fn checkFkCascade(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

fn checkNullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
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
}

fn checkOrphanType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        var used = false;
        for (ast.tables) |table| {
            for (table.fields) |field| {
                switch (field.type_info) {
                    .simple => |s| if (std.mem.eql(u8, s, ct.name)) {
                        used = true;
                        break;
                    },
                    else => {},
                }
                if (used) break;
            }
            if (used) break;
        }
        if (!used) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is defined but never used by any table", .{ct.name});
            try results.append(alloc, .{
                .rule = "orphan-type",
                .table = ct.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

fn checkIndexUnused(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
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
}

fn checkCircularFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

fn checkDuplicateIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.indexes.len < 2) continue;

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
}

fn checkEmptyTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.fields.len == 0) {
            try results.append(alloc, .{
                .rule = "empty-table",
                .table = table.name,
                .message = "table has no fields",
                .severity = .warning,
            });
        }
    }
}

fn checkTableComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
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
}

fn checkSerialType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
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
}

fn checkTableNameLength(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.name.len > cfg.table_name_max) {
            const msg = try std.fmt.allocPrint(alloc, "table name '{s}' is {d} chars (max: {d})", .{ table.name, table.name.len, cfg.table_name_max });
            try results.append(alloc, .{
                .rule = "table-name-length",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

fn checkColumnLength(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .varchar_explicit => |len| {
                    if (len == 0) {
                        const msg = try std.fmt.allocPrint(alloc, "string column '{s}' has no explicit length — consider adding length (e.g., s64) for cross-dialect compatibility", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-length",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                .simple => |s| {
                    if (std.mem.eql(u8, s, "S")) {
                        const msg = try std.fmt.allocPrint(alloc, "string column '{s}' has no explicit length — consider adding length (e.g., s64) for cross-dialect compatibility", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-length",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                else => {},
            }
        }
    }
}

fn checkIndexColumnMissing(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.indexes) |idx| {
            for (idx.fields) |idx_field| {
                var found = false;
                for (table.fields) |field| {
                    if (std.mem.eql(u8, field.name, idx_field)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    const msg = try std.fmt.allocPrint(alloc, "index '{s}' references column '{s}' which does not exist in table", .{ idx.name, idx_field });
                    try results.append(alloc, .{
                        .rule = "index-column-missing",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            }
        }
    }
}

fn checkNamingPrefix(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    const prefixes = [_][]const u8{ "tbl_", "t_", "tb_", "table_" };
    for (ast.tables) |table| {
        for (prefixes) |prefix| {
            if (table.name.len > prefix.len and std.mem.startsWith(u8, table.name, prefix)) {
                const msg = try std.fmt.allocPrint(alloc, "table name '{s}' uses anti-pattern prefix '{s}'", .{ table.name, prefix });
                try results.append(alloc, .{
                    .rule = "naming-prefix",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
                break;
            }
        }
    }
}

fn checkFkNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

            // FK columns should end with _id
            if (!std.mem.endsWith(u8, field.name, "_id")) {
                const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' should follow '<table>_id' naming convention", .{field.name});
                try results.append(alloc, .{
                    .rule = "fk-naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

fn checkBoolDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            // Check if field is boolean type using type_info
            const is_bool = field.type_info.isBoolean();
            if (!is_bool) continue;

            // Check if field has an explicit default value
            const has_default = field.default_val != null;

            if (!has_default) {
                const msg = try std.fmt.allocPrint(alloc, "boolean column '{s}' has no explicit default value", .{field.name});
                try results.append(alloc, .{
                    .rule = "bool-default",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
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

fn indexesEqual(a: ast_mod.IndexDecl, b: ast_mod.IndexDecl) bool {
    if (a.kind != b.kind) return false;
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, 0..) |field_a, idx| {
        if (!std.mem.eql(u8, field_a, b.fields[idx])) return false;
    }
    return true;
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
