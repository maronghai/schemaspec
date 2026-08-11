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
