const std = @import("std");
const pipeline = @import("../pipeline/forward.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const generator = @import("../generator.zig");
const common = @import("common.zig");

// ─── WASM Generate Exports ──────────────────────────────────────
// Generator functions for ORM, API schema, and documentation output.

/// Generate output using a named generator (prisma, drizzle, openapi, etc.).
/// Options: "generator=<name> dialect=<dialect>".
pub export fn rune_generate(schema_ptr: [*]const u8, schema_len: usize, options_ptr: [*]const u8, options_len: usize) ?[*:0]const u8 {
    const alloc = common.gpa.allocator();
    const schema = schema_ptr[0..schema_len];
    const options = options_ptr[0..options_len];

    common.clearError();

    const dialect = common.parseDialectOption(options);
    const gen_name = common.parseOption(options, "generator") orelse {
        common.storeError(alloc, "missing generator option (e.g. generator=prisma)");
        return null;
    };

    const gen = generator.get(gen_name) orelse {
        common.storeError(alloc, "unknown generator");
        return null;
    };

    // Compile schema
    const result = pipeline.compilePipeline(alloc, schema, .{ .dialect = dialect, .run_semantic = true }) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Resolve types
    const typed = TypeResolver.resolve(alloc, result.resolved, dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    // Generate output
    const output = gen.generate(alloc, typed, dialect) catch |err| {
        common.storeError(alloc, @errorName(err));
        return null;
    };

    return alloc.dupeZ(u8, output) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────

test "rune_generate prisma" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=prisma dialect=pg", 28);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "model") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_generate json-schema" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=json-schema dialect=pg", 32);
    try std.testing.expect(result != null);
    if (result) |r| {
        const output = std.mem.span(r);
        try std.testing.expect(output.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, output, "{") != null);
    }
    @import("error.zig").rune_reset();
}

test "rune_generate unknown generator" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "generator=nonexistent", 21);
    try std.testing.expect(result == null);
    const err = @import("error.zig").rune_last_error();
    try std.testing.expect(err != null);
    @import("error.zig").rune_reset();
}

test "rune_generate missing generator option" {
    const schema = "# users\nid N ++\nname s\n";
    const result = rune_generate(schema.ptr, schema.len, "dialect=pg", 10);
    try std.testing.expect(result == null);
    const err = @import("error.zig").rune_last_error();
    try std.testing.expect(err != null);
    @import("error.zig").rune_reset();
}
