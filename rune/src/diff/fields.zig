const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const diff_semantic = @import("../diff/semantic.zig");
const diff_types = @import("../diff/types.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Field = ast_mod.Field;
const TypeInfo = ast_mod.TypeInfo;
const DefaultVal = ast_mod.DefaultVal;
const CheckConstraint = ast_mod.CheckConstraint;
const Dialect = dialect_enum.Dialect;
pub const FieldDiff = diff_types.FieldDiff;
pub const FieldAction = diff_types.FieldAction;

// ─── Field Diff + Rename Detection ─────────────────────────
// Extracted from diff.zig for single-responsibility.

// ─── Capacity Constants ────────────────────────────────────
// Initial ArrayList capacities based on typical table patterns.
// Most tables have 5-20 fields; few changes per migration.

/// Typical number of field diffs per table (5-10 common).
const INITIAL_FIELD_DIFF_CAPACITY = 8;
/// Typical number of dropped fields per table (0-3 common).
const INITIAL_DROPPED_NAMES_CAPACITY = 4;
/// Typical number of added fields per table (0-3 common).
const INITIAL_ADDED_FIELDS_CAPACITY = 4;

pub const RenamePair = struct {
    old_name: []const u8,
    new_name: []const u8,
    old_field: ?Field,
    new_field: ?Field,
};

/// Compute field-level diffs between two tables, including rename detection.
pub fn diffFields(
    alloc: std.mem.Allocator,
    old_fields: []const Field,
    new_fields: []const Field,
) ![]const FieldDiff {
    // Build name→field maps (skip slot markers)
    var old_fmap = std.StringHashMap(usize).init(alloc);
    defer old_fmap.deinit();
    for (old_fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f.name, "..."))
            try old_fmap.put(f.name, i);
    }
    var new_fmap = std.StringHashMap(usize).init(alloc);
    defer new_fmap.deinit();
    for (new_fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f.name, "..."))
            try new_fmap.put(f.name, i);
    }

    var diffs = try std.ArrayList(FieldDiff).initCapacity(alloc, INITIAL_FIELD_DIFF_CAPACITY);
    var dropped_names = try std.ArrayList([]const u8).initCapacity(alloc, INITIAL_DROPPED_NAMES_CAPACITY);
    defer dropped_names.deinit(alloc);
    var added_fields = try std.ArrayList(Field).initCapacity(alloc, INITIAL_ADDED_FIELDS_CAPACITY);
    defer added_fields.deinit(alloc);

    // Fields in both → compare
    for (old_fields) |old_field| {
        if (std.mem.eql(u8, old_field.name, "...")) continue;
        if (new_fmap.get(old_field.name)) |new_idx| {
            const new_field = new_fields[new_idx];
            if (!fieldsEqual(old_field, new_field)) {
                try diffs.append(alloc, .{
                    .name = old_field.name,
                    .action = .modify,
                    .old_field = old_field,
                    .new_field = new_field,
                    .rename_from = null,
                });
            }
        } else {
            try dropped_names.append(alloc, old_field.name);
        }
    }

    // Fields in new but not old → add or rename target
    for (new_fields) |new_field| {
        if (std.mem.eql(u8, new_field.name, "...")) continue;
        if (!old_fmap.contains(new_field.name)) {
            try added_fields.append(alloc, new_field);
        }
    }

    // Rename detection: match dropped ↔ added by (type_info, modifiers, default, check)
    const renames = try detectRenames(old_fmap, new_fmap, old_fields, new_fields, &dropped_names, alloc);

    // Emit add for unmatched added fields
    for (added_fields.items) |af| {
        var was_renamed = false;
        for (renames) |r| {
            if (std.mem.eql(u8, r.new_name, af.name)) {
                was_renamed = true;
                break;
            }
        }
        if (!was_renamed) {
            try diffs.append(alloc, .{
                .name = af.name,
                .action = .add,
                .old_field = null,
                .new_field = af,
                .rename_from = null,
            });
        }
    }

    // Emit rename entries
    for (renames) |r| {
        try diffs.append(alloc, .{
            .name = r.new_name,
            .action = .rename,
            .old_field = r.old_field,
            .new_field = r.new_field,
            .rename_from = r.old_name,
        });
    }

    // Emit drop for unmatched dropped fields
    for (dropped_names.items) |dfn| {
        var was_renamed = false;
        for (renames) |r| {
            if (std.mem.eql(u8, r.old_name, dfn)) {
                was_renamed = true;
                break;
            }
        }
        if (!was_renamed) {
            const old_field = if (old_fmap.get(dfn)) |idx| old_fields[idx] else null;
            try diffs.append(alloc, .{
                .name = dfn,
                .action = .drop,
                .old_field = old_field,
                .new_field = null,
                .rename_from = null,
            });
        }
    }

    const result = try alloc.dupe(FieldDiff, diffs.items);
    diffs.deinit(alloc);
    return result;
}

/// Create add-diffs for all fields of a new table.
pub fn createAllFieldDiffs(alloc: std.mem.Allocator, new_fields: []const Field) ![]const FieldDiff {
    var diffs = try std.ArrayList(FieldDiff).initCapacity(alloc, new_fields.len);
    for (new_fields) |f| {
        if (std.mem.eql(u8, f.name, "...")) continue;
        try diffs.append(alloc, .{
            .name = f.name,
            .action = .add,
            .old_field = null,
            .new_field = f,
            .rename_from = null,
        });
    }
    const result = try alloc.dupe(FieldDiff, diffs.items);
    diffs.deinit(alloc);
    return result;
}

// ─── Rename Detection ──────────────────────────────────────

fn detectRenames(
    old_fmap: std.StringHashMap(usize),
    new_fmap: std.StringHashMap(usize),
    old_fields: []const Field,
    new_fields: []const Field,
    dropped_names: *const std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
) ![]const RenamePair {
    var renames = try std.ArrayList(RenamePair).initCapacity(alloc, 4);

    for (dropped_names.items) |old_name| {
        const old_idx = old_fmap.get(old_name) orelse continue;
        const old_f = old_fields[old_idx];

        var match_name: ?[]const u8 = null;
        var match_count: usize = 0;

        for (new_fields) |new_f| {
            if (std.mem.eql(u8, new_f.name, "...")) continue;
            // Skip fields that exist in both old and new (not a rename candidate)
            if (old_fmap.contains(new_f.name)) continue;

            if (fieldSignatureMatch(old_f, new_f)) {
                match_name = new_f.name;
                match_count += 1;
            }
        }

        if (match_count == 1 and match_name != null) {
            const new_name = match_name.?;
            const new_idx = new_fmap.get(new_name) orelse continue;
            try renames.append(alloc, .{
                .old_name = old_name,
                .new_name = new_name,
                .old_field = old_f,
                .new_field = new_fields[new_idx],
            });
        }
    }

    const result = try alloc.dupe(RenamePair, renames.items);
    renames.deinit(alloc);
    return result;
}

// ─── Equality Helpers ──────────────────────────────────────

/// Check if two fields have the same signature (type, modifiers, default, check).
/// Used by rename detection to match dropped ↔ added fields.
pub fn fieldSignatureMatch(a: Field, b: Field) bool {
    if (!typeInfoEqualDialect(a.type_info, b.type_info)) return false;
    if (a.modifiers.len != b.modifiers.len) return false;
    for (a.modifiers, 0..) |am, i| {
        if (am.kind != b.modifiers[i].kind) return false;
    }
    if (!defaultValEqual(a.default_val, b.default_val)) return false;
    if (!checkEqual(a.check, b.check)) return false;
    return true;
}

/// Check if two fields are fully equal (type, modifiers, default, check).
pub fn fieldsEqual(a: Field, b: Field) bool {
    return fieldSignatureMatch(a, b);
}

pub fn typeInfoEqual(a: TypeInfo, b: TypeInfo) bool {
    return a.eql(b);
}

/// Dialect-aware type info equality: uses semantic equivalence.
pub fn typeInfoEqualDialect(a: TypeInfo, b: TypeInfo) bool {
    return diff_semantic.typeInfoEquiv(a, b);
}

pub fn defaultValEqual(a: ?DefaultVal, b: ?DefaultVal) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?.value, b.?.value);
}

pub fn checkEqual(a: ?CheckConstraint, b: ?CheckConstraint) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.?.kind == b.?.kind and std.mem.eql(u8, a.?.expr, b.?.expr);
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

fn makeTestField(name: []const u8, sym: []const u8) Field {
    return .{
        .name = name,
        .type_info = .{ .simple = sym },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn makeTestFieldWithDefault(name: []const u8, sym: []const u8, default: []const u8) Field {
    return .{
        .name = name,
        .type_info = .{ .simple = sym },
        .modifiers = &.{},
        .default_val = .{ .value = default, .line_no = 1 },
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn makeTestFieldWithCheck(name: []const u8, sym: []const u8, expr: []const u8) Field {
    return .{
        .name = name,
        .type_info = .{ .simple = sym },
        .modifiers = &.{},
        .default_val = null,
        .check = .{ .kind = .comparison, .expr = expr, .line_no = 1 },
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

test "fieldSignatureMatch: identical fields match" {
    const a = makeTestField("id", "n");
    const b = makeTestField("id", "n");
    try testing.expect(fieldSignatureMatch(a, b));
}

test "fieldSignatureMatch: different type does not match" {
    const a = makeTestField("id", "n");
    const b = makeTestField("id", "s");
    try testing.expect(!fieldSignatureMatch(a, b));
}

test "fieldSignatureMatch: different default does not match" {
    const a = makeTestFieldWithDefault("col", "n", "0");
    const b = makeTestFieldWithDefault("col", "n", "1");
    try testing.expect(!fieldSignatureMatch(a, b));
}

test "fieldSignatureMatch: different check does not match" {
    const a = makeTestFieldWithCheck("col", "n", "x > 0");
    const b = makeTestFieldWithCheck("col", "n", "x < 100");
    try testing.expect(!fieldSignatureMatch(a, b));
}

test "fieldSignatureMatch: both null checks match" {
    const a = makeTestField("col", "n");
    const b = makeTestField("col", "n");
    try testing.expect(fieldSignatureMatch(a, b));
}

test "checkEqual: both null" {
    try testing.expect(checkEqual(null, null));
}

test "checkEqual: different expr" {
    const a = CheckConstraint{ .kind = .comparison, .expr = "x > 0", .line_no = 1 };
    const b = CheckConstraint{ .kind = .comparison, .expr = "x < 100", .line_no = 1 };
    try testing.expect(!checkEqual(a, b));
}

test "diffFields: one-to-one rename" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const old_fields = try alloc.alloc(Field, 1);
    old_fields[0] = makeTestField("old_name", "n");
    const new_fields = try alloc.alloc(Field, 1);
    new_fields[0] = makeTestField("new_name", "n");

    const diffs = try diffFields(alloc, old_fields, new_fields);
    try testing.expectEqual(@as(usize, 1), diffs.len);
    try testing.expectEqual(FieldAction.rename, diffs[0].action);
    try testing.expectEqualStrings("new_name", diffs[0].name);
    try testing.expectEqualStrings("old_name", diffs[0].rename_from.?);
}

test "diffFields: ambiguous renames produce no rename" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const old_fields = try alloc.alloc(Field, 2);
    old_fields[0] = makeTestField("a", "n");
    old_fields[1] = makeTestField("b", "n");
    const new_fields = try alloc.alloc(Field, 2);
    new_fields[0] = makeTestField("c", "n");
    new_fields[1] = makeTestField("d", "n");

    const diffs = try diffFields(alloc, old_fields, new_fields);
    // Ambiguous: 2 dropped + 2 added with same signature → 2 drops + 2 adds, no renames
    var renames: usize = 0;
    var adds: usize = 0;
    var drops: usize = 0;
    for (diffs) |d| {
        switch (d.action) {
            .rename => renames += 1,
            .add => adds += 1,
            .drop => drops += 1,
            else => {},
        }
    }
    try testing.expectEqual(@as(usize, 0), renames);
    try testing.expectEqual(@as(usize, 2), adds);
    try testing.expectEqual(@as(usize, 2), drops);
}
