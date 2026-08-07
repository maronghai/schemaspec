const std = @import("std");
const generator = @import("generator.zig");
const REGISTRY = generator.REGISTRY;

test "registry has expected generators" {
    try std.testing.expectEqual(@as(usize, 11), REGISTRY.len);
}

test "get returns known generators" {
    const names = [_][]const u8{
        "json-schema", "sql-ddl", "prisma",  "docs",    "drizzle",      "typeorm",
        "sqlalchemy",  "knex",    "openapi", "graphql", "symbol-index",
    };
    for (names) |name| {
        const gen = generator.get(name);
        try std.testing.expect(gen != null);
        try std.testing.expectEqualStrings(name, gen.?.name);
        try std.testing.expect(gen.?.description.len > 0);
    }
}

test "get returns null for unknown generator" {
    try std.testing.expect(generator.get("nonexistent") == null);
    try std.testing.expect(generator.get("") == null);
}

test "all generators have non-empty names and descriptions" {
    for (REGISTRY) |gen| {
        try std.testing.expect(gen.name.len > 0);
        try std.testing.expect(gen.description.len > 0);
    }
}

test "generator names are unique" {
    for (REGISTRY, 0..) |a, i| {
        for (REGISTRY[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.name, b.name));
        }
    }
}

test "all generators have non-empty extensions" {
    for (REGISTRY) |gen| {
        try std.testing.expect(gen.extension.len > 0);
        try std.testing.expect(gen.extension[0] == '.');
    }
}

test "generator extensions are correct" {
    try std.testing.expectEqualStrings(".json", generator.get("json-schema").?.extension);
    try std.testing.expectEqualStrings(".sql", generator.get("sql-ddl").?.extension);
    try std.testing.expectEqualStrings(".prisma", generator.get("prisma").?.extension);
    try std.testing.expectEqualStrings(".md", generator.get("docs").?.extension);
    try std.testing.expectEqualStrings(".ts", generator.get("drizzle").?.extension);
    try std.testing.expectEqualStrings(".ts", generator.get("typeorm").?.extension);
    try std.testing.expectEqualStrings(".py", generator.get("sqlalchemy").?.extension);
    try std.testing.expectEqualStrings(".js", generator.get("knex").?.extension);
    try std.testing.expectEqualStrings(".json", generator.get("openapi").?.extension);
    try std.testing.expectEqualStrings(".graphql", generator.get("graphql").?.extension);
    try std.testing.expectEqualStrings(".json", generator.get("symbol-index").?.extension);
}
