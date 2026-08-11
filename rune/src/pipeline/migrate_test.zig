const std = @import("std");
const migrate = @import("migrate.zig");
const diff_types = @import("../diff/types.zig");

const testing = std.testing;

// ─── Helper: Create empty SchemaDiff ──────────────────────────

fn emptySchemaDiff() diff_types.SchemaDiff {
    return .{
        .table_diffs = &.{},
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };
}

// ─── formatMigrationFileName Tests ───────────────────────────

test "formatMigrationFileName: zero-padded sequence" {
    const alloc = testing.allocator;
    const name = try migrate.formatMigrationFileName(alloc, 1, "create_users");
    defer alloc.free(name);
    try testing.expectEqualStrings("0001_create_users.sql", name);
}

test "formatMigrationFileName: high sequence number" {
    const alloc = testing.allocator;
    const name = try migrate.formatMigrationFileName(alloc, 42, "add_email_index");
    defer alloc.free(name);
    try testing.expectEqualStrings("0042_add_email_index.sql", name);
}

test "formatMigrationFileName: four-digit sequence" {
    const alloc = testing.allocator;
    const name = try migrate.formatMigrationFileName(alloc, 1234, "migration");
    defer alloc.free(name);
    try testing.expectEqualStrings("1234_migration.sql", name);
}

// ─── filterIncrementalChanges Tests ───────────────────────────

test "filterIncrementalChanges: keeps structural changes" {
    const alloc = testing.allocator;
    const field_diffs = try alloc.dupe(diff_types.FieldDiff, &.{
        .{
            .name = "email",
            .action = .add,
            .old_field = null,
            .new_field = .{
                .name = "email",
                .type_info = .{ .simple = "s" },
                .modifiers = &.{},
                .default_val = null,
                .check = null,
                .fk = null,
                .comment = null,
                .generated_expr = null,
                .line_no = 0,
                .loc = .{ .line = 0, .col = 0, .offset = 0 },
            },
            .rename_from = null,
        },
    });
    defer alloc.free(field_diffs);

    const table_diffs = try alloc.dupe(diff_types.TableDiff, &.{
        .{
            .name = "users",
            .action = .alter,
            .field_diffs = field_diffs,
            .index_diffs = &.{},
            .fk_diffs = &.{},
            .metadata_diff = null,
        },
    });
    defer alloc.free(table_diffs);

    const sd = diff_types.SchemaDiff{
        .table_diffs = table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try migrate.filterIncrementalChanges(alloc, sd);
    defer alloc.free(result.table_diffs);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqualStrings("users", result.table_diffs[0].name);
}

test "filterIncrementalChanges: removes metadata-only changes" {
    const alloc = testing.allocator;
    const table_diffs = try alloc.dupe(diff_types.TableDiff, &.{
        .{
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
        },
    });
    defer alloc.free(table_diffs);

    const sd = diff_types.SchemaDiff{
        .table_diffs = table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try migrate.filterIncrementalChanges(alloc, sd);
    defer alloc.free(result.table_diffs);
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
}

test "filterIncrementalChanges: keeps create table actions" {
    const alloc = testing.allocator;
    const table_diffs = try alloc.dupe(diff_types.TableDiff, &.{
        .{
            .name = "new_table",
            .action = .create,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = &.{},
            .metadata_diff = null,
        },
    });
    defer alloc.free(table_diffs);

    const sd = diff_types.SchemaDiff{
        .table_diffs = table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try migrate.filterIncrementalChanges(alloc, sd);
    defer alloc.free(result.table_diffs);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
    try testing.expectEqual(diff_types.TableAction.create, result.table_diffs[0].action);
}

test "filterIncrementalChanges: keeps index changes" {
    const alloc = testing.allocator;
    const index_diffs = try alloc.dupe(diff_types.IndexDiff, &.{
        .{
            .name = "idx_email",
            .action = .add,
            .old_idx = null,
            .new_idx = .{
                .name = "idx_email",
                .kind = .regular,
                .fields = &.{"email"},
                .descending = &.{false},
                .line_no = 0,
            },
        },
    });
    defer alloc.free(index_diffs);

    const table_diffs = try alloc.dupe(diff_types.TableDiff, &.{
        .{
            .name = "users",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = index_diffs,
            .fk_diffs = &.{},
            .metadata_diff = null,
        },
    });
    defer alloc.free(table_diffs);

    const sd = diff_types.SchemaDiff{
        .table_diffs = table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try migrate.filterIncrementalChanges(alloc, sd);
    defer alloc.free(result.table_diffs);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
}

test "filterIncrementalChanges: keeps FK changes" {
    const alloc = testing.allocator;
    const fk_diffs = try alloc.dupe(diff_types.FkDiff, &.{
        .{
            .action = .add,
            .old_fk = null,
            .new_fk = .{
                .fields = &.{"user_id"},
                .ref_table = "users",
                .ref_fields = &.{"id"},
                .actions = &.{},
                .line_no = 0,
            },
        },
    });
    defer alloc.free(fk_diffs);

    const table_diffs = try alloc.dupe(diff_types.TableDiff, &.{
        .{
            .name = "orders",
            .action = .alter,
            .field_diffs = &.{},
            .index_diffs = &.{},
            .fk_diffs = fk_diffs,
        },
    });
    defer alloc.free(table_diffs);

    const sd = diff_types.SchemaDiff{
        .table_diffs = table_diffs,
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .custom_type_diffs = &.{},
    };

    const result = try migrate.filterIncrementalChanges(alloc, sd);
    defer alloc.free(result.table_diffs);
    try testing.expectEqual(@as(usize, 1), result.table_diffs.len);
}

test "filterIncrementalChanges: empty diff stays empty" {
    const alloc = testing.allocator;
    const result = try migrate.filterIncrementalChanges(alloc, emptySchemaDiff());
    try testing.expectEqual(@as(usize, 0), result.table_diffs.len);
}

// ─── MigrateConfig Tests ─────────────────────────────────────

test "MigrateConfig: default values" {
    const cfg = migrate.MigrateConfig{
        .old_path = "old.ss",
        .new_path = "new.ss",
    };
    try testing.expectEqual(@import("../dialect/enum.zig").Dialect.mysql, cfg.dialect);
    try testing.expectEqual(@import("../types/enums.zig").DiffFormat.text, cfg.format);
    try testing.expect(cfg.output_path == null);
    try testing.expect(!cfg.trace);
    try testing.expect(!cfg.stats);
    try testing.expect(!cfg.rollback);
    try testing.expect(!cfg.dry_run);
    try testing.expect(!cfg.check);
    try testing.expect(!cfg.incremental);
    try testing.expect(!cfg.summary);
    try testing.expect(cfg.auto_lint);
}

test "MigrateConfig: custom values" {
    const cfg = migrate.MigrateConfig{
        .old_path = "old.ss",
        .new_path = "new.ss",
        .dialect = .pg,
        .format = .json,
        .output_path = "out.sql",
        .trace = true,
        .stats = true,
        .rollback = true,
        .dry_run = true,
        .check = true,
        .incremental = true,
        .summary = true,
        .auto_lint = false,
    };
    try testing.expectEqual(@import("../dialect/enum.zig").Dialect.pg, cfg.dialect);
    try testing.expectEqual(@import("../types/enums.zig").DiffFormat.json, cfg.format);
    try testing.expect(cfg.output_path != null);
    try testing.expect(cfg.trace);
    try testing.expect(cfg.stats);
    try testing.expect(cfg.rollback);
    try testing.expect(cfg.dry_run);
    try testing.expect(cfg.check);
    try testing.expect(cfg.incremental);
    try testing.expect(cfg.summary);
    try testing.expect(!cfg.auto_lint);
}
