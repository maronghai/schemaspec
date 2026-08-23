const std = @import("std");
const testing = std.testing;
const lsp_protocol = @import("protocol.zig");

// ─── v0.331.0: per-document arena lifetime ─────────────────────

test "diagnostics copied out of a doc arena survive its destruction" {
    // Mirrors compileAndPublishDiagnostics: compile into a scratch arena,
    // dupe the diagnostics into the long-lived arena, destroy the scratch.
    const long_lived = testing.allocator;

    const da = try long_lived.create(std.heap.ArenaAllocator);
    defer long_lived.destroy(da);
    da.* = std.heap.ArenaAllocator.init(long_lived);
    var doc_arena = da.allocator();

    const scratch_diags = try doc_arena.alloc(lsp_protocol.Diagnostic, 1);
    scratch_diags[0] = .{
        .range = .{
            .start = .{ .line = 3, .character = 7 },
            .end = .{ .line = 3, .character = 9 },
        },
        .severity = .error_sev,
        .message = try doc_arena.dupe(u8, "parse error in doc arena"),
    };

    // Copy to the owning allocator, then tear down the document arena.
    const owned = try long_lived.dupe(lsp_protocol.Diagnostic, scratch_diags);
    owned[0].message = try long_lived.dupe(u8, scratch_diags[0].message);
    da.deinit();

    defer {
        long_lived.free(owned[0].message);
        long_lived.free(owned);
    }

    try testing.expectEqualStrings("parse error in doc arena", owned[0].message);
    try testing.expectEqual(@as(u32, 3), owned[0].range.start.line);
}
