const std = @import("std");
const testing = std.testing;
const migrate_json = @import("migrate_json.zig");
const diff_types = @import("types.zig");

// ─── Helpers ─────────────────────────────────────────────────────

fn allocStrSlice(alloc: std.mem.Allocator, items: []const []const u8) ![][]const u8 {
    const slice = try alloc.alloc([]const u8, items.len);
    for (items, 0..) |item, i| slice[i] = item;
    return slice;
}

// ─── Tests ───────────────────────────────────────────────────────

test "migrate_json: empty diff" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"operations\": []") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"dialect\": \"mysql\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"wrapped_in_transaction\": true") != null);
}

test "migrate_json: drop table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const dropped = try allocStrSlice(alloc, &.{"users"});
    const result = try migrate_json.generateMigrationJson(alloc, .{
        .table_diffs = &.{},
        .dropped_tables = dropped,
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_table\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"table\": \"users\"") != null);
}

test "migrate_json: create table" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "orders",
            .action = .create,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"create_table\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"table\": \"orders\"") != null);
}

test "migrate_json: add column" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &[_]diff_types.FieldDiff{.{
                .name = "email",
                .action = .add,
                .old_field = null,
                .new_field = null,
                .rename_from = null,
            }},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"add_column\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"column\": \"email\"") != null);
}

test "migrate_json: drop column" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &[_]diff_types.FieldDiff{.{
                .name = "legacy_field",
                .action = .drop,
                .old_field = null,
                .new_field = null,
                .rename_from = null,
            }},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_column\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"column\": \"legacy_field\"") != null);
}

test "migrate_json: modify column" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "orders",
            .action = .alter,
            .field_diffs = &[_]diff_types.FieldDiff{.{
                .name = "status",
                .action = .modify,
                .old_field = null,
                .new_field = null,
                .rename_from = null,
            }},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"modify_column\"") != null);
}

test "migrate_json: rename column" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &[_]diff_types.FieldDiff{.{
                .name = "new_name",
                .action = .rename,
                .old_field = null,
                .new_field = null,
                .rename_from = "old_name",
            }},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"rename_column\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"from\": \"old_name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"to\": \"new_name\"") != null);
}

test "migrate_json: add index" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &[_]diff_types.IndexDiff{.{
                .name = "idx_email",
                .action = .add,
                .old_idx = null,
                .new_idx = null,
            }},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"add_index\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"index\": \"idx_email\"") != null);
}

test "migrate_json: drop index" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &[_]diff_types.IndexDiff{.{
                .name = "idx_old",
                .action = .drop,
                .old_idx = null,
                .new_idx = null,
            }},
            .fk_diffs = &.{},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_index\"") != null);
}

test "migrate_json: add fk" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "orders",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &[_]diff_types.FkDiff{.{
                .action = .add,
                .old_fk = null,
                .new_fk = null,
            }},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"add_fk\"") != null);
}

test "migrate_json: drop fk" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "orders",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &[_]diff_types.FkDiff{.{
                .action = .drop,
                .old_fk = null,
                .new_fk = null,
            }},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_fk\"") != null);
}

test "migrate_json: modify fk" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "orders",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &[_]diff_types.FkDiff{.{
                .action = .modify,
                .old_fk = null,
                .new_fk = null,
            }},
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"modify_fk\"") != null);
}

test "migrate_json: view diffs" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &[_]diff_types.ViewDiff{
            .{ .name = "v_active", .action = .create },
            .{ .name = "v_old", .action = .drop },
            .{ .name = "v_changed", .action = .modify },
        },
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"create_view\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_view\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"modify_view\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"view\": \"v_active\"") != null);
}

test "migrate_json: metadata diff with changes" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &.{},
            .metadata_diff = .{
                .old_comment = "old comment",
                .new_comment = "new comment",
                .old_engine = null,
                .new_engine = null,
            },
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"alter_metadata\"") != null);
}

test "migrate_json: metadata diff no changes" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &.{},
            .metadata_diff = .{
                .old_comment = "same",
                .new_comment = "same",
                .old_engine = null,
                .new_engine = null,
            },
        }},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .mysql);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"alter_metadata\"") == null);
}

test "migrate_json: mixed operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const dropped = try allocStrSlice(alloc, &.{"old_table"});
    const result = try migrate_json.generateMigrationJson(alloc, .{
        .table_diffs = &[_]diff_types.TableDiff{.{
            .name = "users",
            .action = .alter,
            .field_diffs = &[_]diff_types.FieldDiff{.{
                .name = "new_col",
                .action = .add,
                .old_field = null,
                .new_field = null,
                .rename_from = null,
            }},
            .index_diffs = &.{},
            .fk_diffs = &.{},
        }},
        .dropped_tables = dropped,
        .view_diffs = &[_]diff_types.ViewDiff{.{ .name = "v1", .action = .create }},
        .custom_type_diffs = &.{},
    }, .pg);

    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"drop_table\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"add_column\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type\": \"create_view\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"dialect\": \"pg\"") != null);
}

test "migrate_json: dialect sqlite" {
    const result = try migrate_json.generateMigrationJson(testing.allocator, .{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    }, .sqlite);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"dialect\": \"sqlite\"") != null);
}
