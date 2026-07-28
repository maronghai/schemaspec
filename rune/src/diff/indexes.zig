const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const diff_types = @import("../diff/types.zig");
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
pub const IndexDiff = diff_types.IndexDiff;
pub const IndexAction = diff_types.IndexAction;

pub fn diffIndexes(alloc: std.mem.Allocator, old_idxs: []const IndexDecl, new_idxs: []const IndexDecl) ![]const IndexDiff {
    var diffs = try std.ArrayList(IndexDiff).initCapacity(alloc, 4);

    var old_by_name = std.StringHashMap(usize).init(alloc);
    defer old_by_name.deinit();
    for (old_idxs, 0..) |idx, i| try old_by_name.put(idx.name, i);
    var new_by_name = std.StringHashMap(usize).init(alloc);
    defer new_by_name.deinit();
    for (new_idxs, 0..) |idx, i| try new_by_name.put(idx.name, i);

    for (old_idxs) |old_idx| {
        if (new_by_name.get(old_idx.name)) |new_i| {
            const new_idx = new_idxs[new_i];
            if (!indexesEqual(old_idx, new_idx)) {
                try diffs.append(alloc, .{
                    .name = old_idx.name,
                    .action = .modify,
                    .old_idx = old_idx,
                    .new_idx = new_idx,
                });
            }
        } else {
            try diffs.append(alloc, .{
                .name = old_idx.name,
                .action = .drop,
                .old_idx = old_idx,
                .new_idx = null,
            });
        }
    }

    for (new_idxs) |new_idx| {
        if (!old_by_name.contains(new_idx.name)) {
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
