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

// ─── Re-export diff data structures ───────────────────────

pub const TableAction = diff_types.TableAction;
pub const TableMetadataDiff = diff_types.TableMetadataDiff;
pub const FieldDiff = diff_types.FieldDiff;
pub const ViewAction = diff_types.ViewAction;
pub const ViewDiff = diff_types.ViewDiff;
pub const SchemaDiff = diff_types.SchemaDiff;
pub const TableDiff = diff_types.TableDiff;

// ─── Helpers ───────────────────────────────────────────────

const optionalStrEq = utils.optionalStrEq;

// ─── Diff Engine ───────────────────────────────────────────

/// Compare two ResolvedAsts and produce a SchemaDiff describing all differences.
pub fn diff(old: resolved_ast.ResolvedAst, new: resolved_ast.ResolvedAst, alloc: std.mem.Allocator, dialect: ?Dialect) !SchemaDiff {
    var table_diffs = try std.ArrayList(TableDiff).initCapacity(alloc, 8);
    var dropped_tables = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    var view_diffs = try std.ArrayList(ViewDiff).initCapacity(alloc, 4);

    // Build name→table maps
    var old_map = std.StringHashMap(usize).init(alloc);
    defer old_map.deinit();
    for (old.tables, 0..) |t, i| try old_map.put(t.name, i);
    var new_map = std.StringHashMap(usize).init(alloc);
    defer new_map.deinit();
    for (new.tables, 0..) |t, i| try new_map.put(t.name, i);

    // Tables in new but not old → create
    for (new.tables) |new_table| {
        if (!old_map.contains(new_table.name)) {
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

    // Tables in old but not new → dropped
    for (old.tables) |old_table| {
        if (!new_map.contains(old_table.name)) {
            try dropped_tables.append(alloc, old_table.name);
        }
    }

    // Tables in both → compare
    for (old.tables) |old_table| {
        if (new_map.get(old_table.name)) |new_idx| {
            const new_table = new.tables[new_idx];
            const td = try diffTable(alloc, old_table, new_table, dialect);
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

    // Safe toOwnedSlice: copy items to new allocation, then free ArrayList buffer
    const table_diffs_slice = try alloc.dupe(TableDiff, table_diffs.items);
    table_diffs.clearAndFree(alloc);
    const dropped_tables_slice = try alloc.dupe([]const u8, dropped_tables.items);
    dropped_tables.clearAndFree(alloc);
    const view_diffs_slice = try alloc.dupe(ViewDiff, view_diffs.items);
    view_diffs.clearAndFree(alloc);

    return .{
        .table_diffs = table_diffs_slice,
        .dropped_tables = dropped_tables_slice,
        .view_diffs = view_diffs_slice,
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

fn diffTable(alloc: std.mem.Allocator, old: resolved_ast.ResolvedTable, new: resolved_ast.ResolvedTable, dialect: ?Dialect) !TableDiff {
    const field_diffs = try diff_fields.diffFields(alloc, old.fields, new.fields, dialect);
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
