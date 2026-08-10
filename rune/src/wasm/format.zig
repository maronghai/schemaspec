const std = @import("std");
const formatter = @import("../formatter.zig");
const tune_mod = @import("../tune.zig");
const common = @import("common.zig");

// ─── WASM Format Exports ────────────────────────────────────────
// Formatting and template extraction functions.

/// Format a Rune .ss schema with consistent style.
/// Returns formatted .ss text. No options needed (formatter is dialect-agnostic).
pub export fn rune_format(schema_ptr: [*]const u8, schema_len: usize, _: [*]const u8, _: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];

    common.clearError();

    const output = formatter.format(alloc, schema) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

/// Auto-extract common fields into templates (tune).
/// Returns .ss text with extracted template definitions.
pub export fn rune_tune(schema_ptr: [*]const u8, schema_len: usize, _: [*]const u8, _: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];

    common.clearError();

    const output = tune_mod.tune(alloc, schema) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_format basic" {
    const schema = "# users\nid n pk\nname s\n";
    const result = rune_format(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    if (result) |r| {
        const formatted = std.mem.span(r);
        try std.testing.expect(formatted.len > 0);
        // Should be formatted with indentation
        try std.testing.expect(std.mem.indexOf(u8, formatted, "  id") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_format already formatted" {
    const schema = "# users\n  id n pk\n  name s\n";
    const result = rune_format(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}

test "rune_tune extracts templates" {
    const schema = "# user\nid p\nname s\nemail s\n\n# post\nid p\nname s\nemail s\ntitle s\n";
    const result = rune_tune(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    if (result) |r| {
        const tuned = std.mem.span(r);
        try std.testing.expect(std.mem.indexOf(u8, tuned, "% base") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_tune single table returns original" {
    const schema = "# user\nid p\nname s\n";
    const result = rune_tune(schema.ptr, schema.len, "", 0);
    try std.testing.expect(result != null);
    @import("error.zig").rune_reset();
}
