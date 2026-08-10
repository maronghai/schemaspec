const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const diff_fields = @import("../diff/fields.zig");
const diff_indexes = @import("../diff/indexes.zig");
const diff_fks = @import("../diff/fks.zig");
const diff_types = @import("../diff/types.zig");
const dialect_enum = @import("../dialect/enum.zig");
const utils = @import("../utils.zig");
const Field = ast_mod.Field;
const Dialect = dialect_enum.Dialect;

// ─── Re-export sub-module types ────────────────────────────

pub const FieldAction = diff_types.FieldAction;
pub const IndexAction = diff_types.IndexAction;
pub const IndexDiff = diff_types.IndexDiff;
pub const FkAction = diff_types.FkAction;
pub const FkDiff = diff_types.FkDiff;

// ─── Re-export diff data structures ───────────────────────

pub const TableAction = diff_types.TableAction;
pub const TableMetadataDiff = diff_types.TableMetadataDiff;
pub const FieldDiff = diff_types.FieldDiff;
pub const ViewAction = diff_types.ViewAction;
pub const ViewDiff = diff_types.ViewDiff;
pub const CustomTypeAction = diff_types.CustomTypeAction;
pub const CustomTypeDiff = diff_types.CustomTypeDiff;
pub const SchemaDiff = diff_types.SchemaDiff;
pub const TableDiff = diff_types.TableDiff;

// ─── Helpers ───────────────────────────────────────────────

const optionalStrEq = utils.optionalStrEq;

// ─── Capacity Constants ────────────────────────────────────
// Initial ArrayList capacities based on typical schema patterns.
// Most schemas have 5-20 tables; few changes per migration.

/// Typical number of table diffs in a single migration (5-10 common).
const INITIAL_TABLE_DIFF_CAPACITY = 8;
/// Typical number of dropped tables per migration (1-3 common).
const INITIAL_DROPPED_TABLES_CAPACITY = 4;
/// Typical number of view diffs per migration (0-2 common).
const INITIAL_VIEW_DIFF_CAPACITY = 4;

// ─── Detection Thresholds ───────────────────────────────────
// Thresholds for heuristic-based detection in the diff engine.

/// Minimum field overlap ratio to consider a drop+create pair as a table rename.
/// When a dropped table and a created table share at least this fraction of fields,
/// the diff engine treats them as a rename rather than separate drop+create.
const RENAME_OVERLAP_THRESHOLD: f64 = 0.7;

// ─── Diff Engine ───────────────────────────────────────────

/// Compare two ResolvedAsts and produce a SchemaDiff describing all differences.
pub fn diff(old: resolved_ast.ResolvedAst, new: resolved_ast.ResolvedAst, alloc: std.mem.Allocator) !SchemaDiff {
    var table_diffs = try std.ArrayList(TableDiff).initCapacity(alloc, INITIAL_TABLE_DIFF_CAPACITY);
    errdefer table_diffs.deinit(alloc);
    var dropped_tables = try std.ArrayList([]const u8).initCapacity(alloc, INITIAL_DROPPED_TABLES_CAPACITY);
    errdefer dropped_tables.deinit(alloc);
    var view_diffs = try std.ArrayList(ViewDiff).initCapacity(alloc, INITIAL_VIEW_DIFF_CAPACITY);
    errdefer view_diffs.deinit(alloc);

    // Build name→table maps
    var old_map = std.StringHashMap(usize).init(alloc);
    defer old_map.deinit();
    for (old.tables, 0..) |t, i| try old_map.put(t.name, i);
    var new_map = std.StringHashMap(usize).init(alloc);
    defer new_map.deinit();
    for (new.tables, 0..) |t, i| try new_map.put(t.name, i);

    // Collect dropped and created table names for rename detection
    var pending_drops = try std.ArrayList([]const u8).initCapacity(alloc, INITIAL_DROPPED_TABLES_CAPACITY);
    defer pending_drops.deinit(alloc);
    var pending_creates = try std.ArrayList(usize).initCapacity(alloc, INITIAL_TABLE_DIFF_CAPACITY);
    defer pending_creates.deinit(alloc);

    // Tables in new but not old → pending creates
    for (new.tables, 0..) |new_table, i| {
        if (!old_map.contains(new_table.name)) {
            try pending_creates.append(alloc, i);
        }
    }

    // Tables in old but not new → pending drops
    for (old.tables) |old_table| {
        if (!new_map.contains(old_table.name)) {
            try pending_drops.append(alloc, old_table.name);
        }
    }

    // Table-level rename detection: match dropped tables with created tables
    // when field overlap exceeds 70%.
    var matched_drops = std.StringHashMap(void).init(alloc);
    defer matched_drops.deinit();
    var matched_creates = std.AutoHashMap(usize, void).init(alloc);
    defer matched_creates.deinit();

    for (pending_drops.items) |old_name| {
        const old_idx = old_map.get(old_name) orelse continue;
        const old_table = old.tables[old_idx];
        var best_match: ?struct { new_idx: usize, overlap: f64 } = null;

        for (pending_creates.items) |new_idx| {
            if (matched_creates.contains(new_idx)) continue;
            const new_table = new.tables[new_idx];
            const overlap = computeFieldOverlap(old_table.fields, new_table.fields);
            if (overlap >= RENAME_OVERLAP_THRESHOLD) {
                if (best_match == null or overlap > best_match.?.overlap) {
                    best_match = .{ .new_idx = new_idx, .overlap = overlap };
                }
            }
        }

        if (best_match) |bm| {
            const new_table = new.tables[bm.new_idx];
            const field_diffs = try diff_fields.diffFields(alloc, old_table.fields, new_table.fields);
            const index_diffs = try diff_indexes.diffIndexes(alloc, old_table.indexes, new_table.indexes, field_diffs);
            const fk_diffs = try diff_fks.diffFks(alloc, old_table.fks, new_table.fks, field_diffs);
            const metadata_diff = TableMetadataDiff{
                .old_comment = old_table.comment,
                .new_comment = new_table.comment,
                .old_engine = old_table.engine,
                .new_engine = new_table.engine,
            };
            try table_diffs.append(alloc, .{
                .name = new_table.name,
                .action = .alter,
                .field_diffs = field_diffs,
                .index_diffs = index_diffs,
                .fk_diffs = fk_diffs,
                .metadata_diff = if (metadata_diff.hasChanges()) metadata_diff else null,
                .rename_from = old_name,
            });
            try matched_drops.put(old_name, {});
            try matched_creates.put(bm.new_idx, {});
        }
    }

    // Remaining creates (not matched as renames)
    for (pending_creates.items) |new_idx| {
        if (!matched_creates.contains(new_idx)) {
            const new_table = new.tables[new_idx];
            const field_diffs = try diff_fields.createAllFieldDiffs(alloc, new_table.fields);
            const index_diffs = try diff_indexes.createAllIndexDiffs(alloc, new_table.indexes);
            const fk_diffs = try diff_fks.createAllFkDiffs(alloc, new_table.fks);
            try table_diffs.append(alloc, .{
                .name = new_table.name,
                .action = .create,
                .field_diffs = field_diffs,
                .index_diffs = index_diffs,
                .fk_diffs = fk_diffs,
            });
        }
    }

    // Remaining drops (not matched as renames)
    for (pending_drops.items) |old_name| {
        if (!matched_drops.contains(old_name)) {
            try dropped_tables.append(alloc, old_name);
        }
    }

    // Tables in both → compare
    for (old.tables) |old_table| {
        if (new_map.get(old_table.name)) |new_idx| {
            const new_table = new.tables[new_idx];
            const td = try diffTable(alloc, old_table, new_table);
            if (td.field_diffs.len > 0 or td.index_diffs.len > 0 or td.fk_diffs.len > 0 or td.metadata_diff != null) {
                try table_diffs.append(alloc, td);
            }
        }
    }

    // Views: build name→view maps
    var old_view_map = std.StringHashMap(usize).init(alloc);
    defer old_view_map.deinit();
    for (old.views, 0..) |v, i| try old_view_map.put(v.name, i);
    var new_view_map = std.StringHashMap(usize).init(alloc);
    defer new_view_map.deinit();
    for (new.views, 0..) |v, i| try new_view_map.put(v.name, i);

    // Views in new but not old → create
    for (new.views) |new_view| {
        if (!old_view_map.contains(new_view.name)) {
            try view_diffs.append(alloc, .{ .name = new_view.name, .action = .create });
        }
    }
    // Views in old but not new → drop
    for (old.views) |old_view| {
        if (!new_view_map.contains(old_view.name)) {
            try view_diffs.append(alloc, .{ .name = old_view.name, .action = .drop });
        }
    }
    // Views in both → check for query change
    for (old.views) |old_view| {
        if (new_view_map.get(old_view.name)) |new_idx| {
            const new_view = new.views[new_idx];
            if (!viewQueriesEql(old_view, new_view)) {
                try view_diffs.append(alloc, .{ .name = old_view.name, .action = .modify });
            }
        }
    }

    // Safe toOwnedSlice: transfer ownership of the backing buffer
    const table_diffs_slice = try table_diffs.toOwnedSlice(alloc);
    const dropped_tables_slice = try dropped_tables.toOwnedSlice(alloc);
    const view_diffs_slice = try view_diffs.toOwnedSlice(alloc);

    // Custom types: diff between old and new custom type definitions
    var custom_type_diffs = try std.ArrayList(diff_types.CustomTypeDiff).initCapacity(alloc, 4);
    errdefer custom_type_diffs.deinit(alloc);

    var old_ct_map = std.StringHashMap(usize).init(alloc);
    defer old_ct_map.deinit();
    for (old.custom_types, 0..) |ct, i| try old_ct_map.put(ct.name, i);
    var new_ct_map = std.StringHashMap(usize).init(alloc);
    defer new_ct_map.deinit();
    for (new.custom_types, 0..) |ct, i| try new_ct_map.put(ct.name, i);

    // Custom types in new but not old → added
    for (new.custom_types) |new_ct| {
        if (!old_ct_map.contains(new_ct.name)) {
            try custom_type_diffs.append(alloc, .{
                .name = new_ct.name,
                .action = .add,
                .old_type = null,
                .new_type = new_ct,
            });
        }
    }
    // Custom types in old but not new → dropped
    for (old.custom_types) |old_ct| {
        if (!new_ct_map.contains(old_ct.name)) {
            try custom_type_diffs.append(alloc, .{
                .name = old_ct.name,
                .action = .drop,
                .old_type = old_ct,
                .new_type = null,
            });
        }
    }
    // Custom types in both → check for changes
    for (old.custom_types) |old_ct| {
        if (new_ct_map.get(old_ct.name)) |new_idx| {
            const new_ct = new.custom_types[new_idx];
            if (!customTypesEql(old_ct, new_ct)) {
                try custom_type_diffs.append(alloc, .{
                    .name = old_ct.name,
                    .action = .modify,
                    .old_type = old_ct,
                    .new_type = new_ct,
                });
            }
        }
    }

    const custom_type_diffs_slice = try custom_type_diffs.toOwnedSlice(alloc);

    return .{
        .table_diffs = table_diffs_slice,
        .dropped_tables = dropped_tables_slice,
        .view_diffs = view_diffs_slice,
        .custom_type_diffs = custom_type_diffs_slice,
    };
}

/// Compare two views for equality (query + union parts).
fn viewQueriesEql(old: ast_mod.View, new: ast_mod.View) bool {
    if (!std.mem.eql(u8, old.query, new.query)) return false;
    if (old.union_op == null and new.union_op == null) return true;
    if (old.union_op == null or new.union_op == null) return false;
    if (old.union_op.? != new.union_op.?) return false;
    const old_second = old.second_query orelse "";
    const new_second = new.second_query orelse "";
    return std.mem.eql(u8, old_second, new_second);
}

/// Compute field name overlap ratio between two field lists.
/// Returns a value between 0.0 (no overlap) and 1.0 (identical fields).
/// Used for table-level rename detection.
/// Optimized: O(n+m) via hash set instead of O(n*m) nested loop.
fn computeFieldOverlap(old_fields: []const ast_mod.Field, new_fields: []const ast_mod.Field) f64 {
    if (old_fields.len == 0 and new_fields.len == 0) return 1.0;
    if (old_fields.len == 0 or new_fields.len == 0) return 0.0;

    // Build a hash set of old field names, then probe with new field names.
    // This is O(n+m) instead of O(n*m).
    var old_names = std.StringHashMap(void).init(std.heap.page_allocator);
    defer old_names.deinit();
    for (old_fields) |old_field| {
        old_names.put(old_field.name, {}) catch continue;
    }

    var match_count: usize = 0;
    for (new_fields) |new_field| {
        if (old_names.contains(new_field.name)) {
            match_count += 1;
        }
    }

    // Jaccard-like similarity: intersection / union
    const max_fields = @max(old_fields.len, new_fields.len);
    return @as(f64, @floatFromInt(match_count)) / @as(f64, @floatFromInt(max_fields));
}

/// Compare two custom types for equality (base type + dialect overrides).
fn customTypesEql(a: ast_mod.CustomType, b: ast_mod.CustomType) bool {
    if (!a.base.eql(b.base)) return false;
    if (a.dialect_overrides.len != b.dialect_overrides.len) return false;
    for (a.dialect_overrides, 0..) |ao, i| {
        if (ao.dialect != b.dialect_overrides[i].dialect) return false;
        if (!ao.type_info.eql(b.dialect_overrides[i].type_info)) return false;
    }
    return true;
}

fn diffTable(alloc: std.mem.Allocator, old: resolved_ast.ResolvedTable, new: resolved_ast.ResolvedTable) !TableDiff {
    const field_diffs = try diff_fields.diffFields(alloc, old.fields, new.fields);
    const index_diffs = try diff_indexes.diffIndexes(alloc, old.indexes, new.indexes, field_diffs);
    const fk_diffs = try diff_fks.diffFks(alloc, old.fks, new.fks, field_diffs);

    // Compare metadata (comment, engine)
    const metadata_diff = TableMetadataDiff{
        .old_comment = old.comment,
        .new_comment = new.comment,
        .old_engine = old.engine,
        .new_engine = new.engine,
    };

    return .{
        .name = old.name,
        .action = .alter,
        .field_diffs = field_diffs,
        .index_diffs = index_diffs,
        .fk_diffs = fk_diffs,
        .metadata_diff = if (metadata_diff.hasChanges()) metadata_diff else null,
    };
}
