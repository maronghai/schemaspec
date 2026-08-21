const std = @import("std");
const common = @import("common.zig");

// ─── WASM Error Handling ────────────────────────────────────────
// Error state management for WASM exports.

/// Allocate `len` bytes from the WASM arena for caller use (e.g. writing
/// schema text into module memory before calling a rune_* function).
/// The arena is reclaimed by `rune_reset()`.
pub export fn rune_wasm_alloc(len: usize) ?[*]u8 {
    const alloc = common.gpa.allocator();
    // Zero-length allocations have no valid pointer; hand back one byte so
    // callers can still pass a non-null (empty) buffer.
    const buf = alloc.alloc(u8, @max(len, 1)) catch return null;
    return buf.ptr;
}

/// Free all memory allocated by rune_compile.
pub export fn rune_reset() void {
    common.clearError();
    _ = common.gpa.reset(.retain_capacity);
}

/// Get the last error message from rune_compile.
/// Returns null if no error has occurred since the last successful compile or reset.
pub export fn rune_last_error() ?[*:0]const u8 {
    return common.last_error;
}

/// Get the numeric error code from the last operation.
/// 0 = success, 1 = syntax, 2 = type, 3 = FK, 4 = semantic, 5 = unknown.
pub export fn rune_last_error_code() i32 {
    return common.last_error_code;
}

/// Get the Rune version string.
pub export fn rune_version() ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    return alloc.dupeZ(u8, @import("../version.zig").VERSION) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_version returns version" {
    const ver = rune_version();
    try std.testing.expect(ver != null);
    if (ver) |v| {
        const version_str = std.mem.span(v);
        try std.testing.expect(version_str.len > 0);
    }
    rune_reset();
}

test "rune_last_error after reset" {
    rune_reset();
    try std.testing.expect(rune_last_error() == null);
}

test "rune_last_error_code after reset" {
    rune_reset();
    try std.testing.expectEqual(@as(i32, 0), rune_last_error_code());
}
