const std = @import("std");
const pipeline_diff = @import("diff.zig");
const pipeline_forward = @import("forward.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");

const testing = std.testing;

// ─── formatMigrationFileName ─────────────────────────────────

test "migration file name: zero-padded 4-digit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const name = try pipeline_diff.formatMigrationFileName(alloc, 1, "add_users");
    try testing.expectEqualStrings("0001_add_users.sql", name);
}

test "migration file name: large sequence number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const name = try pipeline_diff.formatMigrationFileName(alloc, 1234, "create_posts");
    try testing.expectEqualStrings("1234_create_posts.sql", name);
}

test "migration file name: sequence 0" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const name = try pipeline_diff.formatMigrationFileName(alloc, 0, "init");
    try testing.expectEqualStrings("0000_init.sql", name);
}

// ─── filterIncrementalChanges ─────────────────────────────────

test "filter incremental: keeps structural diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A table with field diffs is structural — should be kept
    const sd = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{
            .{
                .name = "users",
                .action = .alter,
                .field_diffs = &.{
                    .{ .name = "email", .action = .add, .old_field = null, .new_field = null, .rename_from = null },
                },
                .index_diffs = &.{},
                .fk_diffs = &.{},
                .metadata_diff = null,
            },
        },
        .custom_type_diffs = &.{},
    };
    const filtered = try pipeline_diff.filterIncrementalChanges(alloc, sd);
    try testing.expectEqual(@as(usize, 1), filtered.table_diffs.len);
}

test "filter incremental: removes metadata-only diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A table with only metadata changes (no structural diffs) — should be filtered out
    const sd = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{
            .{
                .name = "users",
                .action = .alter,
                .field_diffs = &.{},
                .index_diffs = &.{},
                .fk_diffs = &.{},
                .metadata_diff = .{
                    .old_comment = "old",
                    .new_comment = "new",
                    .old_engine = null,
                    .new_engine = null,
                },
            },
        },
        .custom_type_diffs = &.{},
    };
    const filtered = try pipeline_diff.filterIncrementalChanges(alloc, sd);
    try testing.expectEqual(@as(usize, 0), filtered.table_diffs.len);
}

test "filter incremental: keeps create tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A newly created table is structural — should be kept
    const sd = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{
            .{
                .name = "new_table",
                .action = .create,
                .field_diffs = &.{
                    .{ .name = "id", .action = .add, .old_field = null, .new_field = null, .rename_from = null },
                },
                .index_diffs = &.{},
                .fk_diffs = &.{},
                .metadata_diff = null,
            },
        },
        .custom_type_diffs = &.{},
    };
    const filtered = try pipeline_diff.filterIncrementalChanges(alloc, sd);
    try testing.expectEqual(@as(usize, 1), filtered.table_diffs.len);
}

test "filter incremental: keeps table with index changes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A table with only index changes (no field_diffs) — index_diffs count as structural
    const sd = diff_types.SchemaDiff{
        .dropped_tables = &.{},
        .view_diffs = &.{},
        .table_diffs = &.{
            .{
                .name = "users",
                .action = .alter,
                .field_diffs = &.{},
                .index_diffs = &.{
                    .{ .name = "idx_email", .action = .add, .old_idx = null, .new_idx = null },
                },
                .fk_diffs = &.{},
                .metadata_diff = null,
            },
        },
        .custom_type_diffs = &.{},
    };
    const filtered = try pipeline_diff.filterIncrementalChanges(alloc, sd);
    try testing.expectEqual(@as(usize, 1), filtered.table_diffs.len);
}

// ─── DiffConfig defaults ──────────────────────────────────────

test "diff config: default values" {
    const cfg = pipeline_diff.DiffConfig{
        .old_path = "old.ss",
        .new_path = "new.ss",
    };
    try testing.expectEqual(diff_types.TableAction.create, .create); // sanity check types compile
    try testing.expect(cfg.check == false);
    try testing.expect(cfg.summary == false);
    try testing.expect(cfg.trace == false);
}

test "migrate config: default values" {
    const cfg = pipeline_diff.MigrateConfig{
        .old_path = "old.ss",
        .new_path = "new.ss",
    };
    try testing.expect(cfg.rollback == false);
    try testing.expect(cfg.incremental == false);
    try testing.expect(cfg.dry_run == false);
}

// ─── Existing tests ──────────────────────────────────────────

test "diff: identical schemas produce no table diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, ss, .{});
    const new_resolved = try pipeline_forward.compilePipeline(alloc, ss, .{});
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc);
    try testing.expectEqual(@as(usize, 0), schema_diff.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), schema_diff.dropped_tables.len);
}

test "diff: adding a table produces a create action" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\
        \\# post
        \\
        \\id   n++
        \\title s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, old_ss, .{});
    const new_resolved = try pipeline_forward.compilePipeline(alloc, new_ss, .{});
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc);
    try testing.expectEqual(@as(usize, 1), schema_diff.table_diffs.len);
    try testing.expectEqual(diff_types.TableAction.create, schema_diff.table_diffs[0].action);
    try testing.expectEqualStrings("post", schema_diff.table_diffs[0].name);
}

test "diff format json: produces valid JSON structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
        \\
        \\# post
        \\
        \\id   n++
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, old_ss, .{});
    const new_resolved = try pipeline_forward.compilePipeline(alloc, new_ss, .{});
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc);
    const json = try diff_format.formatDiffJson(alloc, schema_diff);

    try testing.expect(std.mem.indexOf(u8, json, "\"dropped_tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"table_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"view_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"custom_type_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\": \"post\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"action\": \"create\"") != null);
}
