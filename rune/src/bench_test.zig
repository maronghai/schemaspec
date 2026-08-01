const std = @import("std");
const bench = @import("bench.zig");
const dialect_enum = @import("dialect/enum.zig");

const testing = std.testing;

test "parseDialect: mysql" {
    try testing.expectEqual(dialect_enum.Dialect.mysql, bench.parseDialect("mysql"));
}

test "parseDialect: pg" {
    try testing.expectEqual(dialect_enum.Dialect.pg, bench.parseDialect("pg"));
}

test "parseDialect: postgres" {
    try testing.expectEqual(dialect_enum.Dialect.pg, bench.parseDialect("postgres"));
}

test "parseDialect: sqlite" {
    try testing.expectEqual(dialect_enum.Dialect.sqlite, bench.parseDialect("sqlite"));
}

test "parseDialect: mssql" {
    try testing.expectEqual(dialect_enum.Dialect.mssql, bench.parseDialect("mssql"));
}

test "parseDialect: sqlserver" {
    try testing.expectEqual(dialect_enum.Dialect.mssql, bench.parseDialect("sqlserver"));
}

test "parseDialect: oracle" {
    try testing.expectEqual(dialect_enum.Dialect.oracle, bench.parseDialect("oracle"));
}

test "parseDialect: ora" {
    try testing.expectEqual(dialect_enum.Dialect.oracle, bench.parseDialect("ora"));
}

test "parseDialect: db2" {
    try testing.expectEqual(dialect_enum.Dialect.db2, bench.parseDialect("db2"));
}

test "parseDialect: idb2" {
    try testing.expectEqual(dialect_enum.Dialect.db2, bench.parseDialect("idb2"));
}

test "parseDialect: unknown returns error" {
    try testing.expectError(error.UnknownDialect, bench.parseDialect("unknown"));
}

test "parseDialect: empty string returns error" {
    try testing.expectError(error.UnknownDialect, bench.parseDialect(""));
}

test "stagePairs: returns 5 stages" {
    const current = bench.StageTimes{
        .tokenize = 1.0,
        .parse = 2.0,
        .semantic = 3.0,
        .type_resolve = 4.0,
        .codegen = 5.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 1.0,
        .parse = 2.0,
        .semantic = 3.0,
        .type_resolve = 4.0,
        .codegen = 5.0,
    };
    const pairs = bench.stagePairs(current, baseline);
    try testing.expectEqual(@as(usize, 5), pairs.len);
    try testing.expectEqualStrings("tokenize", pairs[0].name);
    try testing.expectEqualStrings("codegen", pairs[4].name);
}

test "Baseline.total: sums all stages" {
    const b = bench.Baseline{
        .tokenize = 1.0,
        .parse = 2.0,
        .semantic = 3.0,
        .type_resolve = 4.0,
        .codegen = 5.0,
    };
    try testing.expectEqual(@as(f64, 15.0), b.total());
}
