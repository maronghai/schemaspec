const std = @import("std");
const ResolvedAst = @import("types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("types/ast.zig");

// ─── Lint Engine ──────────────────────────────────────────────
// Schema quality analysis — catches anti-patterns that validation passes miss.

pub const LintSeverity = enum { warning, info };

pub const LintResult = struct {
    rule: []const u8,
    table: []const u8,
    message: []const u8,
    severity: LintSeverity,
};

pub const LintConfig = struct {
    check_pk: bool = true,
    check_naming: bool = true,
    check_fk_index: bool = true,
    check_timestamps: bool = true,
    check_wide_table: bool = true,
    check_enum_case: bool = true,
    check_count: bool = true,
    check_fk_cascade: bool = true,
    check_nullable_pk: bool = true,
    check_orphan_type: bool = true,
    check_index_unused: bool = true,
    check_circular_fk: bool = true,
    check_duplicate_index: bool = true,
    check_empty_table: bool = true,
    check_table_comment: bool = true,
    wide_table_max: usize = 30,
    count_min: usize = 2,
};

// ─── Diff-aware Lint ─────────────────────────────────────────

pub const LintDiffResult = struct {
    old_results: []const LintResult,
    new_results: []const LintResult,
    added: []const LintResult,
};

/// Compare lint results between two schemas, returning only newly introduced issues.
pub fn lintDiff(old_results: []const LintResult, new_results: []const LintResult, alloc: std.mem.Allocator) !LintDiffResult {
    var added = try std.ArrayList(LintResult).initCapacity(alloc, new_results.len);
    errdefer added.deinit(alloc);

    for (new_results) |new_r| {
        var found = false;
        for (old_results) |old_r| {
            if (std.mem.eql(u8, old_r.rule, new_r.rule) and
                std.mem.eql(u8, old_r.table, new_r.table) and
                std.mem.eql(u8, old_r.message, new_r.message))
            {
                found = true;
                break;
            }
        }
        if (!found) {
            try added.append(alloc, new_r);
        }
    }

    return .{
        .old_results = old_results,
        .new_results = new_results,
        .added = try added.toOwnedSlice(alloc),
    };
}

// ─── Run All Lint Checks ─────────────────────────────────────

/// Run all enabled lint checks on a resolved schema.
pub fn lintSchema(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (ast.tables) |table| {
        if (cfg.check_pk) try lintNoPk(alloc, &results, table);
        if (cfg.check_naming) try lintNamingConventions(alloc, &results, table);
        if (cfg.check_fk_index) try lintNoIndexFk(alloc, &results, table);
        if (cfg.check_timestamps) try lintNoTimestamps(alloc, &results, table);
        if (cfg.check_wide_table) try lintWideTable(alloc, &results, table, cfg.wide_table_max);
        if (cfg.check_count) try lintCount(alloc, &results, table, cfg.count_min);
        if (cfg.check_fk_cascade) try lintNoFkCascade(alloc, &results, table);
        if (cfg.check_nullable_pk) try lintNullablePk(alloc, &results, table);
    }
    if (cfg.check_enum_case) {
        for (ast.custom_types) |ct| {
            try lintEnumCase(alloc, &results, ct);
        }
    }
    if (cfg.check_orphan_type) {
        for (ast.custom_types) |ct| {
            try lintOrphanType(alloc, &results, ast, ct);
        }
    }
    if (cfg.check_index_unused) {
        for (ast.tables) |table| {
            try lintIndexUnused(alloc, &results, table);
        }
    }
    if (cfg.check_circular_fk) {
        try lintCircularFk(alloc, &results, ast);
    }
    if (cfg.check_duplicate_index) {
        for (ast.tables) |table| {
            try lintDuplicateIndex(alloc, &results, table);
        }
    }
    if (cfg.check_empty_table) {
        for (ast.tables) |table| {
            try lintEmptyTable(alloc, &results, table);
        }
    }
    if (cfg.check_table_comment) {
        for (ast.tables) |table| {
            try lintTableComment(alloc, &results, table);
        }
    }

    return results;
}

// ─── Lint: No Primary Key ─────────────────────────────────────
// Warns when a table has no primary key field.
// Tables without PKs break ORM mapping and complicate replication.

fn lintNoPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return;
        }
    }
    // Also check for composite PK via standalone indexes
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

// ─── Lint: Naming Conventions ─────────────────────────────────
// Warns when table or column names use camelCase instead of snake_case.
// Rune convention is snake_case for all identifiers.

fn lintNamingConventions(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Lint: No Index on FK ─────────────────────────────────────
// Warns when FK columns lack a corresponding index.
// FKs without indexes cause slow JOIN performance on MySQL/SQLite.

fn lintNoIndexFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Lint: No Timestamps ──────────────────────────────────────
// Warns when tables have no created_at/updated_at fields.
// Most production tables benefit from audit timestamps.

fn lintNoTimestamps(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Lint: Wide Table ─────────────────────────────────────────
// Warns when a table has more than max fields.
// Wide tables often indicate poor normalization or missing template inheritance.

fn lintWideTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, max: usize) !void {
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

// ─── Lint: Enum Case ──────────────────────────────────────────
// Warns when custom type definitions use non-UPPER_CASE naming.
// UPPER_CASE is the standard convention for enum-like types.

fn lintEnumCase(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), custom_type: ast_mod.CustomType) !void {
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

// ─── Lint: Count ──────────────────────────────────────────────
// Warns when a table has fewer than min non-PK fields.
// A table with only a PK is likely a mistake or incomplete junction table.

fn lintCount(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, min: usize) !void {
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

// ─── Lint: FK Cascade ─────────────────────────────────────────
// Warns when FK fields lack explicit ON DELETE/ON UPDATE actions.
// Production schemas need explicit cascade rules to avoid data integrity issues.

fn lintNoFkCascade(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Lint: Nullable PK ────────────────────────────────────────
// Warns when PK fields have nullable modifier.
// Primary keys must be NOT NULL for data integrity.

fn lintNullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Lint: Orphan Type ────────────────────────────────────────
// Warns when custom type definitions aren't used by any table field.
// Dead type definitions clutter the schema and confuse readers.

fn lintOrphanType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, ct: ast_mod.CustomType) !void {
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

// ─── Lint: Index Unused ────────────────────────────────────────
// Warns when a standalone index doesn't correspond to any FK field,
// primary key, or unique constraint. Such indexes may be unnecessary overhead.

fn lintIndexUnused(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    // Collect FK field names for this table
    var fk_fields = std.StringHashMap(void).init(alloc);
    defer fk_fields.deinit();
    for (table.fields) |field| {
        if (field.fk != null) {
            try fk_fields.put(field.name, {});
        }
    }
    for (table.indexes) |idx| {
        // Skip primary key and unique indexes — those are always useful
        if (idx.kind == .primary_key or idx.kind == .unique) continue;
        // Check if this index covers any FK fields
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

// ─── Lint: Circular FK ─────────────────────────────────────────
// Warns when foreign key chains form circular references (e.g. A→B→C→A).
// Circular FKs can cause insertion deadlocks and migration issues.

fn lintCircularFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst) !void {
    // Build adjacency list: table_name → list of FK target table names
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

    // DFS cycle detection
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
            // Check if target is in current path (cycle detected)
            for (path.items) |path_node| {
                if (std.mem.eql(u8, path_node, target)) {
                    // Build cycle description
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

// ─── Lint: Duplicate Index ─────────────────────────────────────
// Warns when a table has multiple indexes with the same columns and type.
// Duplicate indexes waste storage and slow down writes.

fn lintDuplicateIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (table.indexes.len < 2) return;

    // Compare each pair of indexes for structural equality
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

// ─── Lint: Empty Table ────────────────────────────────────────
// Warns when a table has zero fields.
// An empty table is almost certainly a mistake or incomplete definition.

fn lintEmptyTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (table.fields.len == 0) {
        try results.append(alloc, .{
            .rule = "empty-table",
            .table = table.name,
            .message = "table has no fields",
            .severity = .warning,
        });
    }
}

// ─── Lint: Table Comment ──────────────────────────────────────
// Warns when a table lacks a comment/documentation.
// Documented schemas are easier to understand and maintain.

fn lintTableComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
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

// ─── Output Formatting ────────────────────────────────────────

/// Format lint results as human-readable text.
pub fn formatLintResults(alloc: std.mem.Allocator, results: []const LintResult, use_color: bool) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    if (results.len == 0) {
        try aw.writer.writeAll("No lint issues found.\n");
        return try aw.toOwnedSlice();
    }

    var warnings: usize = 0;
    var infos: usize = 0;
    for (results) |r| {
        const severity_str = if (r.severity == .warning) "warning" else "info";
        const prefix = if (use_color) "\x1b[33m" else "";
        const suffix = if (use_color) "\x1b[0m" else "";
        try aw.writer.print("{s}{s}{s}: [{s}] {s}: {s}\n", .{
            prefix, severity_str, suffix, r.rule, r.table, r.message,
        });
        if (r.severity == .warning) warnings += 1 else infos += 1;
    }
    try aw.writer.print("\n{s}Lint summary: {d} warning(s), {d} info(s)\n", .{
        if (use_color) "\x1b[1m" else "", warnings, infos,
    });
    if (use_color) try aw.writer.writeAll("\x1b[0m");

    return try aw.toOwnedSlice();
}

/// Format lint results as JSON (machine-readable).
pub fn formatLintJson(alloc: std.mem.Allocator, results: []const LintResult) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    try aw.writer.writeAll("{\"issues\":[");
    for (results, 0..) |r, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"rule\":\"");
        try aw.writer.writeAll(r.rule);
        try aw.writer.writeAll("\",\"table\":\"");
        try aw.writer.writeAll(r.table);
        try aw.writer.writeAll("\",\"message\":\"");
        // Escape JSON string
        for (r.message) |c| {
            switch (c) {
                '"' => try aw.writer.writeAll("\\\""),
                '\\' => try aw.writer.writeAll("\\\\"),
                '\n' => try aw.writer.writeAll("\\n"),
                else => try aw.writer.writeByte(c),
            }
        }
        try aw.writer.writeAll("\",\"severity\":\"");
        try aw.writer.writeAll(if (r.severity == .warning) "warning" else "info");
        try aw.writer.writeAll("\"}");
    }
    const has_warnings = for (results) |r| {
        if (r.severity == .warning) break true;
    } else false;
    try aw.writer.writeAll("],\"count\":");
    // Write count as decimal
    var count_buf: [20]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{results.len}) catch "0";
    try aw.writer.writeAll(count_str);
    try aw.writer.writeAll(",\"has_warnings\":");
    try aw.writer.writeAll(if (has_warnings) "true" else "false");
    try aw.writer.writeAll("}");

    return try aw.toOwnedSlice();
}

/// Format lint results as SARIF 2.1.0 (CI/CD integration).
pub fn formatLintSarif(alloc: std.mem.Allocator, results: []const LintResult, version_str: []const u8, file_path: ?[]const u8) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    try aw.writer.writeAll("{\"$schema\":\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"rune\",\"version\":\"");
    try aw.writer.writeAll(version_str);
    try aw.writer.writeAll("\",\"rules\":[");

    // Emit rule definitions
    const rules = [_]struct { id: []const u8, name: []const u8, desc: []const u8, level: []const u8 }{
        .{ .id = "no-pk", .name = "no-primary-key", .desc = "Table has no primary key", .level = "error" },
        .{ .id = "wide-table", .name = "wide-table", .desc = "Table has too many fields", .level = "warning" },
        .{ .id = "no-index-fk", .name = "no-index-fk", .desc = "Foreign key column has no index", .level = "warning" },
        .{ .id = "nullable-pk", .name = "nullable-pk", .desc = "Primary key column is nullable", .level = "warning" },
        .{ .id = "circular-fk", .name = "circular-fk", .desc = "Foreign key chain forms a circular reference", .level = "warning" },
        .{ .id = "naming", .name = "naming-conventions", .desc = "Identifier does not follow snake_case", .level = "note" },
        .{ .id = "no-timestamps", .name = "no-timestamps", .desc = "Table has no audit timestamps", .level = "note" },
        .{ .id = "enum-case", .name = "enum-case", .desc = "Custom type should use UPPER_CASE naming", .level = "note" },
        .{ .id = "count", .name = "low-field-count", .desc = "Table has very few non-PK fields", .level = "note" },
        .{ .id = "fk-cascade", .name = "fk-cascade", .desc = "FK has no explicit ON DELETE/ON UPDATE actions", .level = "note" },
        .{ .id = "orphan-type", .name = "orphan-type", .desc = "Custom type is defined but never used", .level = "note" },
        .{ .id = "index-unused", .name = "index-unused", .desc = "Standalone index may be unnecessary", .level = "note" },
        .{ .id = "duplicate-index", .name = "duplicate-index", .desc = "Multiple indexes with same columns and type", .level = "warning" },
    };

    for (rules, 0..) |rule, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"id\":\"");
        try aw.writer.writeAll(rule.id);
        try aw.writer.writeAll("\",\"name\":\"");
        try aw.writer.writeAll(rule.name);
        try aw.writer.writeAll("\",\"shortDescription\":{\"text\":\"");
        try aw.writer.writeAll(rule.desc);
        try aw.writer.writeAll("\"},\"defaultConfiguration\":{\"level\":\"");
        try aw.writer.writeAll(rule.level);
        try aw.writer.writeAll("\"}}");
    }

    try aw.writer.writeAll("]},\"results\":[");

    // Emit results
    for (results, 0..) |r, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"ruleId\":\"");
        try aw.writer.writeAll(r.rule);
        try aw.writer.writeAll("\",\"level\":\"");
        try aw.writer.writeAll(if (r.severity == .warning) "warning" else "note");
        try aw.writer.writeAll("\",\"message\":{\"text\":\"");
        for (r.message) |c| {
            switch (c) {
                '"' => try aw.writer.writeAll("\\\""),
                '\\' => try aw.writer.writeAll("\\\\"),
                '\n' => try aw.writer.writeAll("\\n"),
                else => try aw.writer.writeByte(c),
            }
        }
        try aw.writer.writeAll("\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"");
        if (file_path) |fp| {
            for (fp) |c| {
                switch (c) {
                    '"' => try aw.writer.writeAll("\\\""),
                    '\\' => try aw.writer.writeAll("\\\\"),
                    else => try aw.writer.writeByte(c),
                }
            }
        } else {
            try aw.writer.writeAll("schema.ss");
        }
        try aw.writer.writeAll("\"},\"region\":{\"startLine\":1}}}],\"fingerprints\":{\"run/rune/v1\":\"");
        try aw.writer.writeAll(r.rule);
        try aw.writer.writeAll(":");
        try aw.writer.writeAll(r.table);
        try aw.writer.writeAll("\"}}");
    }

    try aw.writer.writeAll("],\"artifacts\":[{\"location\":{\"uri\":\"");
    if (file_path) |fp| {
        for (fp) |c| {
            switch (c) {
                '"' => try aw.writer.writeAll("\\\""),
                '\\' => try aw.writer.writeAll("\\\\"),
                else => try aw.writer.writeByte(c),
            }
        }
    } else {
        try aw.writer.writeAll("schema.ss");
    }
    try aw.writer.writeAll("\"}}]}]}");

    return try aw.toOwnedSlice();
}

// ─── Lint Config File ─────────────────────────────────────────

pub const LintRulesConfig = struct {
    enabled: ?[]const []const u8 = null,
    disabled: ?[]const []const u8 = null,
    severity_overrides: []const SeverityOverride = &.{},
    thresholds: Thresholds = .{},

    pub const SeverityOverride = struct {
        rule: []const u8,
        severity: []const u8,
    };

    pub const Thresholds = struct {
        wide_table_max: ?usize = null,
        count_min: ?usize = null,
    };
};

/// Parse a rune-lint.toml rules file.
pub fn parseLintRules(alloc: std.mem.Allocator, data: []const u8) !LintRulesConfig {
    var result = LintRulesConfig{};
    var enabled_list = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    errdefer enabled_list.deinit(alloc);
    var disabled_list = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    errdefer disabled_list.deinit(alloc);
    var severity_list = try std.ArrayList(LintRulesConfig.SeverityOverride).initCapacity(alloc, 4);
    errdefer severity_list.deinit(alloc);
    var in_severity = false;
    var in_thresholds = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[lint]")) {
            in_severity = false;
            in_thresholds = false;
            continue;
        }
        if (std.mem.eql(u8, line, "[lint.severity]")) {
            in_severity = true;
            in_thresholds = false;
            continue;
        }
        if (std.mem.eql(u8, line, "[lint.thresholds]")) {
            in_thresholds = true;
            in_severity = false;
            continue;
        }

        if (in_severity) {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = std.mem.trim(u8, line[0..eq_pos], " \t");
                const val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t\"'");
                try severity_list.append(alloc, .{ .rule = key, .severity = val });
            }
            continue;
        }

        if (in_thresholds) {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = std.mem.trim(u8, line[0..eq_pos], " \t");
                const val_str = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");
                if (std.mem.eql(u8, key, "wide_table_max")) {
                    result.thresholds.wide_table_max = std.fmt.parseInt(usize, val_str, 10) catch null;
                } else if (std.mem.eql(u8, key, "count_min")) {
                    result.thresholds.count_min = std.fmt.parseInt(usize, val_str, 10) catch null;
                }
            }
            continue;
        }

        if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
            const key = std.mem.trim(u8, line[0..eq_pos], " \t");
            const val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t\"'");

            if (std.mem.eql(u8, key, "enabled")) {
                // Parse comma-separated list
                var items = std.mem.splitScalar(u8, val, ',');
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\"'");
                    if (trimmed.len > 0) {
                        try enabled_list.append(alloc, trimmed);
                    }
                }
            } else if (std.mem.eql(u8, key, "disabled")) {
                var items = std.mem.splitScalar(u8, val, ',');
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\"'");
                    if (trimmed.len > 0) {
                        try disabled_list.append(alloc, trimmed);
                    }
                }
            }
        }
    }

    if (enabled_list.items.len > 0) {
        result.enabled = try enabled_list.toOwnedSlice(alloc);
    }
    if (disabled_list.items.len > 0) {
        result.disabled = try disabled_list.toOwnedSlice(alloc);
    }
    if (severity_list.items.len > 0) {
        result.severity_overrides = try severity_list.toOwnedSlice(alloc);
    }

    return result;
}

/// Apply lint rules config to LintConfig — filters and overrides based on rules file.
pub fn applyLintRules(base: LintConfig, rules: LintRulesConfig) LintConfig {
    var cfg = base;

    // If enabled list is set, disable everything first, then enable listed rules
    if (rules.enabled) |enabled| {
        cfg.check_pk = false;
        cfg.check_naming = false;
        cfg.check_fk_index = false;
        cfg.check_timestamps = false;
        cfg.check_wide_table = false;
        cfg.check_enum_case = false;
        cfg.check_count = false;
        cfg.check_fk_cascade = false;
        cfg.check_nullable_pk = false;
        cfg.check_orphan_type = false;
        cfg.check_index_unused = false;
        cfg.check_circular_fk = false;
        for (enabled) |rule| {
            if (std.mem.eql(u8, rule, "no-pk")) cfg.check_pk = true;
            if (std.mem.eql(u8, rule, "naming")) cfg.check_naming = true;
            if (std.mem.eql(u8, rule, "no-index-fk")) cfg.check_fk_index = true;
            if (std.mem.eql(u8, rule, "no-timestamps")) cfg.check_timestamps = true;
            if (std.mem.eql(u8, rule, "wide-table")) cfg.check_wide_table = true;
            if (std.mem.eql(u8, rule, "enum-case")) cfg.check_enum_case = true;
            if (std.mem.eql(u8, rule, "count")) cfg.check_count = true;
            if (std.mem.eql(u8, rule, "fk-cascade")) cfg.check_fk_cascade = true;
            if (std.mem.eql(u8, rule, "nullable-pk")) cfg.check_nullable_pk = true;
            if (std.mem.eql(u8, rule, "orphan-type")) cfg.check_orphan_type = true;
            if (std.mem.eql(u8, rule, "index-unused")) cfg.check_index_unused = true;
            if (std.mem.eql(u8, rule, "circular-fk")) cfg.check_circular_fk = true;
        }
    }

    // Disable listed rules
    if (rules.disabled) |disabled| {
        for (disabled) |rule| {
            if (std.mem.eql(u8, rule, "no-pk")) cfg.check_pk = false;
            if (std.mem.eql(u8, rule, "naming")) cfg.check_naming = false;
            if (std.mem.eql(u8, rule, "no-index-fk")) cfg.check_fk_index = false;
            if (std.mem.eql(u8, rule, "no-timestamps")) cfg.check_timestamps = false;
            if (std.mem.eql(u8, rule, "wide-table")) cfg.check_wide_table = false;
            if (std.mem.eql(u8, rule, "enum-case")) cfg.check_enum_case = false;
            if (std.mem.eql(u8, rule, "count")) cfg.check_count = false;
            if (std.mem.eql(u8, rule, "fk-cascade")) cfg.check_fk_cascade = false;
            if (std.mem.eql(u8, rule, "nullable-pk")) cfg.check_nullable_pk = false;
            if (std.mem.eql(u8, rule, "orphan-type")) cfg.check_orphan_type = false;
            if (std.mem.eql(u8, rule, "index-unused")) cfg.check_index_unused = false;
            if (std.mem.eql(u8, rule, "circular-fk")) cfg.check_circular_fk = false;
        }
    }

    // Apply thresholds
    if (rules.thresholds.wide_table_max) |max| cfg.wide_table_max = max;
    if (rules.thresholds.count_min) |min| cfg.count_min = min;

    return cfg;
}

// ─── Lint Auto-Fix ────────────────────────────────────────────
// Modifies source text to fix lintable issues (no-pk, no-timestamps).
// Works on raw source text — inserts lines at the right positions.

pub const LintFix = struct {
    rule: []const u8,
    table: []const u8,
    description: []const u8,
};

/// Fix lint issues in the source text. Returns the modified source and a list of fixes applied.
pub fn lintFix(alloc: std.mem.Allocator, source: []const u8, results: []const LintResult) !struct { source: []u8, fixes: []LintFix } {
    var fixes = try std.ArrayList(LintFix).initCapacity(alloc, results.len);
    errdefer fixes.deinit(alloc);

    // Pre-scan: find which tables need fixes
    var needs_pk = std.StringHashMap(void).init(alloc);
    defer needs_pk.deinit();
    var needs_timestamps = std.StringHashMap(void).init(alloc);
    defer needs_timestamps.deinit();

    for (results) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) {
            try needs_pk.put(r.table, {});
        } else if (std.mem.eql(u8, r.rule, "no-timestamps")) {
            try needs_timestamps.put(r.table, {});
        }
    }

    // Build output by scanning source character by character
    // Strategy: find table headers and field positions, insert fixes at the right spots
    var output = try std.ArrayList(u8).initCapacity(alloc, source.len + 256);
    errdefer output.deinit(alloc);

    // Track state as we scan
    var i: usize = 0;
    var current_table: ?[]const u8 = null;
    var in_table = false;
    var last_field_end: usize = 0; // byte offset after last field line's newline
    var pk_inserted = std.StringHashMap(void).init(alloc);
    defer pk_inserted.deinit();
    var ts_inserted = std.StringHashMap(void).init(alloc);
    defer ts_inserted.deinit();

    while (i < source.len) {
        // Find end of current line
        const line_start = i;
        while (i < source.len and source[i] != '\n') : (i += 1) {}
        const line_end = i; // index of \n or past end
        if (i < source.len) i += 1; // skip \n

        const line = source[line_start..line_end];

        // Detect table header
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                // Flush timestamp insertion for previous table
                if (current_table) |prev_tbl| {
                    if (needs_timestamps.contains(prev_tbl) and !ts_inserted.contains(prev_tbl) and last_field_end > 0) {
                        // Insert timestamps after the last field of previous table
                        try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t");
                        try fixes.append(alloc, .{
                            .rule = "no-timestamps",
                            .table = prev_tbl,
                            .description = "added created_at and updated_at fields",
                        });
                        try ts_inserted.put(prev_tbl, {});
                    }
                }
                current_table = line[ns..];
                in_table = true;
            }
        }

        // Detect field lines (not starting with #, ;, @, $, or empty)
        if (in_table and line.len > 0 and
            line[0] != '#' and line[0] != ';' and line[0] != '@' and line[0] != '$')
        {
            last_field_end = line_end + 1; // +1 to include the \n
        }

        // Write the current line with its newline
        try output.appendSlice(alloc, line);
        if (line_end < source.len) {
            try output.append(alloc, '\n');
        }

        // After table header line, insert PK if needed
        if (line.len > 0 and line[0] == '#') {
            const ns: usize = if (line.len > 1 and line[1] == ' ') 2 else 1;
            if (ns < line.len) {
                const tbl_name = line[ns..];
                if (needs_pk.contains(tbl_name) and !pk_inserted.contains(tbl_name)) {
                    try output.appendSlice(alloc, "id       n++\n");
                    try fixes.append(alloc, .{
                        .rule = "no-pk",
                        .table = tbl_name,
                        .description = "added primary key field 'id'",
                    });
                    try pk_inserted.put(tbl_name, {});
                }
            }
        }
    }

    // Handle timestamps for the last table (if file doesn't end with a table header)
    if (current_table) |tbl| {
        if (needs_timestamps.contains(tbl) and !ts_inserted.contains(tbl)) {
            try output.appendSlice(alloc, "\ncreated_at t\nupdated_at t");
            try fixes.append(alloc, .{
                .rule = "no-timestamps",
                .table = tbl,
                .description = "added created_at and updated_at fields",
            });
        }
    }

    return .{ .source = try output.toOwnedSlice(alloc), .fixes = try fixes.toOwnedSlice(alloc) };
}
