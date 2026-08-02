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
