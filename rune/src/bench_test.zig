const std = @import("std");
const bench = @import("bench.zig");
const dialect_enum = @import("dialect/enum.zig");

const testing = std.testing;

test "parseDialect: mysql" {
    try testing.expectEqual(dialect_enum.Dialect.mysql, dialect_enum.parseDialect("mysql"));
}

test "parseDialect: pg" {
    try testing.expectEqual(dialect_enum.Dialect.pg, dialect_enum.parseDialect("pg"));
}

test "parseDialect: postgres" {
    try testing.expectEqual(dialect_enum.Dialect.pg, dialect_enum.parseDialect("postgres"));
}

test "parseDialect: sqlite" {
    try testing.expectEqual(dialect_enum.Dialect.sqlite, dialect_enum.parseDialect("sqlite"));
}

test "parseDialect: mssql" {
    try testing.expectEqual(dialect_enum.Dialect.mssql, dialect_enum.parseDialect("mssql"));
}

test "parseDialect: sqlserver" {
    try testing.expectEqual(dialect_enum.Dialect.mssql, dialect_enum.parseDialect("sqlserver"));
}

test "parseDialect: oracle" {
    try testing.expectEqual(dialect_enum.Dialect.oracle, dialect_enum.parseDialect("oracle"));
}

test "parseDialect: ora" {
    try testing.expectEqual(dialect_enum.Dialect.oracle, dialect_enum.parseDialect("ora"));
}

test "parseDialect: db2" {
    try testing.expectEqual(dialect_enum.Dialect.db2, dialect_enum.parseDialect("db2"));
}

test "parseDialect: idb2" {
    try testing.expectEqual(dialect_enum.Dialect.db2, dialect_enum.parseDialect("idb2"));
}

test "parseDialect: unknown returns error" {
    try testing.expectError(error.UnknownDialect, dialect_enum.parseDialect("unknown"));
}

test "parseDialect: empty string returns error" {
    try testing.expectError(error.UnknownDialect, dialect_enum.parseDialect(""));
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

// ─── StageTimes tests ──────────────────────────────────────────

test "StageTimes.add: accumulates values" {
    var a = bench.StageTimes{
        .tokenize = 1.0,
        .parse = 2.0,
        .semantic = 3.0,
        .type_resolve = 4.0,
        .codegen = 5.0,
    };
    const b = bench.StageTimes{
        .tokenize = 0.5,
        .parse = 1.0,
        .semantic = 1.5,
        .type_resolve = 2.0,
        .codegen = 2.5,
    };
    a.add(&b);
    try testing.expectEqual(@as(f64, 1.5), a.tokenize);
    try testing.expectEqual(@as(f64, 3.0), a.parse);
    try testing.expectEqual(@as(f64, 4.5), a.semantic);
    try testing.expectEqual(@as(f64, 6.0), a.type_resolve);
    try testing.expectEqual(@as(f64, 7.5), a.codegen);
}

test "StageTimes.avg: divides by count" {
    const t = bench.StageTimes{
        .tokenize = 10.0,
        .parse = 20.0,
        .semantic = 30.0,
        .type_resolve = 40.0,
        .codegen = 50.0,
    };
    const avg = t.avg(10);
    try testing.expectEqual(@as(f64, 1.0), avg.tokenize);
    try testing.expectEqual(@as(f64, 2.0), avg.parse);
    try testing.expectEqual(@as(f64, 3.0), avg.semantic);
    try testing.expectEqual(@as(f64, 4.0), avg.type_resolve);
    try testing.expectEqual(@as(f64, 5.0), avg.codegen);
}

test "StageTimes.total: sums all stages" {
    const t = bench.StageTimes{
        .tokenize = 1.0,
        .parse = 2.0,
        .semantic = 3.0,
        .type_resolve = 4.0,
        .codegen = 5.0,
    };
    try testing.expectEqual(@as(f64, 15.0), t.total());
}

test "StageTimes defaults: all zero" {
    const t = bench.StageTimes{};
    try testing.expectEqual(@as(f64, 0.0), t.total());
}

// ─── Regression threshold tests (10%) ──────────────────────────

test "checkRegressions: no regression at equal times" {
    const current = bench.StageTimes{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    try testing.expectEqual(@as(usize, 0), bench.checkRegressions(current, baseline));
}

test "checkRegressions: 5% increase is ok" {
    const current = bench.StageTimes{
        .tokenize = 10.5,
        .parse = 10.5,
        .semantic = 10.5,
        .type_resolve = 10.5,
        .codegen = 10.5,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    try testing.expectEqual(@as(usize, 0), bench.checkRegressions(current, baseline));
}

test "checkRegressions: 15% increase is regression" {
    const current = bench.StageTimes{
        .tokenize = 11.5,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    try testing.expectEqual(@as(usize, 1), bench.checkRegressions(current, baseline));
}

test "checkRegressions: 10% increase is boundary (not regression)" {
    const current = bench.StageTimes{
        .tokenize = 11.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    // 11.0 / 10.0 = 1.10, threshold is 1.10, so 1.10 > 1.10 is false
    try testing.expectEqual(@as(usize, 0), bench.checkRegressions(current, baseline));
}

test "checkRegressions: decrease is always ok" {
    const current = bench.StageTimes{
        .tokenize = 5.0,
        .parse = 5.0,
        .semantic = 5.0,
        .type_resolve = 5.0,
        .codegen = 5.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    try testing.expectEqual(@as(usize, 0), bench.checkRegressions(current, baseline));
}

test "checkRegressions: multiple regressions counted" {
    const current = bench.StageTimes{
        .tokenize = 15.0,
        .parse = 15.0,
        .semantic = 15.0,
        .type_resolve = 15.0,
        .codegen = 15.0,
    };
    const baseline = bench.Baseline{
        .tokenize = 10.0,
        .parse = 10.0,
        .semantic = 10.0,
        .type_resolve = 10.0,
        .codegen = 10.0,
    };
    try testing.expectEqual(@as(usize, 5), bench.checkRegressions(current, baseline));
}
