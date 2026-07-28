const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const diff_types = @import("../diff/types.zig");
const FkDecl = ast_mod.FkDecl;
pub const FkDiff = diff_types.FkDiff;
pub const FkAction = diff_types.FkAction;
pub const FieldDiff = diff_types.FieldDiff;

pub fn diffFks(alloc: std.mem.Allocator, old_fks: []const FkDecl, new_fks: []const FkDecl, field_diffs: []const FieldDiff) ![]const FkDiff {
    var diffs = try std.ArrayList(FkDiff).initCapacity(alloc, 4);

    var old_matched = try std.ArrayList(bool).initCapacity(alloc, old_fks.len);
    defer old_matched.deinit(alloc);
    for (old_fks) |_| try old_matched.append(alloc, false);
    var new_matched = try std.ArrayList(bool).initCapacity(alloc, new_fks.len);
    defer new_matched.deinit(alloc);
    for (new_fks) |_| try new_matched.append(alloc, false);

    // Pass 1: exact match (same structure + same actions) → unchanged
    for (old_fks, 0..) |old_fk, oi| {
        for (new_fks, 0..) |new_fk, ni| {
            if (!new_matched.items[ni] and fksEqual(old_fk, new_fk)) {
                old_matched.items[oi] = true;
                new_matched.items[ni] = true;
                break;
            }
        }
    }

    // Pass 1.5: rename-aware matching — adjust FK fields for renames, then match
    for (old_fks, 0..) |old_fk, oi| {
        if (old_matched.items[oi]) continue;
        const adjusted_result = try adjustFkForRenames(old_fk, field_diffs, alloc);
        defer adjusted_result.deinit(alloc);
        for (new_fks, 0..) |new_fk, ni| {
            if (!new_matched.items[ni]) {
                if (fksStructurallyEqual(adjusted_result.fk, new_fk)) {
                    old_matched.items[oi] = true;
                    new_matched.items[ni] = true;
                    try diffs.append(alloc, .{
                        .action = .modify,
                        .old_fk = old_fk,
                        .new_fk = new_fk,
                    });
                    break;
                }
            }
        }
    }

    // Pass 2: structural match (same structure, different actions) → modify
    for (old_fks, 0..) |old_fk, oi| {
        if (old_matched.items[oi]) continue;
        for (new_fks, 0..) |new_fk, ni| {
            if (!new_matched.items[ni] and fksStructurallyEqual(old_fk, new_fk)) {
                old_matched.items[oi] = true;
                new_matched.items[ni] = true;
                try diffs.append(alloc, .{
                    .action = .modify,
                    .old_fk = old_fk,
                    .new_fk = new_fk,
                });
                break;
            }
        }
    }

    // Remaining unmatched old FKs → drop
    for (old_fks, 0..) |old_fk, oi| {
        if (!old_matched.items[oi]) {
            try diffs.append(alloc, .{
                .action = .drop,
                .old_fk = old_fk,
                .new_fk = null,
            });
        }
    }

    // Remaining unmatched new FKs → add
    for (new_fks, 0..) |new_fk, ni| {
        if (!new_matched.items[ni]) {
            try diffs.append(alloc, .{
                .action = .add,
                .old_fk = null,
                .new_fk = new_fk,
            });
        }
    }

    const result = try alloc.dupe(FkDiff, diffs.items);
    diffs.deinit(alloc);
    return result;
}

/// Result of adjustFkForRenames — contains the adjusted FK and allocated memory.
/// Caller must free `fields_buf` and `ref_fields_buf` after use.
pub const AdjustedFk = struct {
    fk: FkDecl,
    fields_buf: []const []const u8,
    ref_fields_buf: []const []const u8,

    pub fn deinit(self: AdjustedFk, alloc: std.mem.Allocator) void {
        if (self.fields_buf.len > 0) alloc.free(self.fields_buf);
        if (self.ref_fields_buf.len > 0) alloc.free(self.ref_fields_buf);
    }
};

/// Create a copy of an FK with fields adjusted according to field renames.
/// Returns the adjusted FK and allocated buffers that the caller must free.
fn adjustFkForRenames(fk: FkDecl, field_diffs: []const FieldDiff, alloc: std.mem.Allocator) !AdjustedFk {
    var modified = false;

    for (field_diffs) |fd| {
        if (fd.action != .rename) continue;
        const old_name = fd.rename_from orelse continue;

        for (fk.fields) |f| {
            if (std.mem.eql(u8, f, old_name)) modified = true;
        }
        for (fk.ref_fields) |f| {
            if (std.mem.eql(u8, f, old_name)) modified = true;
        }
    }

    if (!modified) return .{
        .fk = fk,
        .fields_buf = &.{},
        .ref_fields_buf = &.{},
    };

    // Allocate buffers for renamed fields
    var fields_buf = try alloc.alloc([]const u8, fk.fields.len);
    errdefer alloc.free(fields_buf);
    var ref_fields_buf = try alloc.alloc([]const u8, fk.ref_fields.len);
    errdefer alloc.free(ref_fields_buf);

    for (fk.fields, 0..) |f, i| {
        var replaced = f;
        for (field_diffs) |fd| {
            if (fd.action == .rename and fd.rename_from != null and std.mem.eql(u8, f, fd.rename_from.?)) {
                replaced = fd.name;
                break;
            }
        }
        fields_buf[i] = replaced;
    }
    for (fk.ref_fields, 0..) |f, i| {
        var replaced = f;
        for (field_diffs) |fd| {
            if (fd.action == .rename and fd.rename_from != null and std.mem.eql(u8, f, fd.rename_from.?)) {
                replaced = fd.name;
                break;
            }
        }
        ref_fields_buf[i] = replaced;
    }

    return .{
        .fk = .{
            .fields = fields_buf,
            .ref_table = fk.ref_table,
            .ref_fields = ref_fields_buf,
            .actions = fk.actions,
            .line_no = fk.line_no,
        },
        .fields_buf = fields_buf,
        .ref_fields_buf = ref_fields_buf,
    };
}

/// Create add-diffs for all FKs of a new table.
pub fn createAllFkDiffs(alloc: std.mem.Allocator, new_fks: []const FkDecl) ![]const FkDiff {
    var diffs = try std.ArrayList(FkDiff).initCapacity(alloc, new_fks.len);
    for (new_fks) |fk| {
        try diffs.append(alloc, .{
            .action = .add,
            .old_fk = null,
            .new_fk = fk,
        });
    }
    const result = try alloc.dupe(FkDiff, diffs.items);
    diffs.deinit(alloc);
    return result;
}

pub fn fksEqual(a: FkDecl, b: FkDecl) bool {
    return fksStructurallyEqual(a, b) and fksActionsEqual(a, b);
}

/// Check if two FKs have the same structure (fields, ref_table, ref_fields) — ignores actions.
pub fn fksStructurallyEqual(a: FkDecl, b: FkDecl) bool {
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f, b.fields[i])) return false;
    }
    if (!std.mem.eql(u8, a.ref_table, b.ref_table)) return false;
    if (a.ref_fields.len != b.ref_fields.len) return false;
    for (a.ref_fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f, b.ref_fields[i])) return false;
    }
    return true;
}

/// Check if two FKs have identical actions.
pub fn fksActionsEqual(a: FkDecl, b: FkDecl) bool {
    if (a.actions.len != b.actions.len) return false;
    for (a.actions, 0..) |act, i| {
        if (act.trigger != b.actions[i].trigger or act.action != b.actions[i].action) return false;
    }
    return true;
}

