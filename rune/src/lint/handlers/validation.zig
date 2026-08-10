const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;
const naming = @import("naming.zig");

// ─── Shared Field Helpers ──────────────────────────────────────

/// Check if a field has a primary key modifier (auto_inc_pk or primary_key).
pub fn isPrimaryKey(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return true;
    }
    return false;
}

/// Check if a field has the nullable modifier.
pub fn isNullable(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .nullable) return true;
    }
    return false;
}

/// Check if a field has an explicit default value.
pub fn hasExplicitDefault(field: ast_mod.Field) bool {
    return field.default_val != null;
}

// ─── Validation Rules ──────────────────────────────────────────
// Rules that validate schema integrity: FK references, indexes,
// cascades, duplicates, views, and default values.

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

pub fn checkNullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field) and isNullable(field)) {
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

pub fn checkEnumCase(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        if (!naming.isUpperSnakeCase(ct.name)) {
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

pub fn checkOrphanType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

pub fn checkIndexUnused(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

pub fn checkDuplicateIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

pub fn checkIndexColumnMissing(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

pub fn checkBoolDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (!field.type_info.isBoolean()) continue;
            if (hasExplicitDefault(field)) continue;

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

pub fn checkColumnDefaultRequired(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "column '{s}' has no explicit DEFAULT value", .{field.name});
            try results.append(alloc, .{
                .rule = "column-default-required",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkNullableColumnDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (!isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "nullable column '{s}' has no explicit DEFAULT — consider adding `= null` for clarity", .{field.name});
            try results.append(alloc, .{
                .rule = "nullable-column-default",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
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

pub fn checkEnumEmpty(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        // Check if custom type is an enum with no values
        if (ct.base == .enum_type and ct.base.enum_type.len == 0) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is an enum with no values — add at least one value", .{ct.name});
            try results.append(alloc, .{
                .rule = "enum-empty",
                .table = ct.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

pub fn checkDuplicateColumn(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Track seen column names
        var seen = std.StringHashMap(void).init(alloc);
        defer seen.deinit();

        for (table.fields) |field| {
            if (seen.contains(field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "duplicate column name '{s}' in table", .{field.name});
                try results.append(alloc, .{
                    .rule = "duplicate-column",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            } else {
                try seen.put(field.name, {});
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

fn indexesEqual(a: ast_mod.IndexDecl, b: ast_mod.IndexDecl) bool {
    if (a.kind != b.kind) return false;
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, 0..) |field_a, idx| {
        if (!std.mem.eql(u8, field_a, b.fields[idx])) return false;
    }
    return true;
}

fn fieldHasIndex(table: ResolvedTable, field_name: []const u8) bool {
    for (table.indexes) |idx| {
        for (idx.fields) |idx_field| {
            if (std.mem.eql(u8, idx_field, field_name)) return true;
        }
    }
    return false;
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

pub fn checkEnumValueDuplicate(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        switch (ct.base) {
            .enum_type => |values| {
                var seen = std.StringHashMap(u32).init(alloc);
                defer seen.deinit();
                for (values, 0..) |val, idx| {
                    const gop = try seen.getOrPut(val);
                    if (gop.found_existing) {
                        const msg = try std.fmt.allocPrint(alloc, "enum value '{s}' in type '{s}' is duplicated (first at position {d})", .{ val, ct.name, gop.value_ptr.* });
                        try results.append(alloc, .{
                            .rule = "enum-value-duplicate",
                            .table = ct.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    } else {
                        gop.value_ptr.* = @intCast(idx);
                    }
                }
            },
            else => {},
        }
    }
}

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
