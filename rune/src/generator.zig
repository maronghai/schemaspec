const std = @import("std");
const typed_ast = @import("types/typed_ast.zig");
const dialect_enum = @import("dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── Generator Registry ───────────────────────────────────────
// Pluggable generator infrastructure for `rune generate`.
// Follows the DialectBackend pattern: struct with function pointers.
//
// Adding a new generator:
//   1. Create `rune/src/generators/<name>.zig` with a `generate()` function
//   2. Add a Generator entry to REGISTRY below
//   3. That's it — the CLI automatically picks it up

/// A code generator that produces output from a TypedAst.
pub const Generator = struct {
    name: []const u8,
    description: []const u8,
    generate: *const fn (alloc: std.mem.Allocator, typed: typed_ast.TypedAst, dialect: Dialect) anyerror![]const u8,
};

/// Registry of all available generators.
pub const REGISTRY = [_]Generator{
    .{
        .name = "json-schema",
        .description = "JSON Schema (draft-07) from .ss schema",
        .generate = @import("json_schema.zig").generate,
    },
    .{
        .name = "sql-ddl",
        .description = "SQL DDL (CREATE TABLE) for the selected dialect",
        .generate = @import("generators/sql_ddl.zig").generate,
    },
    .{
        .name = "prisma",
        .description = "Prisma schema from .ss schema",
        .generate = @import("generators/prisma.zig").generate,
    },
    .{
        .name = "docs",
        .description = "Markdown documentation from .ss schema",
        .generate = @import("generators/docs.zig").generate,
    },
    .{
        .name = "drizzle",
        .description = "Drizzle ORM TypeScript schema from .ss schema",
        .generate = @import("generators/drizzle.zig").generate,
    },
};

/// Look up a generator by name. Returns null if not found.
pub fn get(name: []const u8) ?Generator {
    for (REGISTRY) |gen| {
        if (std.mem.eql(u8, gen.name, name)) return gen;
    }
    return null;
}

/// Print all available generators to stderr.
pub fn listAll() void {
    std.debug.print("Available generators:\n", .{});
    for (REGISTRY) |gen| {
        std.debug.print("  {s:<16} {s}\n", .{ gen.name, gen.description });
    }
}
