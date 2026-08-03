const std = @import("std");
const migrate_graph = @import("migrate_graph.zig");

const testing = std.testing;

test "extractTables: CREATE TABLE" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sql = "CREATE TABLE `users` (\n  `id` int PRIMARY KEY\n);\n";
    var tables = try migrate_graph.extractTables(alloc, sql);
    defer tables.deinit();

    try testing.expect(tables.contains("users"));
    try testing.expectEqual(@as(usize, 1), tables.count());
}

test "extractTables: ALTER TABLE" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sql = "ALTER TABLE `posts` ADD COLUMN `title` varchar(100);\n";
    var tables = try migrate_graph.extractTables(alloc, sql);
    defer tables.deinit();

    try testing.expect(tables.contains("posts"));
    try testing.expectEqual(@as(usize, 1), tables.count());
}

test "extractTables: multiple tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sql =
        \\CREATE TABLE `users` (
        \\  `id` int PRIMARY KEY
        \\);
        \\CREATE TABLE `posts` (
        \\  `id` int PRIMARY KEY
        \\);
        \\ALTER TABLE `comments` ADD COLUMN `body` text;
    ;
    var tables = try migrate_graph.extractTables(alloc, sql);
    defer tables.deinit();

    try testing.expect(tables.contains("users"));
    try testing.expect(tables.contains("posts"));
    try testing.expect(tables.contains("comments"));
    try testing.expectEqual(@as(usize, 3), tables.count());
}

test "extractTables: skips comments and blank lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sql =
        \\-- This is a comment
        \\# Hash comment
        \\
        \\CREATE TABLE `orders` (
        \\  `id` int PRIMARY KEY
        \\);
    ;
    var tables = try migrate_graph.extractTables(alloc, sql);
    defer tables.deinit();

    try testing.expect(tables.contains("orders"));
    try testing.expectEqual(@as(usize, 1), tables.count());
}

test "MigrationGraph: init produces empty graph" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = try migrate_graph.MigrationGraph.init(alloc);
    defer graph.deinit();

    try testing.expectEqual(@as(usize, 0), graph.migrations.count());
    try testing.expectEqual(@as(usize, 0), graph.order.items.len);
}

test "formatGraph: empty graph" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = try migrate_graph.MigrationGraph.init(alloc);
    defer graph.deinit();

    const output = try migrate_graph.formatGraph(alloc, &graph);
    try testing.expect(std.mem.indexOf(u8, output, "Migration Graph (0 files)") != null);
}
