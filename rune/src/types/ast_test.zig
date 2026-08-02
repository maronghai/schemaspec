const std = @import("std");
const ast = @import("ast.zig");
const TypeInfo = ast.TypeInfo;

const testing = std.testing;

// ─── TypeInfo.eql ─────────────────────────────────────────────

test "TypeInfo.eql: none == none" {
    try testing.expect(TypeInfo.eql(.none, .none));
}

test "TypeInfo.eql: simple same" {
    try testing.expect(TypeInfo.eql(.{ .simple = "n" }, .{ .simple = "n" }));
}

test "TypeInfo.eql: simple different" {
    try testing.expect(!TypeInfo.eql(.{ .simple = "n" }, .{ .simple = "s" }));
}

test "TypeInfo.eql: different tags" {
    try testing.expect(!TypeInfo.eql(.none, .{ .simple = "n" }));
    try testing.expect(!TypeInfo.eql(.{ .simple = "n" }, .{ .int_explicit = 4 }));
}

test "TypeInfo.eql: int_explicit" {
    try testing.expect(TypeInfo.eql(.{ .int_explicit = 8 }, .{ .int_explicit = 8 }));
    try testing.expect(!TypeInfo.eql(.{ .int_explicit = 4 }, .{ .int_explicit = 8 }));
}

test "TypeInfo.eql: decimal_explicit" {
    try testing.expect(TypeInfo.eql(
        .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } },
        .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } },
    ));
    try testing.expect(!TypeInfo.eql(
        .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } },
        .{ .decimal_explicit = .{ .precision = 10, .scale = 3 } },
    ));
}

test "TypeInfo.eql: varchar_explicit" {
    try testing.expect(TypeInfo.eql(.{ .varchar_explicit = 255 }, .{ .varchar_explicit = 255 }));
    try testing.expect(!TypeInfo.eql(.{ .varchar_explicit = 100 }, .{ .varchar_explicit = 255 }));
}

test "TypeInfo.eql: enum_type same" {
    const vals = [_][]const u8{ "a", "b", "c" };
    try testing.expect(TypeInfo.eql(
        .{ .enum_type = &vals },
        .{ .enum_type = &vals },
    ));
}

test "TypeInfo.eql: enum_type different length" {
    const vals3 = [_][]const u8{ "a", "b", "c" };
    const vals2 = [_][]const u8{ "a", "b" };
    try testing.expect(!TypeInfo.eql(
        .{ .enum_type = &vals3 },
        .{ .enum_type = &vals2 },
    ));
}

test "TypeInfo.eql: raw_sql same" {
    try testing.expect(TypeInfo.eql(.{ .raw_sql = "GEOMETRY" }, .{ .raw_sql = "GEOMETRY" }));
    try testing.expect(!TypeInfo.eql(.{ .raw_sql = "GEOMETRY" }, .{ .raw_sql = "POINT" }));
}

// ─── TypeInfo.isNumeric ───────────────────────────────────────

test "TypeInfo.isNumeric: none → false" {
    try testing.expect(!TypeInfo.isNumeric(.none));
}

test "TypeInfo.isNumeric: numeric simple types" {
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "n" })); // int
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "N" })); // bigint
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "i" })); // tinyint
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "m" })); // mediumint
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "M" })); // unsigned
    try testing.expect(TypeInfo.isNumeric(.{ .simple = "p" })); // decimal
}

test "TypeInfo.isNumeric: non-numeric simple types → false" {
    try testing.expect(!TypeInfo.isNumeric(.{ .simple = "s" })); // varchar
    try testing.expect(!TypeInfo.isNumeric(.{ .simple = "d" })); // date
    try testing.expect(!TypeInfo.isNumeric(.{ .simple = "b" })); // boolean
}

test "TypeInfo.isNumeric: explicit types" {
    try testing.expect(TypeInfo.isNumeric(.{ .int_explicit = 4 }));
    try testing.expect(TypeInfo.isNumeric(.{ .decimal_explicit = .{ .precision = 10, .scale = 2 } }));
    try testing.expect(!TypeInfo.isNumeric(.{ .varchar_explicit = 255 }));
}

// ─── TypeInfo.isString ────────────────────────────────────────

test "TypeInfo.isString: none → false" {
    try testing.expect(!TypeInfo.isString(.none));
}

test "TypeInfo.isString: string simple types" {
    try testing.expect(TypeInfo.isString(.{ .simple = "s" })); // varchar
    try testing.expect(TypeInfo.isString(.{ .simple = "S" })); // longtext
    try testing.expect(TypeInfo.isString(.{ .simple = "j" })); // json
    try testing.expect(TypeInfo.isString(.{ .simple = "J" })); // jsonb
    try testing.expect(TypeInfo.isString(.{ .simple = "I" })); // inet
    try testing.expect(TypeInfo.isString(.{ .simple = "U" })); // uuid
    try testing.expect(TypeInfo.isString(.{ .simple = "B" })); // blob
}

test "TypeInfo.isString: non-string simple types → false" {
    try testing.expect(!TypeInfo.isString(.{ .simple = "n" })); // int
    try testing.expect(!TypeInfo.isString(.{ .simple = "d" })); // date
}

test "TypeInfo.isString: multi-char simple types → true (passthrough)" {
    try testing.expect(TypeInfo.isString(.{ .simple = "xyz" }));
}

test "TypeInfo.isString: explicit types" {
    try testing.expect(TypeInfo.isString(.{ .varchar_explicit = 255 }));
    try testing.expect(TypeInfo.isString(.{ .enum_type = &.{ "a", "b" } }));
    try testing.expect(TypeInfo.isString(.{ .raw_sql = "GEOMETRY" }));
    try testing.expect(!TypeInfo.isString(.{ .int_explicit = 4 }));
}

// ─── TypeInfo.isDatetime ──────────────────────────────────────

test "TypeInfo.isDatetime: none → false" {
    try testing.expect(!TypeInfo.isDatetime(.none));
}

test "TypeInfo.isDatetime: datetime simple types" {
    try testing.expect(TypeInfo.isDatetime(.{ .simple = "d" })); // date
    try testing.expect(TypeInfo.isDatetime(.{ .simple = "t" })); // time
    try testing.expect(TypeInfo.isDatetime(.{ .simple = "T" })); // timestamp
}

test "TypeInfo.isDatetime: non-datetime types → false" {
    try testing.expect(!TypeInfo.isDatetime(.{ .simple = "n" }));
    try testing.expect(!TypeInfo.isDatetime(.{ .simple = "s" }));
    try testing.expect(!TypeInfo.isDatetime(.{ .int_explicit = 4 }));
}

// ─── TypeInfo.isBoolean ───────────────────────────────────────

test "TypeInfo.isBoolean: b → true" {
    try testing.expect(TypeInfo.isBoolean(.{ .simple = "b" }));
}

test "TypeInfo.isBoolean: non-boolean types → false" {
    try testing.expect(!TypeInfo.isBoolean(.none));
    try testing.expect(!TypeInfo.isBoolean(.{ .simple = "n" }));
    try testing.expect(!TypeInfo.isBoolean(.{ .simple = "bb" })); // multi-char
    try testing.expect(!TypeInfo.isBoolean(.{ .int_explicit = 4 }));
}
