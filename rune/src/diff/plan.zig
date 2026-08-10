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
        drop_type: DropType,
        create_type: CreateType,
        modify_type: ModifyType,
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

    pub const DropType = struct {
        name: []const u8,
        /// Type definition for rollback inversion (preserves type_def for create_type inversion).
        type_def: ?ast_mod.CustomType = null,
    };

    pub const CreateType = struct {
        name: []const u8,
        type_def: ast_mod.CustomType,
    };

    pub const ModifyType = struct {
        name: []const u8,
        old_type: ast_mod.CustomType,
        new_type: ast_mod.CustomType,
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
    var ops = try std.ArrayList(MigrationPlan.Operation).initCapacity(alloc, d.dropped_tables.len + d.table_diffs.len + d.view_diffs.len + d.custom_type_diffs.len);

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

    // 4. Custom type diffs → drop/create/modify_type operations
    for (d.custom_type_diffs) |ctd| {
        switch (ctd.action) {
            .drop => ops.appendAssumeCapacity(.{ .drop_type = .{ .name = ctd.name, .type_def = ctd.old_type } }),
            .add => {
                if (ctd.new_type) |new_t| {
                    ops.appendAssumeCapacity(.{ .create_type = .{ .name = ctd.name, .type_def = new_t } });
                }
            },
            .modify => {
                if (ctd.old_type) |old_t| {
                    if (ctd.new_type) |new_t| {
                        ops.appendAssumeCapacity(.{ .modify_type = .{ .name = ctd.name, .old_type = old_t, .new_type = new_t } });
                    }
                }
            },
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
            .drop_type => |dt| {
                // When rolling back a drop_type, we need to recreate the type.
                // If type_def is available (from plan generation), use it.
                // Otherwise, create a minimal placeholder (type was not tracked).
                if (dt.type_def) |td| {
                    ops.appendAssumeCapacity(.{ .create_type = .{ .name = dt.name, .type_def = td } });
                } else {
                    ops.appendAssumeCapacity(.{ .create_type = .{ .name = dt.name, .type_def = .{
                        .name = dt.name,
                        .base = .{ .simple = "s" },
                        .dialect_overrides = &.{},
                        .line_no = 0,
                    } } });
                }
            },
            .create_type => |ct| ops.appendAssumeCapacity(.{ .drop_type = .{ .name = ct.name } }),
            .modify_type => |mt| ops.appendAssumeCapacity(.{ .modify_type = .{ .name = mt.name, .old_type = mt.new_type, .new_type = mt.old_type } }),
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
        .custom_type_diffs = &[_]types.CustomTypeDiff{},
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
        .custom_type_diffs = &[_]types.CustomTypeDiff{},
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

test "invertFieldDiff: add → drop" {
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
    const fd = types.FieldDiff{ .name = "email", .action = .add, .old_field = null, .new_field = field, .rename_from = null };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.drop, inv.action);
    try testing.expectEqual(@as(?ast_mod.Field, field), inv.old_field);
    try testing.expectEqual(@as(?ast_mod.Field, null), inv.new_field);
}

test "invertFieldDiff: drop → add" {
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
    const fd = types.FieldDiff{ .name = "email", .action = .drop, .old_field = field, .new_field = null, .rename_from = null };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.add, inv.action);
    try testing.expectEqual(@as(?ast_mod.Field, null), inv.old_field);
    try testing.expectEqual(@as(?ast_mod.Field, field), inv.new_field);
}

test "invertFieldDiff: modify swaps old/new" {
    const old_field = ast_mod.Field{
        .name = "email",
        .type_info = .{ .simple = "s" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
    const new_field = ast_mod.Field{
        .name = "email",
        .type_info = .{ .simple = "s128" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
    const fd = types.FieldDiff{ .name = "email", .action = .modify, .old_field = old_field, .new_field = new_field, .rename_from = null };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.modify, inv.action);
    // After inversion: old=new, new=old
    try testing.expectEqual(@as(?ast_mod.Field, new_field), inv.old_field);
    try testing.expectEqual(@as(?ast_mod.Field, old_field), inv.new_field);
}

test "invertFieldDiff: rename reverses direction" {
    const old_field = ast_mod.Field{
        .name = "userName",
        .type_info = .{ .simple = "s" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
    const new_field = ast_mod.Field{
        .name = "user_name",
        .type_info = .{ .simple = "s" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
    const fd = types.FieldDiff{ .name = "user_name", .action = .rename, .old_field = old_field, .new_field = new_field, .rename_from = "userName" };
    const inv = invertFieldDiff(fd);
    try testing.expectEqual(types.FieldAction.rename, inv.action);
    // After inversion: name reverts to original, rename_from points to new name
    try testing.expectEqualStrings("userName", inv.name);
    try testing.expectEqualStrings("user_name", inv.rename_from.?);
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
        .custom_type_diffs = &[_]types.CustomTypeDiff{},
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

// ─── Custom Type Migration Tests ──────────────────────────────

test "planFromDiff: custom type add" {
    const ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
        .custom_type_diffs = &[_]types.CustomTypeDiff{
            types.CustomTypeDiff{ .name = "status_t", .action = .add, .old_type = null, .new_type = ct },
        },
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);
    try testing.expectEqual(@as(usize, 1), plan.operations.len);
    try testing.expectEqualStrings("status_t", plan.operations[0].create_type.name);
}

test "planFromDiff: custom type drop" {
    const old_ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
        .custom_type_diffs = &[_]types.CustomTypeDiff{
            types.CustomTypeDiff{ .name = "status_t", .action = .drop, .old_type = old_ct, .new_type = null },
        },
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);
    try testing.expectEqual(@as(usize, 1), plan.operations.len);
    try testing.expectEqualStrings("status_t", plan.operations[0].drop_type.name);
    // Verify type_def is preserved for rollback
    try testing.expect(plan.operations[0].drop_type.type_def != null);
    try testing.expectEqualStrings("status_t", plan.operations[0].drop_type.type_def.?.name);
}

test "planFromDiff: custom type modify" {
    const old_ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const new_ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
        .custom_type_diffs = &[_]types.CustomTypeDiff{
            types.CustomTypeDiff{ .name = "status_t", .action = .modify, .old_type = old_ct, .new_type = new_ct },
        },
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);
    try testing.expectEqual(@as(usize, 1), plan.operations.len);
    try testing.expectEqualStrings("status_t", plan.operations[0].modify_type.name);
}

test "invertPlan: custom type operations" {
    const ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
        .custom_type_diffs = &[_]types.CustomTypeDiff{
            types.CustomTypeDiff{ .name = "status_t", .action = .add, .old_type = null, .new_type = ct },
        },
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);

    const inv = try invertPlan(testing.allocator, plan);
    defer testing.allocator.free(inv.operations);
    try testing.expectEqual(@as(usize, 1), inv.operations.len);
    // create_type inverted to drop_type
    try testing.expectEqualStrings("status_t", inv.operations[0].drop_type.name);
}

test "invertPlan: custom type drop preserves type_def" {
    const old_ct = ast_mod.CustomType{
        .name = "status_t",
        .base = .{ .simple = "s" },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
    const d = types.SchemaDiff{
        .table_diffs = &[_]types.TableDiff{},
        .dropped_tables = &[_][]const u8{},
        .view_diffs = &[_]types.ViewDiff{},
        .custom_type_diffs = &[_]types.CustomTypeDiff{
            types.CustomTypeDiff{ .name = "status_t", .action = .drop, .old_type = old_ct, .new_type = null },
        },
    };
    const plan = try planFromDiff(testing.allocator, d);
    defer testing.allocator.free(plan.operations);

    const inv = try invertPlan(testing.allocator, plan);
    defer testing.allocator.free(inv.operations);
    try testing.expectEqual(@as(usize, 1), inv.operations.len);
    // drop_type inverted to create_type with type_def preserved
    try testing.expectEqualStrings("status_t", inv.operations[0].create_type.name);
    try testing.expectEqualStrings("status_t", inv.operations[0].create_type.type_def.name);
    try testing.expectEqualStrings("s", inv.operations[0].create_type.type_def.base.simple);
}
