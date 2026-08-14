const std = @import("std");
const testing = std.testing;
const generator = @import("generator.zig");
const REGISTRY = generator.REGISTRY;

test "registry has expected generators" {
    try testing.expectEqual(@as(usize, 12), REGISTRY.len);
}

test "get returns known generators" {
    const names = [_][]const u8{
        "json-schema", "sql-ddl", "prisma",  "docs",    "drizzle",      "typeorm",
        "sqlalchemy",  "knex",    "openapi", "graphql", "symbol-index", "pydantic",
    };
    for (names) |name| {
        const gen = generator.get(name);
        try testing.expect(gen != null);
        try testing.expectEqualStrings(name, gen.?.name);
        try testing.expect(gen.?.description.len > 0);
    }
}

test "get returns null for unknown generator" {
    try testing.expect(generator.get("nonexistent") == null);
    try testing.expect(generator.get("") == null);
}

test "all generators have non-empty names and descriptions" {
    for (REGISTRY) |gen| {
        try testing.expect(gen.name.len > 0);
        try testing.expect(gen.description.len > 0);
    }
}

test "generator names are unique" {
    for (REGISTRY, 0..) |a, i| {
        for (REGISTRY[i + 1 ..]) |b| {
            try testing.expect(!std.mem.eql(u8, a.name, b.name));
        }
    }
}

test "all generators have non-empty extensions" {
    for (REGISTRY) |gen| {
        try testing.expect(gen.extension.len > 0);
        try testing.expect(gen.extension[0] == '.');
    }
}

test "generator extensions are correct" {
    try testing.expectEqualStrings(".json", generator.get("json-schema").?.extension);
    try testing.expectEqualStrings(".sql", generator.get("sql-ddl").?.extension);
    try testing.expectEqualStrings(".prisma", generator.get("prisma").?.extension);
    try testing.expectEqualStrings(".md", generator.get("docs").?.extension);
    try testing.expectEqualStrings(".ts", generator.get("drizzle").?.extension);
    try testing.expectEqualStrings(".ts", generator.get("typeorm").?.extension);
    try testing.expectEqualStrings(".py", generator.get("sqlalchemy").?.extension);
    try testing.expectEqualStrings(".js", generator.get("knex").?.extension);
    try testing.expectEqualStrings(".json", generator.get("openapi").?.extension);
    try testing.expectEqualStrings(".graphql", generator.get("graphql").?.extension);
    try testing.expectEqualStrings(".json", generator.get("symbol-index").?.extension);
}

// ─── Generator Metadata Tests ──────────────────────────────────

test "all generators have valid category" {
    for (REGISTRY) |gen| {
        try testing.expect(gen.category == .schema or gen.category == .standalone);
    }
}

test "standalone generators are json-schema and symbol-index" {
    var standalone_count: usize = 0;
    for (REGISTRY) |gen| {
        if (gen.category == .standalone) standalone_count += 1;
    }
    try testing.expectEqual(@as(usize, 2), standalone_count);
}

test "dialect-aware generators list correct dialects" {
    const sql_ddl = generator.get("sql-ddl") orelse return error.TestFailed;
    try testing.expect(sql_ddl.dialects != null);
    try testing.expectEqual(@as(usize, 6), sql_ddl.dialects.?.len);

    const json_schema = generator.get("json-schema") orelse return error.TestFailed;
    try testing.expect(json_schema.dialects == null);

    const drizzle = generator.get("drizzle") orelse return error.TestFailed;
    try testing.expect(drizzle.dialects != null);
    try testing.expectEqual(@as(usize, 3), drizzle.dialects.?.len);
}

test "listAll produces output" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try generator.listAll(&aw.writer);
    const output = try aw.toOwnedSlice();
    defer testing.allocator.free(output);
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "Available generators:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "json-schema") != null);
}

test "listDetailed produces rich output" {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try generator.listDetailedTo(&aw.writer);
    const output = try aw.toOwnedSlice();
    defer testing.allocator.free(output);
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "Extension:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Category:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Dialects:") != null);
    // sql-ddl should list all 6 dialects
    try testing.expect(std.mem.indexOf(u8, output, "mysql") != null);
    try testing.expect(std.mem.indexOf(u8, output, "pg") != null);
    // json-schema should show "all (agnostic)"
    try testing.expect(std.mem.indexOf(u8, output, "all (agnostic)") != null);
}

test "check returns null on success" {
    const result = generator.check(testing.allocator);
    try testing.expect(result == null);
}
