const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

const SchemaDiff = types.SchemaDiff;
const TableDiff = types.TableDiff;
const ViewDiff = types.ViewDiff;

test "hasChanges: empty diff returns false" {
    const diff = SchemaDiff{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &.{},
    };
    try testing.expect(!diff.hasChanges());
}

test "hasChanges: table diffs returns true" {
    const table_diffs = [_]TableDiff{.{
        .name = "users",
        .action = .alter,
        .field_diffs = &.{},
        .index_diffs = &.{},
        .fk_diffs = &.{},
    }};
    const diff = SchemaDiff{
        .table_diffs = &table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
    };
    try testing.expect(diff.hasChanges());
}

test "hasChanges: view diffs returns true" {
    const view_diffs = [_]ViewDiff{.{
        .name = "active_users",
        .action = .create,
    }};
    const diff = SchemaDiff{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &view_diffs,
    };
    try testing.expect(diff.hasChanges());
}
