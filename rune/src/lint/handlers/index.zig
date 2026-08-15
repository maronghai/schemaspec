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

/// True when `prefix` is a strict leading-column prefix of `full` (same columns in order,
/// strictly shorter). Used by `index-consistency-pass` to detect redundant prefix indexes.
fn isPrefix(prefix: []const []const u8, full: []const []const u8) bool {
    if (prefix.len == 0 or prefix.len >= full.len) return false;
    for (prefix, 0..) |p, i| {
        if (i >= full.len) return false;
        if (!std.mem.eql(u8, p, full[i])) return false;
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

/// `unique-index-redundant-with-fk` — completes the FK-redundancy direction of the index-redundancy
/// family. `index-redundant-with-fk` only flags `regular` standalone indexes that duplicate the index a
/// database auto-creates for a foreign-key column; this rule closes the remaining `unique` direction. A
/// standalone `unique` index on a foreign-key column is redundant because the database already creates an
/// (implicit regular) index for the FK column, and the explicit `unique` index duplicates that coverage (and
/// is frequently also semantically wrong, since FK columns are not necessarily unique). Non-fixable: the
/// author must decide whether to drop the redundant index or the constraint. Disjoint from
/// `index-redundant-with-fk` by index kind, so the two never double-flag the same index.
pub fn checkUniqueIndexRedundantWithFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
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

        // Check each standalone UNIQUE index against the FK index sets.
        for (table.indexes) |idx| {
            if (idx.kind != .unique) continue;
            for (fk_sets.items) |fk_set| {
                if (setEquals(idx.fields, fk_set)) {
                    const msg = try std.fmt.allocPrint(alloc, "unique index '{s}' duplicates the index auto-created for a foreign key column", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "unique-index-redundant-with-fk",
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

/// `index-redundant-with-unique` — warns when a standalone (regular) index duplicates the
/// index a database auto-creates for a UNIQUE constraint. A UNIQUE modifier on a column
/// (inline `+`) or an explicit unique index already produce a backing index, so an explicit
/// regular index on the same column(s) is redundant. Symmetric with `index-redundant-with-pk`
/// (PK) and `index-redundant-with-fk` (FK), completing the index-redundancy family.
/// Non-fixable: the author must decide whether to drop the redundant index or the constraint.
pub fn checkIndexRedundantWithUnique(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Collect column sets the database auto-indexes for UNIQUE constraints.
        var unique_sets = try std.ArrayList([]const []const u8).initCapacity(alloc, table.fields.len);
        defer unique_sets.deinit(alloc);

        // (a) Inline UNIQUE modifier on a column creates a single-column backing index.
        for (table.fields) |field| {
            var has_unique = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_unique) {
                    has_unique = true;
                    break;
                }
            }
            if (has_unique) {
                const single = try alloc.alloc([]const u8, 1);
                single[0] = field.name;
                try unique_sets.append(alloc, single);
            }
        }

        // (b) Explicit unique indexes also produce a backing index.
        for (table.indexes) |idx| {
            if (idx.kind == .unique) {
                try unique_sets.append(alloc, idx.fields);
            }
        }

        if (unique_sets.items.len == 0) continue;

        // Check each standalone (regular) index against the unique index sets.
        for (table.indexes) |idx| {
            if (idx.kind != .regular) continue;
            for (unique_sets.items) |u_set| {
                if (setEquals(idx.fields, u_set)) {
                    const msg = try std.fmt.allocPrint(alloc, "index '{s}' duplicates the index auto-created for a UNIQUE constraint on the same column(s)", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "index-redundant-with-unique",
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

/// `index-consistency-pass` — extends the index-redundancy family beyond the PK/FK/UNIQUE
/// trio toward full duplicate/prefix coverage. Two symmetric, non-fixable checks:
///
///   (1) reverse-UNIQUE: a standalone `unique` index that duplicates the UNIQUE constraint
///       already implied by an inline `+` unique column (the reverse direction of
///       `index-redundant-with-unique`, which only flags `regular` indexes). An inline `+`
///       unique modifier already makes the database create a backing UNIQUE index, so an
///       explicit `unique` index on the same column is redundant. (Two `unique` indexes with
///       identical columns are same-kind and already caught by `duplicate-index`, so this rule
///       targets only the inline-unique direction.)
///   (2) prefix: a standalone `regular` index whose column set is a *non-trailing prefix* of a
///       UNIQUE or PRIMARY-KEY index is redundant — the leading column(s) are already covered by
///       the larger index's backing index (e.g. a `regular` index on (a) when the PK is (a,b,c),
///       or a `regular` index on (tenant_id) when a `unique` index is (tenant_id,user_id)).
///       Exact matches are intentionally excluded: they are already flagged by
///       `index-redundant-with-pk` / `index-redundant-with-unique`.
/// Non-fixable: the author must decide which index/constraint to drop.
pub fn checkIndexConsistencyPass(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // ── Collect the full ordered PK column list (inline PK modifiers + explicit PK index). ──
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

        // ── Collect column sets that already carry a UNIQUE backing index. ──
        // inline_unique_cols: single-column sets from inline `+` unique modifiers (check 1 target).
        // unique_sets: every UNIQUE-backed column set (inline + explicit unique index), used as
        // prefix-check targets in check 2.
        var inline_unique_cols = try std.ArrayList([]const u8).initCapacity(alloc, table.fields.len);
        defer inline_unique_cols.deinit(alloc);
        var unique_sets = try std.ArrayList([]const []const u8).initCapacity(alloc, table.fields.len);
        defer unique_sets.deinit(alloc);
        for (table.fields) |field| {
            var has_unique = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_unique) {
                    has_unique = true;
                    break;
                }
            }
            if (has_unique) {
                try inline_unique_cols.append(alloc, field.name);
                const single = try alloc.alloc([]const u8, 1);
                single[0] = field.name;
                try unique_sets.append(alloc, single);
            }
        }
        for (table.indexes) |idx| {
            if (idx.kind == .unique) {
                try unique_sets.append(alloc, idx.fields);
            }
        }

        // ── Check (1): reverse-UNIQUE — an explicit `unique` index duplicating an inline `+` unique column. ──
        for (table.indexes) |idx| {
            if (idx.kind != .unique) continue;
            for (inline_unique_cols.items) |col| {
                if (idx.fields.len == 1 and std.mem.eql(u8, idx.fields[0], col)) {
                    const msg = try std.fmt.allocPrint(alloc, "index '{s}' duplicates the UNIQUE constraint already implied by an inline '+' unique column on the same column(s)", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "index-consistency-pass",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                    break;
                }
            }
        }

        // ── Check (2): prefix — a `regular` index that is a non-trailing prefix of a UNIQUE/PK index. ──
        for (table.indexes) |idx| {
            if (idx.kind != .regular) continue;
            if (idx.fields.len == 0) continue;
            // Compare against the PK column set.
            if (pk_columns.items.len > idx.fields.len and isPrefix(idx.fields, pk_columns.items)) {
                const msg = try std.fmt.allocPrint(alloc, "index '{s}' is a redundant prefix of the primary key — its leading column(s) are already covered by the primary key", .{idx.name});
                try results.append(alloc, .{
                    .rule = "index-consistency-pass",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
                continue;
            }
            // Compare against each UNIQUE index/constraint column set.
            for (unique_sets.items) |u_set| {
                if (u_set.len > idx.fields.len and isPrefix(idx.fields, u_set)) {
                    const msg = try std.fmt.allocPrint(alloc, "index '{s}' is a redundant prefix of a UNIQUE index — its leading column(s) are already covered", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "index-consistency-pass",
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

/// `unique-prefix-redundancy` — extends the redundant-prefix detection added in
/// `index-consistency-pass` to also fire for `unique` indexes that are non-trailing
/// *prefixes* of a larger UNIQUE or PRIMARY-KEY index (a redundant leading-column
/// unique index), completing the prefix-direction coverage for `unique` as well as
/// `regular` indexes. Symmetric with `index-consistency-pass` check (2) (which only
/// handles `regular` indexes) and with `index-redundant-with-pk` / `index-redundant-with-unique`
/// (which only handle exact column-set matches). Non-fixable: the author must decide
/// which index to drop.
pub fn checkUniquePrefixRedundancy(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // ── Collect the full ordered PK column list (inline PK modifiers + explicit PK index). ──
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

        // ── Collect column sets that already carry a UNIQUE backing index. ──
        var unique_sets = try std.ArrayList([]const []const u8).initCapacity(alloc, table.fields.len);
        defer unique_sets.deinit(alloc);
        for (table.fields) |field| {
            var has_unique = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_unique) {
                    has_unique = true;
                    break;
                }
            }
            if (has_unique) {
                const single = try alloc.alloc([]const u8, 1);
                single[0] = field.name;
                try unique_sets.append(alloc, single);
            }
        }
        for (table.indexes) |idx| {
            if (idx.kind == .unique) {
                try unique_sets.append(alloc, idx.fields);
            }
        }

        // ── Check: a `unique` index that is a non-trailing prefix of a larger UNIQUE or PK index. ──
        for (table.indexes) |idx| {
            if (idx.kind != .unique) continue;
            if (idx.fields.len == 0) continue;
            // Compare against the PK column set.
            if (pk_columns.items.len > idx.fields.len and isPrefix(idx.fields, pk_columns.items)) {
                const msg = try std.fmt.allocPrint(alloc, "unique index '{s}' is a redundant prefix of the primary key — its leading column(s) are already covered by the primary key", .{idx.name});
                try results.append(alloc, .{
                    .rule = "unique-prefix-redundancy",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
                continue;
            }
            // Compare against each UNIQUE index/constraint column set.
            for (unique_sets.items) |u_set| {
                if (u_set.len > idx.fields.len and isPrefix(idx.fields, u_set)) {
                    const msg = try std.fmt.allocPrint(alloc, "unique index '{s}' is a redundant prefix of a UNIQUE index — its leading column(s) are already covered", .{idx.name});
                    try results.append(alloc, .{
                        .rule = "unique-prefix-redundancy",
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

