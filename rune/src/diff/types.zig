const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const utils = @import("../utils.zig");

// ─── Diff Data Types ────────────────────────────────────────────
// All diff-related data types live here to avoid circular dependencies.
// diff/fields.zig, diff/indexes.zig, diff/fks.zig import from here.

pub const FieldDiff = struct {
    name: []const u8,
    action: FieldAction,
    old_field: ?ast_mod.Field,
    new_field: ?ast_mod.Field,
    rename_from: ?[]const u8,
};

pub const FieldAction = enum { add, modify, drop, rename };

pub const IndexDiff = struct {
    name: []const u8,
    action: IndexAction,
    old_idx: ?ast_mod.IndexDecl,
    new_idx: ?ast_mod.IndexDecl,
};

pub const IndexAction = enum { add, drop, modify };

pub const FkDiff = struct {
    action: FkAction,
    old_fk: ?ast_mod.FkDecl,
    new_fk: ?ast_mod.FkDecl,
};

pub const FkAction = enum { add, drop, modify };

pub const TableAction = enum { create, alter };

pub const TableMetadataDiff = struct {
    old_comment: ?[]const u8,
    new_comment: ?[]const u8,
    old_engine: ?[]const u8,
    new_engine: ?[]const u8,
    pub fn hasChanges(self: TableMetadataDiff) bool {
        return !utils.optionalStrEq(self.old_comment, self.new_comment) or
            !utils.optionalStrEq(self.old_engine, self.new_engine);
    }
};

pub const ViewAction = enum { create, drop, modify };

pub const ViewDiff = struct {
    name: []const u8,
    action: ViewAction,
};

pub const SchemaDiff = struct {
    table_diffs: []const TableDiff,
    dropped_tables: [][]const u8,
    view_diffs: []const ViewDiff,
};

pub const TableDiff = struct {
    name: []const u8,
    action: TableAction,
    field_diffs: []const FieldDiff,
    index_diffs: []const IndexDiff,
    fk_diffs: []const FkDiff,
    metadata_diff: ?TableMetadataDiff = null,
};
