const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const diff_types = @import("../diff/types.zig");
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
pub const IndexDiff = diff_types.IndexDiff;
pub const IndexAction = diff_types.IndexAction;
pub const FieldDiff = diff_types.FieldDiff;

pub fn diffIndexes(alloc: std.mem.Allocator, old_idxs: []const IndexDecl, new_idxs: []const IndexDecl, field_diffs: []const FieldDiff) ![]const IndexDiff {
    var diffs = try std.ArrayList(IndexDiff).initCapacity(alloc, 4);

    var old_matched = try std.ArrayList(bool).initCapacity(alloc, old_idxs.len);
    defer old_matched.deinit(alloc);
    for (old_idxs) |_| try old_matched.append(alloc, false);
    var new_matched = try std.ArrayList(bool).initCapacity(alloc, new_idxs.len);
    defer new_matched.deinit(alloc);
    for (new_idxs) |_| try new_matched.append(alloc, false);

    // Pass 1: exact match (same structure + same fields) → unchanged
    for (old_idxs, 0..) |old_idx, oi| {
        for (new_idxs, 0..) |new_idx, ni| {
            if (!new_matched.items[ni] and indexesEqual(old_idx, new_idx)) {
                old_matched.items[oi] = true;
                new_matched.items[ni] = true;
                break;
            }
        }
    }

    // Pass 1.5: rename-aware matching — adjust index fields for renames, then match
    for (old_idxs, 0..) |old_idx, oi| {
        if (old_matched.items[oi]) continue;
        const adjusted = adjustIndexForRenames(old_idx, field_diffs, alloc);
        defer if (adjusted.fields_buf.len > 0) alloc.free(adjusted.fields_buf);
        for (new_idxs, 0..) |new_idx, ni| {
            if (!new_matched.items[ni]) {
                if (indexesEqual(adjusted.idx, new_idx)) {
                    old_matched.items[oi] = true;
                    new_matched.items[ni] = true;
                    try diffs.append(alloc, .{
                        .name = old_idx.name,
                        .action = .modify,
                        .old_idx = old_idx,
                        .new_idx = new_idx,
                    });
                    break;
                }
            }
        }
    }

    // Pass 2: remaining unmatched old indexes → check if new has same-name index
    for (old_idxs, 0..) |old_idx, oi| {
        if (old_matched.items[oi]) continue;
        var found = false;
        for (new_idxs, 0..) |new_idx, ni| {
            if (!new_matched.items[ni] and std.mem.eql(u8, old_idx.name, new_idx.name)) {
                old_matched.items[oi] = true;
                new_matched.items[ni] = true;
                try diffs.append(alloc, .{
                    .name = old_idx.name,
                    .action = .modify,
                    .old_idx = old_idx,
                    .new_idx = new_idx,
                });
                found = true;
                break;
            }
        }
        if (!found) {
            try diffs.append(alloc, .{
                .name = old_idx.name,
                .action = .drop,
                .old_idx = old_idx,
                .new_idx = null,
            });
        }
    }

    // Remaining unmatched new indexes → add
    for (new_idxs, 0..) |new_idx, ni| {
        if (!new_matched.items[ni]) {
            try diffs.append(alloc, .{
                .name = new_idx.name,
                .action = .add,
                .old_idx = null,
                .new_idx = new_idx,
            });
        }
    }

    const result = try alloc.dupe(IndexDiff, diffs.items);
    diffs.clearAndFree(alloc);
    return result;
}

/// Create add-diffs for all indexes of a new table.
pub fn createAllIndexDiffs(alloc: std.mem.Allocator, new_idxs: []const IndexDecl) ![]const IndexDiff {
    var diffs = try std.ArrayList(IndexDiff).initCapacity(alloc, new_idxs.len);
    for (new_idxs) |idx| {
        try diffs.append(alloc, .{
            .name = idx.name,
            .action = .add,
            .old_idx = null,
            .new_idx = idx,
        });
    }
    const result = try alloc.dupe(IndexDiff, diffs.items);
    diffs.clearAndFree(alloc);
    return result;
}

pub fn indexesEqual(a: IndexDecl, b: IndexDecl) bool {
    if (a.kind != b.kind) return false;
    if (a.fields.len != b.fields.len) return false;
    if (a.descending.len != b.descending.len) return false;
    for (a.fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f, b.fields[i])) return false;
    }
    for (a.descending, 0..) |d, i| {
        if (d != b.descending[i]) return false;
    }
    return true;
}

// ─── Rename-Aware Index Matching ──────────────────────────────

const AdjustedIndex = struct {
    idx: IndexDecl,
    fields_buf: []const []const u8,

    pub fn deinit(self: AdjustedIndex, alloc: std.mem.Allocator) void {
        if (self.fields_buf.len > 0) alloc.free(self.fields_buf);
    }
};

/// Create a copy of an IndexDecl with fields adjusted according to field renames.
fn adjustIndexForRenames(idx: IndexDecl, field_diffs: []const FieldDiff, alloc: std.mem.Allocator) AdjustedIndex {
    var modified = false;

    for (field_diffs) |fd| {
        if (fd.action != .rename) continue;
        const old_name = fd.rename_from orelse continue;

        for (idx.fields) |f| {
            if (std.mem.eql(u8, f, old_name)) modified = true;
        }
    }

    if (!modified) return .{
        .idx = idx,
        .fields_buf = &.{},
    };

    var fields_buf = alloc.alloc([]const u8, idx.fields.len) catch return .{ .idx = idx, .fields_buf = &.{} };

    for (idx.fields, 0..) |f, i| {
        var replaced = f;
        for (field_diffs) |fd| {
            if (fd.action == .rename and fd.rename_from != null and std.mem.eql(u8, f, fd.rename_from.?)) {
                replaced = fd.name;
                break;
            }
        }
        fields_buf[i] = replaced;
    }

    return .{
        .idx = .{
            .kind = idx.kind,
            .name = idx.name,
            .fields = fields_buf,
            .descending = idx.descending,
            .line_no = idx.line_no,
            .loc = idx.loc,
        },
        .fields_buf = fields_buf,
    };
}
