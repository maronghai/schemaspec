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

/// Category of generator output.
pub const GeneratorCategory = enum {
    /// Requires TypedAst input (e.g., Prisma, Drizzle, SQL DDL).
    schema,
    /// Standalone output that may not need full schema processing (e.g., JSON Schema, symbol-index).
    standalone,
};

/// A code generator that produces output from a TypedAst.
pub const Generator = struct {
    name: []const u8,
    description: []const u8,
    extension: []const u8,
    category: GeneratorCategory,
    /// Supported dialects. null = dialect-agnostic (works with any dialect).
    dialects: ?[]const []const u8 = null,
    /// Generator version for metadata display.
    version: []const u8 = "1.0",
    /// Generator author for metadata display.
    author: []const u8 = "Rune",
    generate: *const fn (alloc: std.mem.Allocator, typed: typed_ast.TypedAst, dialect: Dialect) anyerror![]const u8,
};

/// Registry of all available generators.
pub const REGISTRY = [_]Generator{
    .{
        .name = "json-schema",
        .description = "JSON Schema (draft-07) from .ss schema",
        .extension = ".json",
        .category = .standalone,
        .dialects = null, // dialect-agnostic
        .generate = @import("generators/json_schema.zig").generate,
    },
    .{
        .name = "sql-ddl",
        .description = "SQL DDL (CREATE TABLE) for the selected dialect",
        .extension = ".sql",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite", "mssql", "oracle", "db2" },
        .generate = @import("generators/sql_ddl.zig").generate,
    },
    .{
        .name = "prisma",
        .description = "Prisma schema from .ss schema",
        .extension = ".prisma",
        .category = .schema,
        .dialects = null, // dialect-agnostic
        .generate = @import("generators/prisma.zig").generate,
    },
    .{
        .name = "docs",
        .description = "Markdown documentation from .ss schema",
        .extension = ".md",
        .category = .schema,
        .dialects = null, // dialect-agnostic
        .generate = @import("generators/docs.zig").generate,
    },
    .{
        .name = "drizzle",
        .description = "Drizzle ORM TypeScript schema from .ss schema",
        .extension = ".ts",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite" },
        .generate = @import("generators/drizzle.zig").generate,
    },
    .{
        .name = "typeorm",
        .description = "TypeORM entity classes from .ss schema",
        .extension = ".ts",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite", "mssql" },
        .generate = @import("generators/typeorm.zig").generate,
    },
    .{
        .name = "sqlalchemy",
        .description = "SQLAlchemy ORM models from .ss schema",
        .extension = ".py",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite" },
        .generate = @import("generators/sqlalchemy.zig").generate,
    },
    .{
        .name = "knex",
        .description = "Knex.js migration files from .ss schema",
        .extension = ".js",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite", "mssql" },
        .generate = @import("generators/knex.zig").generate,
    },
    .{
        .name = "openapi",
        .description = "OpenAPI 3.1 spec from .ss schema",
        .extension = ".json",
        .category = .schema,
        .dialects = &.{ "mysql", "pg", "sqlite", "mssql", "oracle" },
        .generate = @import("generators/openapi.zig").generate,
    },
    .{
        .name = "graphql",
        .description = "GraphQL type definitions from .ss schema",
        .extension = ".graphql",
        .category = .schema,
        .dialects = null, // dialect-agnostic
        .generate = @import("generators/graphql.zig").generate,
    },
    .{
        .name = "symbol-index",
        .description = "JSON symbol index for IDE integration",
        .extension = ".json",
        .category = .standalone,
        .dialects = &.{ "mysql", "pg", "sqlite", "mssql", "oracle", "db2" },
        .generate = @import("generators/symbol_index.zig").generate,
    },
};

/// Look up a generator by name. Returns null if not found.
pub fn get(name: []const u8) ?Generator {
    for (REGISTRY) |gen| {
        if (std.mem.eql(u8, gen.name, name)) return gen;
    }
    return null;
}

/// Print all available generators to the given writer.
pub fn listAll(writer: anytype) !void {
    try writer.print("Available generators:\n", .{});
    for (REGISTRY) |gen| {
        try writer.print("  {s:<16} {s}\n", .{ gen.name, gen.description });
    }
}

/// Shared helper: write detailed generator info to any writer.
fn writeDetailedInfo(writer: anytype) !void {
    try writer.print("Available generators:\n\n", .{});
    for (REGISTRY) |gen| {
        try writer.print("  {s:<16} {s}\n", .{ gen.name, gen.description });
        try writer.print("    Extension:  {s}\n", .{gen.extension});
        try writer.print("    Category:   {s}\n", .{@tagName(gen.category)});
        try writer.print("    Version:    {s}\n", .{gen.version});
        try writer.print("    Author:     {s}\n", .{gen.author});
        if (gen.dialects) |dialects| {
            try writer.print("    Dialects:   ", .{});
            for (dialects, 0..) |d, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{d});
            }
            try writer.print("\n", .{});
        } else {
            try writer.print("    Dialects:   all (agnostic)\n", .{});
        }
        try writer.print("\n", .{});
    }
}

/// Print detailed generator information to any writer (fallible).
pub fn listDetailedTo(writer: anytype) !void {
    try writeDetailedInfo(writer);
}

/// Print detailed generator information to stderr.
/// Delegates to writeDetailedInfo via an allocating buffer.
pub fn listDetailedStderr() void {
    var buf = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer buf.deinit();
    writeDetailedInfo(&buf.writer) catch return;
    std.debug.print("{s}", .{buf.toOwnedSlice() catch return});
}

/// Health check: verify all generators can produce output for a minimal schema.
/// Returns null on success, error message on failure.
pub fn check(alloc: std.mem.Allocator) ?[]const u8 {
    // Create a minimal typed_ast for testing
    const test_ast = typed_ast.TypedAst{
        .schema_name = "test",
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    for (REGISTRY) |gen| {
        const result = gen.generate(alloc, test_ast, .mysql) catch |err| {
            return @errorName(err);
        };
        alloc.free(result);
    }
    return null;
}

// ─── Tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "Generator: all entries have version and author" {
    for (REGISTRY) |gen| {
        try testing.expect(gen.version.len > 0);
        try testing.expect(gen.author.len > 0);
    }
}

test "Generator: get returns null for unknown name" {
    try testing.expect(get("nonexistent") == null);
}

test "Generator: get returns correct generator" {
    const gen = get("json-schema");
    try testing.expect(gen != null);
    try testing.expectEqualStrings("json-schema", gen.?.name);
    try testing.expectEqualStrings("1.0", gen.?.version);
}

test "Generator: all entries have valid category" {
    for (REGISTRY) |gen| {
        const cat = gen.category;
        try testing.expect(cat == .schema or cat == .standalone);
    }
}
