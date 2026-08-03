const std = @import("std");
const diff_types = @import("types.zig");

// ─── Shared Rename-Adjustment Logic ─────────────────────────
//
// Adjusts field names in index and FK diffs when a rename has been detected.
// Used by both `indexes.zig` and `fks.zig` to eliminate duplicated logic.

/// Apply field renames from `field_diffs` to `fields`.
/// Returns an allocated slice with old names replaced by new names.
/// Caller must free the returned slice.
pub fn applyRenames(
    alloc: std.mem.Allocator,
    fields: []const []const u8,
    field_diffs: []const diff_types.FieldDiff,
) ![]const []const u8 {
    var result = try std.ArrayList([]const u8).initCapacity(alloc, fields.len);
    errdefer result.deinit(alloc);

    for (fields) |field| {
        var replaced = false;
        for (field_diffs) |fd| {
            if (fd.action == .rename and std.mem.eql(u8, fd.rename_from orelse continue, field)) {
                try result.append(alloc, fd.name);
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            try result.append(alloc, field);
        }
    }
    return try result.toOwnedSlice(alloc);
}
