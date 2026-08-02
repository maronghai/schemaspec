const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const semantic = @import("semantic.zig");
const TypeInfo = ast_mod.TypeInfo;
const Dialect = dialect_enum.Dialect;

const testing = std.testing;

test "typeInfoEquiv: identical types" {
    try testing.expect(semantic.typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "n" }));
    try testing.expect(semantic.typeInfoEquiv(.{ .simple = "s" }, .{ .simple = "s" }));
    try testing.expect(semantic.typeInfoEquiv(.none, .none));
}

test "typeInfoEquiv: n/N NOT equivalent (int vs bigint)" {
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "N" }));
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "N" }, .{ .simple = "n" }));
}

test "typeInfoEquiv: 4/N4 equivalent" {
    try testing.expect(semantic.typeInfoEquiv(.{ .simple = "4" }, .{ .simple = "N4" }));
}

test "typeInfoEquiv: 8/N8 equivalent" {
    try testing.expect(semantic.typeInfoEquiv(.{ .simple = "8" }, .{ .simple = "N8" }));
}

test "typeInfoEquiv: b/B NOT equivalent (boolean vs blob)" {
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "b" }, .{ .simple = "B" }));
}

test "typeInfoEquiv: different types not equivalent" {
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "s" }));
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "4" }));
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "s" }, .{ .simple = "t" }));
}

test "typeInfoEquiv: explicit types" {
    try testing.expect(semantic.typeInfoEquiv(.{ .varchar_explicit = 255 }, .{ .varchar_explicit = 255 }));
    try testing.expect(!semantic.typeInfoEquiv(.{ .varchar_explicit = 255 }, .{ .varchar_explicit = 128 }));
    try testing.expect(semantic.typeInfoEquiv(.{ .int_explicit = 11 }, .{ .int_explicit = 11 }));
}

test "typeInfoEquiv: cross-tag not equivalent" {
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "n" }, .none));
    try testing.expect(!semantic.typeInfoEquiv(.{ .simple = "n" }, .{ .varchar_explicit = 255 }));
}

// ─── semanticEquiv tests ─────────────────────────────────────

test "semanticEquiv: MySQL int ↔ PG integer → true" {
    try testing.expect(semantic.semanticEquiv("int", "id", .mysql, "integer", "id", .pg));
}

test "semanticEquiv: MySQL int ↔ PG bigint → false" {
    try testing.expect(!semantic.semanticEquiv("int", "id", .mysql, "bigint", "id", .pg));
}

test "semanticEquiv: MySQL datetime ↔ PG timestamp → true" {
    try testing.expect(semantic.semanticEquiv("datetime", "created_at", .mysql, "timestamp", "created_at", .pg));
}

test "semanticEquiv: MySQL blob ↔ PG bytea → true" {
    try testing.expect(semantic.semanticEquiv("blob", "data", .mysql, "bytea", "data", .pg));
}

test "semanticEquiv: MySQL boolean ↔ PG boolean → true (same name)" {
    try testing.expect(semantic.semanticEquiv("boolean", "flag", .mysql, "boolean", "flag", .pg));
}

test "semanticEquiv: MySQL tinyint ↔ PG smallint → false (n vs i)" {
    try testing.expect(!semantic.semanticEquiv("tinyint", "age", .mysql, "smallint", "age", .pg));
}

test "semanticEquiv: MySQL text ↔ PG text → true" {
    try testing.expect(semantic.semanticEquiv("text", "bio", .mysql, "text", "bio", .pg));
}

test "semanticEquiv: MySQL int ↔ SQLite INTEGER → true" {
    try testing.expect(semantic.semanticEquiv("int", "id", .mysql, "INTEGER", "id", .sqlite));
}

test "semanticEquiv: MySQL varchar(255) ↔ PG varchar → true (both → s)" {
    try testing.expect(semantic.semanticEquiv("varchar(255)", "name", .mysql, "varchar", "name", .pg));
}
