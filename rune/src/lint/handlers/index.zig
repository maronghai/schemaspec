const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;
const validation = @import("validation.zig");

// ─── Index Validation Rules ───────────────────────────────────
// Rules that validate index integrity: unused indexes, duplicates,
// and missing column references.

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

// ─── Helpers ──────────────────────────────────────────────────


fn setEquals(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a) |x| {
        var found = false;
        for (b) |y| {
            if (std.mem.eql(u8, x, y)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn indexesEqual(a: ast_mod.IndexDecl, b: ast_mod.IndexDecl) bool {
    if (a.kind != b.kind) return false;
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, 0..) |field_a, idx| {
        if (!std.mem.eql(u8, field_a, b.fields[idx])) return false;
    }
    return true;
}

pub fn checkIndexRedundantWithPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Collect PK columns
        var pk_columns = try std.ArrayList([]const u8).initCapacity(alloc, table.fields.len);
        defer pk_columns.deinit(alloc);

        for (table.fields) |field| {
            if (validation.isPrimaryKey(field)) {
                try pk_columns.append(alloc, field.name);
            }
        }
        for (table.indexes) |idx| {
            if (idx.kind == .primary_key) {
                for (idx.fields) |f| {
                    // Avoid duplicates
                    var found = false;
                    for (pk_columns.items) |pk| {
                        if (std.mem.eql(u8, pk, f)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) try pk_columns.append(alloc, f);
                }
            }
        }

        if (pk_columns.items.len == 0) continue;

        // Check each non-PK index
        for (table.indexes) |idx| {
            if (idx.kind == .primary_key) continue;
            if (idx.fields.len != pk_columns.items.len) continue;

            var matches_pk = true;
            for (idx.fields) |idx_field| {
                var found = false;
                for (pk_columns.items) |pk| {
                    if (std.mem.eql(u8, idx_field, pk)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    matches_pk = false;
                    break;
                }
            }

            if (matches_pk) {
                const msg = try std.fmt.allocPrint(alloc, "index '{s}' duplicates the primary key columns", .{idx.name});
                try results.append(alloc, .{
                    .rule = "index-redundant-with-pk",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if an index name exceeds the configured maximum length.
/// Symmetric with column-name-too-long / table-name-length: long identifier
/// names can break migration tooling and exceed database name-length limits.
pub fn checkIndexNameTooLong(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.indexes) |idx| {
            if (idx.name.len > cfg.column_name_max) {
                const msg = try std.fmt.allocPrint(alloc, "index name '{s}' on table '{s}' is {d} chars (max: {d})", .{ idx.name, table.name, idx.name.len, cfg.column_name_max });
                try results.append(alloc, .{
                    .rule = "index-name-too-long",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if a table has no indexes at all (potential performance issue).
/// Skips empty tables and tables with only a primary key (which is implicit).
pub fn checkTableNoIndex(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Skip empty tables
        if (table.fields.len == 0) continue;
        // Skip tables with no explicit indexes
        if (table.indexes.len == 0) {
            const msg = try std.fmt.allocPrint(alloc, "table has no indexes — consider adding indexes for query performance", .{});
            try results.append(alloc, .{
                .rule = "table-no-index",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

/// Check for an index that duplicates the one auto-created for a foreign key column.
/// Databases automatically create an index on FK columns; an explicit standalone
/// (non-unique) index covering the same columns is redundant. Symmetric with
/// `index-redundant-with-pk` but for FK columns instead of the PK.
pub fn checkIndexRedundantWithFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Collect column sets that the database auto-indexes for FKs (local FK columns).
        var fk_sets = try std.ArrayList([]const []const u8).initCapacity(alloc, table.fields.len);
        defer fk_sets.deinit(alloc);
        for (table.fields) |field| {
            const fk = field.fk orelse continue;
            if (fk.fields.len == 0) continue;
            try fk_sets.append(alloc, fk.fields);
        }

        if (fk_sets.items.len == 0) continue;

        // Check each standalone (non-PK, non-unique) index against the FK index sets.
        for (table.indexes) |idx| {
            if (idx.kind == .primary_key or idx.kind == .unique) continue;
            for (fk_sets.items) |fk_set| {
                if (setEquals(idx.fields, fk_set)) {
                    const msg = try std.fmt.allocPrint(alloc, "index '{s}' duplicates the index auto-created for a foreign key column", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "index-redundant-with-fk",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                    break;
                }
            }
        }
    }
}

