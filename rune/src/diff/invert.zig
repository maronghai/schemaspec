const std = @import("std");
const diff_mod = @import("engine.zig");
const types = @import("types.zig");

/// Pure data transformation: invert a SchemaDiff so that applying the inverted diff
/// to the old schema produces the inverse of the original migration.
///
/// This extracts the field/index/FK inversion logic that was duplicated in
/// `generateRollback` — the core transformation `add↔drop`, `modify swaps old/new`,
/// `rename reverses direction`.
pub fn invertDiff(
    alloc: std.mem.Allocator,
    d: types.SchemaDiff,
) !InvertedDiff {
    // 1. Tables that were CREATED → need to be DROPPED in rollback
    var drop_created = std.ArrayList([]const u8).initCapacity(alloc, d.table_diffs.len) catch return error.OutOfMemory;
    for (d.table_diffs) |td| {
        if (td.action == .create) {
            drop_created.appendAssumeCapacity(td.name);
        }
    }

    // 2. Re-invert ALTER table diffs (add↔drop, modify swaps old/new)
    var inverted_tables = std.ArrayList(types.TableDiff).initCapacity(alloc, d.table_diffs.len) catch return error.OutOfMemory;
    // Track inner ArrayLists for ownership
    var fields_buf = std.ArrayList(std.ArrayList(types.FieldDiff)).initCapacity(alloc, d.table_diffs.len) catch return error.OutOfMemory;
    var indexes_buf = std.ArrayList(std.ArrayList(types.IndexDiff)).initCapacity(alloc, d.table_diffs.len) catch return error.OutOfMemory;
    var fks_buf = std.ArrayList(std.ArrayList(types.FkDiff)).initCapacity(alloc, d.table_diffs.len) catch return error.OutOfMemory;

    for (d.table_diffs) |td| {
        if (td.action != .alter) continue;

        var r_fields = std.ArrayList(types.FieldDiff).initCapacity(alloc, td.field_diffs.len) catch continue;
        for (td.field_diffs) |fd| {
            r_fields.appendAssumeCapacity(invertFieldDiff(fd));
        }

        var r_indexes = std.ArrayList(types.IndexDiff).initCapacity(alloc, td.index_diffs.len) catch continue;
        for (td.index_diffs) |idx_diff| {
            r_indexes.appendAssumeCapacity(invertIndexDiff(idx_diff));
        }

        var r_fks = std.ArrayList(types.FkDiff).initCapacity(alloc, td.fk_diffs.len) catch continue;
        for (td.fk_diffs) |fk_diff| {
            r_fks.appendAssumeCapacity(invertFkDiff(fk_diff));
        }

        fields_buf.appendAssumeCapacity(r_fields);
        indexes_buf.appendAssumeCapacity(r_indexes);
        fks_buf.appendAssumeCapacity(r_fks);
        inverted_tables.appendAssumeCapacity(.{
            .name = td.name,
            .action = .alter,
            .field_diffs = fields_buf.items[fields_buf.items.len - 1].items,
            .index_diffs = indexes_buf.items[indexes_buf.items.len - 1].items,
            .fk_diffs = fks_buf.items[fks_buf.items.len - 1].items,
            .metadata_diff = null,
        });
    }

    return .{
        .drop_created = drop_created.items,
        .inverted_tables = inverted_tables.items,
        .dropped_tables = d.dropped_tables,
        .view_diffs = d.view_diffs,
        // Ownership tracking for cleanup
        ._fields_buf = fields_buf,
        ._indexes_buf = indexes_buf,
        ._fks_buf = fks_buf,
        ._inverted_tables = inverted_tables,
        ._drop_created = drop_created,
    };
}

/// Result of inverting a SchemaDiff. Contains the inverted diff data
/// plus ownership tracking for proper cleanup.
pub const InvertedDiff = struct {
    /// Tables that were created in forward → need DROP in rollback.
    drop_created: []const []const u8,
    /// Re-inverted ALTER table diffs (add↔drop, modify swaps).
    inverted_tables: []const types.TableDiff,
    /// Original dropped tables (need re-CREATE in rollback).
    dropped_tables: [][]const u8,
    /// Original view diffs (reversed at emission time).
    view_diffs: []const types.ViewDiff,

    // Ownership — freed by deinit
    _fields_buf: std.ArrayList(std.ArrayList(types.FieldDiff)),
    _indexes_buf: std.ArrayList(std.ArrayList(types.IndexDiff)),
    _fks_buf: std.ArrayList(std.ArrayList(types.FkDiff)),
    _inverted_tables: std.ArrayList(types.TableDiff),
    _drop_created: std.ArrayList([]const u8),

    pub fn deinit(self: *InvertedDiff, alloc: std.mem.Allocator) void {
        for (self._fields_buf.items) |*list| list.deinit(alloc);
        self._fields_buf.deinit(alloc);
        for (self._indexes_buf.items) |*list| list.deinit(alloc);
        self._indexes_buf.deinit(alloc);
        for (self._fks_buf.items) |*list| list.deinit(alloc);
        self._fks_buf.deinit(alloc);
        self._inverted_tables.deinit(alloc);
        self._drop_created.deinit(alloc);
    }
};

// ─── Per-item Inversion ─────────────────────────────────────────

fn invertFieldDiff(fd: types.FieldDiff) types.FieldDiff {
    return switch (fd.action) {
        .add => .{ .name = fd.name, .action = .drop, .old_field = fd.new_field, .new_field = null, .rename_from = null },
        .drop => .{ .name = fd.name, .action = .add, .old_field = null, .new_field = fd.old_field, .rename_from = null },
        .modify => .{ .name = fd.name, .action = .modify, .old_field = fd.new_field, .new_field = fd.old_field, .rename_from = null },
        .rename => .{ .name = fd.rename_from orelse fd.name, .action = .rename, .old_field = fd.new_field, .new_field = fd.old_field, .rename_from = fd.name },
    };
}

fn invertIndexDiff(idx: types.IndexDiff) types.IndexDiff {
    return switch (idx.action) {
        .add => .{ .name = idx.name, .action = .drop, .old_idx = idx.new_idx, .new_idx = null },
        .drop => .{ .name = idx.name, .action = .add, .old_idx = null, .new_idx = idx.old_idx },
        .modify => .{ .name = idx.name, .action = .modify, .old_idx = idx.new_idx, .new_idx = idx.old_idx },
    };
}

fn invertFkDiff(fk: types.FkDiff) types.FkDiff {
    return switch (fk.action) {
        .add => .{ .action = .drop, .old_fk = fk.new_fk, .new_fk = null },
        .drop => .{ .action = .add, .old_fk = null, .new_fk = fk.old_fk },
        .modify => .{ .action = .modify, .old_fk = fk.new_fk, .new_fk = fk.old_fk },
    };
}

// ─── Tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "invertFieldDiff: add → drop" {
    const fd = types.FieldDiff{
        .name = "email",
        .action = .add,
        .old_field = null,
        .new_field = .{ .name = "email", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .rename_from = null,
    };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.drop, inv.action);
    try testing.expect(inv.old_field != null);
    try testing.expectEqual(@as(?ast_mod.Field, null), inv.new_field);
}

test "invertFieldDiff: drop → add" {
    const fd = types.FieldDiff{
        .name = "email",
        .action = .drop,
        .old_field = .{ .name = "email", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .new_field = null,
        .rename_from = null,
    };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.add, inv.action);
    try testing.expectEqual(@as(?ast_mod.Field, null), inv.old_field);
    try testing.expect(inv.new_field != null);
}

test "invertFieldDiff: modify swaps old/new" {
    const old_f = ast_mod.Field{ .name = "col", .type_info = .{ .simple = "n" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 };
    const new_f = ast_mod.Field{ .name = "col", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 };
    const fd = types.FieldDiff{
        .name = "col",
        .action = .modify,
        .old_field = old_f,
        .new_field = new_f,
        .rename_from = null,
    };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.modify, inv.action);
    try testing.expectEqual(@as(?ast_mod.Field, new_f), inv.old_field);
    try testing.expectEqual(@as(?ast_mod.Field, old_f), inv.new_field);
}

test "invertFieldDiff: rename reverses direction" {
    const fd = types.FieldDiff{
        .name = "new_name",
        .action = .rename,
        .old_field = .{ .name = "old_name", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .new_field = .{ .name = "new_name", .type_info = .{ .simple = "s" }, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .rename_from = "old_name",
    };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.rename, inv.action);
    try testing.expectEqual(@as(?[]const u8, "old_name"), inv.name);
    try testing.expectEqual(@as(?[]const u8, "new_name"), inv.rename_from);
}

const ast_mod = @import("../types/ast.zig");
