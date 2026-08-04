const std = @import("std");
const diff_mod = @import("engine.zig");
const types = @import("types.zig");

// ─── Migration Plan IR ─────────────────────────────────────────
// Explicit intermediate representation between SchemaDiff and SQL generation.
// Decouples diff analysis from SQL emission, enabling:
//   - Migration dry-run inspection
//   - Plan-level validation before SQL generation
//   - Rollback via plan inversion (not diff re-walking)

/// A migration plan: a sequence of operations derived from a SchemaDiff.
pub const MigrationPlan = struct {
    operations: []const Operation,
    header: Header,

    pub const Header = struct {
        comment: []const u8,
        command: []const u8,
    };

    pub const Operation = union(enum) {
        drop_table: DropTable,
        create_table: CreateTable,
        alter_table: AlterTable,
        drop_view: DropView,
        create_view: CreateView,
        modify_view: ModifyView,
    };

    pub const DropTable = struct {
        name: []const u8,
    };

    pub const CreateTable = struct {
        name: []const u8,
    };

    pub const DropView = struct {
        name: []const u8,
    };

    pub const CreateView = struct {
        name: []const u8,
    };

    pub const ModifyView = struct {
        name: []const u8,
    };

    pub const AlterTable = struct {
        name: []const u8,
        field_diffs: []const types.FieldDiff,
        index_diffs: []const types.IndexDiff,
        fk_diffs: []const types.FkDiff,
        metadata_diff: ?types.TableMetadataDiff,
    };
};

// ─── Plan Generation ────────────────────────────────────────────

/// Convert a SchemaDiff into a MigrationPlan.
pub fn planFromDiff(
    alloc: std.mem.Allocator,
    d: types.SchemaDiff,
) !MigrationPlan {
    var ops = try std.ArrayList(MigrationPlan.Operation).initCapacity(alloc, d.dropped_tables.len + d.table_diffs.len + d.view_diffs.len);

    // 1. Dropped tables → drop_table operations
    for (d.dropped_tables) |tname| {
        ops.appendAssumeCapacity(.{ .drop_table = .{ .name = tname } });
    }

    // 2. Table diffs → create_table or alter_table operations
    for (d.table_diffs) |td| {
        switch (td.action) {
            .create => ops.appendAssumeCapacity(.{ .create_table = .{ .name = td.name } }),
            .alter => ops.appendAssumeCapacity(.{ .alter_table = .{
                .name = td.name,
                .field_diffs = td.field_diffs,
                .index_diffs = td.index_diffs,
                .fk_diffs = td.fk_diffs,
                .metadata_diff = td.metadata_diff,
            } }),
        }
    }

    // 3. View diffs → drop/create/modify_view operations
    for (d.view_diffs) |vd| {
        switch (vd.action) {
            .create => ops.appendAssumeCapacity(.{ .create_view = .{ .name = vd.name } }),
            .drop => ops.appendAssumeCapacity(.{ .drop_view = .{ .name = vd.name } }),
            .modify => ops.appendAssumeCapacity(.{ .modify_view = .{ .name = vd.name } }),
        }
    }

    return .{
        .operations = try ops.toOwnedSlice(alloc),
        .header = .{
            .comment = "Migration: schema diff",
            .command = "migrate",
        },
    };
}

// ─── Plan Inversion (for rollback) ──────────────────────────────

/// Invert a migration plan for rollback generation.
/// Operations are transformed: drop↔create, alter field diffs inverted, views reversed.
pub fn invertPlan(
    alloc: std.mem.Allocator,
    plan: MigrationPlan,
) !MigrationPlan {
    var ops = try std.ArrayList(MigrationPlan.Operation).initCapacity(alloc, plan.operations.len);

    // Process in reverse order for proper rollback semantics
    var i = plan.operations.len;
    while (i > 0) {
        i -= 1;
        const op = plan.operations[i];
        switch (op) {
            .drop_table => |dt| ops.appendAssumeCapacity(.{ .create_table = .{ .name = dt.name } }),
            .create_table => |ct| ops.appendAssumeCapacity(.{ .drop_table = .{ .name = ct.name } }),
            .drop_view => |dv| ops.appendAssumeCapacity(.{ .create_view = .{ .name = dv.name } }),
            .create_view => |cv| ops.appendAssumeCapacity(.{ .drop_view = .{ .name = cv.name } }),
            .modify_view => |mv| ops.appendAssumeCapacity(.{ .modify_view = .{ .name = mv.name } }),
            .alter_table => |at| {
                // Invert field diffs
                var inv_fields = try std.ArrayList(types.FieldDiff).initCapacity(alloc, at.field_diffs.len);
                for (at.field_diffs) |fd| {
                    inv_fields.appendAssumeCapacity(invertFieldDiff(fd));
                }
                // Invert index diffs
                var inv_indexes = try std.ArrayList(types.IndexDiff).initCapacity(alloc, at.index_diffs.len);
                for (at.index_diffs) |idx| {
                    inv_indexes.appendAssumeCapacity(invertIndexDiff(idx));
                }
                // Invert FK diffs
                var inv_fks = try std.ArrayList(types.FkDiff).initCapacity(alloc, at.fk_diffs.len);
                for (at.fk_diffs) |fk| {
                    inv_fks.appendAssumeCapacity(invertFkDiff(fk));
                }
                ops.appendAssumeCapacity(.{ .alter_table = .{
                    .name = at.name,
                    .field_diffs = try inv_fields.toOwnedSlice(alloc),
                    .index_diffs = try inv_indexes.toOwnedSlice(alloc),
                    .fk_diffs = try inv_fks.toOwnedSlice(alloc),
                    .metadata_diff = at.metadata_diff,
                } });
            },
        }
    }

    return .{
        .operations = try ops.toOwnedSlice(alloc),
        .header = .{
            .comment = "Rollback: undo migration",
            .command = "migrate --rollback",
        },
    };
}

// ─── Per-item Inversion (mirrors invert.zig) ────────────────────

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
const ast_mod = @import("../types/ast.zig");

test "planFromDiff: empty diff" {
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer {
        testing.allocator.free(plan.operations);
    }
    try testing.expectEqual(@as(usize, 0), plan.operations.len);
    try testing.expectEqualStrings("Migration: schema diff", plan.header.comment);
    try testing.expectEqualStrings("migrate", plan.header.command);
}

test "planFromDiff: drop + create + alter" {
    const field = ast_mod.Field{
        .name = "email",
        .type_info = .{ .simple = "s" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
    const td_create = types.TableDiff{
        .name = "users",
        .action = .create,
        .field_diffs = &[_]types.FieldDiff{},
        .index_diffs = &[_]types.IndexDiff{},
        .fk_diffs = &[_]types.FkDiff{},
    };
    const td_alter = types.TableDiff{
        .name = "posts",
        .action = .alter,
        .field_diffs = &[_]types.FieldDiff{
            types.FieldDiff{ .name = "email", .action = .add, .old_field = null, .new_field = field, .rename_from = null },
        },
        .index_diffs = &[_]types.IndexDiff{},
        .fk_diffs = &[_]types.FkDiff{},
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{ td_create, td_alter },
        .dropped_tables = &[_][]const u8{"logs"},
        .view_diffs = &[_]types.ViewDiff{},
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);
    try testing.expectEqual(@as(usize, 3), plan.operations.len);
    // First: drop_table
    try testing.expectEqualStrings("logs", plan.operations[0].drop_table.name);
    // Second: create_table
    try testing.expectEqualStrings("users", plan.operations[1].create_table.name);
    // Third: alter_table
    try testing.expectEqualStrings("posts", plan.operations[2].alter_table.name);
    try testing.expectEqual(@as(usize, 1), plan.operations[2].alter_table.field_diffs.len);
}

test "invertPlan: roundtrip operations" {
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{
            types.TableDiff{
                .name = "users",
                .action = .create,
                .field_diffs = &[_]types.FieldDiff{},
                .index_diffs = &[_]types.IndexDiff{},
                .fk_diffs = &[_]types.FkDiff{},
            },
        },
        .dropped_tables = &[_][]const u8{"logs"},
        .view_diffs = &[_]types.ViewDiff{},
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);

    const inv = try invertPlan(testing.allocator, plan);
    defer {
        for (inv.operations) |op| {
            switch (op) {
                .alter_table => |at| {
                    // These were heap-allocated by invertPlan
                    testing.allocator.free(at.field_diffs);
                    testing.allocator.free(at.index_diffs);
                    testing.allocator.free(at.fk_diffs);
                },
                else => {},
            }
        }
        testing.allocator.free(inv.operations);
    }
    // Original: drop_table("logs"), create_table("users")
    // Inverted: drop_table("users"), create_table("logs") (reversed order)
    try testing.expectEqual(@as(usize, 2), inv.operations.len);
    try testing.expectEqualStrings("users", inv.operations[0].drop_table.name);
    try testing.expectEqualStrings("logs", inv.operations[1].create_table.name);
    try testing.expectEqualStrings("Rollback: undo migration", inv.header.comment);
    try testing.expectEqualStrings("migrate --rollback", inv.header.command);
}
