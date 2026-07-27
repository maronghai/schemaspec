const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const reverse_map = @import("../reverse/map.zig");
const TypeInfo = ast_mod.TypeInfo;
const Dialect = dialect_enum.Dialect;

// ─── Dialect-Aware Type Equivalence ──────────────────────────
//
// Determines if two TypeInfo values are semantically equivalent
// within a given SQL dialect. Different SS symbols that resolve
// to the same SQL type are considered equivalent.
//
// Example: MySQL "n" and "N" both resolve to int → equivalent.

/// Check if two TypeInfo values are semantically equivalent in a dialect.
pub fn typeInfoEquiv(a: TypeInfo, b: TypeInfo, dialect: Dialect) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .none => true,
        .simple => |s| simpleEquiv(s, b.simple, dialect),
        .raw_sql => |s| std.mem.eql(u8, s, b.raw_sql),
        .int_explicit => |n| n == b.int_explicit,
        .decimal_explicit => |ds| ds.precision == b.decimal_explicit.precision and ds.scale == b.decimal_explicit.scale,
        .varchar_explicit => |n| n == b.varchar_explicit,
        .enum_type => |vals| {
            if (vals.len != b.enum_type.len) return false;
            for (vals, 0..) |v, i| {
                if (!std.mem.eql(u8, v, b.enum_type[i])) return false;
            }
            return true;
        },
    };
}

/// Canonical form of a SS type symbol within a dialect.
/// Equivalent symbols map to the same canonical form.
/// NOTE: n and N are NOT equivalent — they map to int vs bigint.
fn canonicalSimple(sym: []const u8, dialect: Dialect) ?[]const u8 {
    _ = dialect;
    if (sym.len == 0) return null;
    return switch (sym[0]) {
        'n', 'N' => if (sym.len == 1) sym else switch (sym[1]) {
            '4' => "4",
            '8' => "8",
            else => null,
        },
        '4' => "4",
        '8' => "8",
        'd' => "d",
        's' => if (sym.len == 1) "s" else sym,
        't' => "t",
        'b', 'B' => sym, // b (boolean) and B (blob) are different
        'j' => "j",
        'm' => "m",
        'e' => "e",
        else => null,
    };
}

/// Check if two simple SS type symbols are equivalent in a dialect.
fn simpleEquiv(a: []const u8, b: []const u8, dialect: Dialect) bool {
    if (std.mem.eql(u8, a, b)) return true;
    const ca = canonicalSimple(a, dialect) orelse return false;
    const cb = canonicalSimple(b, dialect) orelse return false;
    return std.mem.eql(u8, ca, cb);
}

// ─── SQL-Level Semantic Equivalence ──────────────────────────
//
// Compares two SQL type strings by reverse-looking-up each to its
// SS symbol and checking if the symbols are identical. This is the
// SQL-string-level counterpart to typeInfoEquiv (which works on AST
// TypeInfo values).

/// Check if two SQL type strings are semantically equivalent via reverse lookup.
pub fn semanticEquiv(a_sql_type: []const u8, a_col_name: []const u8, a_dialect: Dialect, b_sql_type: []const u8, b_col_name: []const u8, b_dialect: Dialect) bool {
    const a_sym = reverse_map.reverseLookup(a_sql_type, a_col_name, false, false, a_dialect).sym;
    const b_sym = reverse_map.reverseLookup(b_sql_type, b_col_name, false, false, b_dialect).sym;
    return std.mem.eql(u8, a_sym, b_sym);
}

// ─── Tests ────────────────────────────────────────────────────

const testing = std.testing;

test "typeInfoEquiv: identical types" {
    try testing.expect(typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "n" }, .mysql));
    try testing.expect(typeInfoEquiv(.{ .simple = "s" }, .{ .simple = "s" }, .mysql));
    try testing.expect(typeInfoEquiv(.none, .none, .mysql));
}

test "typeInfoEquiv: MySQL n/N NOT equivalent (int vs bigint)" {
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "N" }, .mysql));
    try testing.expect(!typeInfoEquiv(.{ .simple = "N" }, .{ .simple = "n" }, .mysql));
}

test "typeInfoEquiv: MySQL 4/N4 equivalent" {
    try testing.expect(typeInfoEquiv(.{ .simple = "4" }, .{ .simple = "N4" }, .mysql));
}

test "typeInfoEquiv: MySQL 8/N8 equivalent" {
    try testing.expect(typeInfoEquiv(.{ .simple = "8" }, .{ .simple = "N8" }, .mysql));
}

test "typeInfoEquiv: MySQL b/B NOT equivalent (boolean vs blob)" {
    try testing.expect(!typeInfoEquiv(.{ .simple = "b" }, .{ .simple = "B" }, .mysql));
}

test "typeInfoEquiv: MySQL different types not equivalent" {
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "s" }, .mysql));
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "4" }, .mysql));
    try testing.expect(!typeInfoEquiv(.{ .simple = "s" }, .{ .simple = "t" }, .mysql));
}

test "typeInfoEquiv: PG n/N NOT equivalent (int vs bigint)" {
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .{ .simple = "N" }, .pg));
}

test "typeInfoEquiv: PG 4/N4 equivalent" {
    try testing.expect(typeInfoEquiv(.{ .simple = "4" }, .{ .simple = "N4" }, .pg));
}

test "typeInfoEquiv: explicit types" {
    try testing.expect(typeInfoEquiv(.{ .varchar_explicit = 255 }, .{ .varchar_explicit = 255 }, .mysql));
    try testing.expect(!typeInfoEquiv(.{ .varchar_explicit = 255 }, .{ .varchar_explicit = 128 }, .mysql));
    try testing.expect(typeInfoEquiv(.{ .int_explicit = 11 }, .{ .int_explicit = 11 }, .pg));
}

test "typeInfoEquiv: cross-tag not equivalent" {
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .none, .mysql));
    try testing.expect(!typeInfoEquiv(.{ .simple = "n" }, .{ .varchar_explicit = 255 }, .mysql));
}

// ─── semanticEquiv tests ─────────────────────────────────────

test "semanticEquiv: MySQL int ↔ PG integer → true" {
    try testing.expect(semanticEquiv("int", "id", .mysql, "integer", "id", .pg));
}

test "semanticEquiv: MySQL int ↔ PG bigint → false" {
    try testing.expect(!semanticEquiv("int", "id", .mysql, "bigint", "id", .pg));
}

test "semanticEquiv: MySQL datetime ↔ PG timestamp → true" {
    try testing.expect(semanticEquiv("datetime", "created_at", .mysql, "timestamp", "created_at", .pg));
}

test "semanticEquiv: MySQL blob ↔ PG bytea → true" {
    try testing.expect(semanticEquiv("blob", "data", .mysql, "bytea", "data", .pg));
}

test "semanticEquiv: MySQL boolean ↔ PG boolean → true (same name)" {
    try testing.expect(semanticEquiv("boolean", "flag", .mysql, "boolean", "flag", .pg));
}

test "semanticEquiv: MySQL tinyint ↔ PG smallint → false (n vs i)" {
    try testing.expect(!semanticEquiv("tinyint", "age", .mysql, "smallint", "age", .pg));
}

test "semanticEquiv: MySQL text ↔ PG text → true" {
    try testing.expect(semanticEquiv("text", "bio", .mysql, "text", "bio", .pg));
}

test "semanticEquiv: MySQL int ↔ SQLite INTEGER → true" {
    try testing.expect(semanticEquiv("int", "id", .mysql, "INTEGER", "id", .sqlite));
}

test "semanticEquiv: MySQL varchar(255) ↔ PG varchar → true (both → s)" {
    try testing.expect(semanticEquiv("varchar(255)", "name", .mysql, "varchar", "name", .pg));
}
