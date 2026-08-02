const std = @import("std");
const stats_mod = @import("stats.zig");
const pf = @import("forward.zig");
const resolved_ast = @import("../types/resolved_ast.zig");

const testing = std.testing;

// ─── computeStats Tests ───────────────────────────────────────

test "computeStats: empty schema returns zeros" {
    const resolved = resolved_ast.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const s = stats_mod.computeStats(resolved);
    try testing.expectEqual(@as(usize, 0), s.tables);
    try testing.expectEqual(@as(usize, 0), s.fields);
    try testing.expectEqual(@as(usize, 0), s.views);
}

test "computeStats: counts tables and fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss =
        \\$ demo
        \\
        \\# users
        \\id   n++
        \\name s
        \\
        \\# posts
        \\id      n++
        \\title   s
        \\user_id n
    ;
    const result = try pf.compilePipeline(alloc, ss, .{});
    const s = stats_mod.computeStats(result.resolved);
    try testing.expectEqual(@as(usize, 2), s.tables);
    try testing.expectEqual(@as(usize, 5), s.fields);
    try testing.expectEqual(@as(usize, 0), s.views);
}

test "computeStats: counts not_null fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss =
        \\$ demo
        \\
        \\# users
        \\id   n++
        \\name s*
    ;
    const result = try pf.compilePipeline(alloc, ss, .{});
    const s = stats_mod.computeStats(result.resolved);
    try testing.expectEqual(@as(usize, 1), s.not_null_fields);
}

test "computeStats: counts views" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss =
        \\$ demo
        \\
        \\# users
        \\id n++
        \\
        \\& user_view = SELECT id FROM users
    ;
    const result = try pf.compilePipeline(alloc, ss, .{});
    const s = stats_mod.computeStats(result.resolved);
    try testing.expectEqual(@as(usize, 1), s.views);
}

// ─── formatStatsJson Tests ────────────────────────────────────

test "formatStatsJson: zero values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const s = stats_mod.Stats{
        .tables = 0, .fields = 0, .views = 0,
        .not_null_fields = 0, .numeric_fields = 0, .string_fields = 0,
        .datetime_fields = 0, .boolean_fields = 0, .other_fields = 0,
    };
    const json = try stats_mod.formatStatsJson(alloc, s);
    try testing.expectEqualStrings(
        \\{"tables":0,"fields":0,"not_null":0,"numeric":0,"string":0,"datetime":0,"boolean":0,"other":0,"views":0}
    , json);
}

test "formatStatsJson: populated values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const s = stats_mod.Stats{
        .tables = 3, .fields = 20, .views = 1,
        .not_null_fields = 12, .numeric_fields = 8, .string_fields = 10,
        .datetime_fields = 1, .boolean_fields = 1, .other_fields = 0,
    };
    const json = try stats_mod.formatStatsJson(alloc, s);
    try testing.expectEqualStrings(
        \\{"tables":3,"fields":20,"not_null":12,"numeric":8,"string":10,"datetime":1,"boolean":1,"other":0,"views":1}
    , json);
}
