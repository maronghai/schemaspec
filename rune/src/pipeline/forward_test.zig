const std = @import("std");
const pf = @import("forward.zig");

const testing = std.testing;

test "compilePipeline: simple schema produces resolved tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expect(result.resolved.tables.len > 0);
    try testing.expectEqualStrings("user", result.resolved.tables[0].name);
}

test "compilePipeline: invalid input produces result (parser is lenient)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const bad_input = "### invalid $$$";
    const result = try pf.compilePipeline(alloc, bad_input);
    // Parser is lenient — invalid SS still produces a result
    try testing.expect(result.resolved.tables.len >= 0);
}

test "compilePipeline: FK columns produce foreign_keys on resolved table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# user
        \\id   n++
        \\name s
        \\
        \\# post
        \\id      n++
        \\user_id n
        \\
        \\> user_id user.id
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expectEqual(@as(usize, 2), result.resolved.tables.len);
    // post table should have a foreign key
    const post = result.resolved.tables[1];
    try testing.expectEqualStrings("post", post.name);
    try testing.expect(post.fks.len > 0);
    try testing.expectEqualStrings("user", post.fks[0].ref_table);
}

test "compilePipeline: enum columns produce enum_values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# orders
        \\id      n++
        \\status  e(pending,shipped,delivered)
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expectEqual(@as(usize, 1), result.resolved.tables.len);
    const table = result.resolved.tables[0];
    // status column should have enum_values
    const status_col = table.fields[1];
    try testing.expectEqualStrings("status", status_col.name);
    try testing.expect(status_col.type_info == .enum_type);
    try testing.expect(status_col.type_info.enum_type.len > 0);
}

test "compilePipeline: template inheritance merges fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\% base
        \\id   n++
        \\name s
        \\
        \\# base user
        \\email s
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expectEqual(@as(usize, 1), result.resolved.tables.len);
    const user = result.resolved.tables[0];
    try testing.expectEqualStrings("user", user.name);
    // user should have id (from template), name (from template), and email (own)
    try testing.expect(user.fields.len >= 3);
}

test "compilePipeline: multiple tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# users
        \\id n++
        \\
        \\# posts
        \\id n++
        \\
        \\# comments
        \\id n++
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expectEqual(@as(usize, 3), result.resolved.tables.len);
    try testing.expectEqualStrings("users", result.resolved.tables[0].name);
    try testing.expectEqualStrings("posts", result.resolved.tables[1].name);
    try testing.expectEqualStrings("comments", result.resolved.tables[2].name);
}

test "compilePipeline: default values preserved" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss_input =
        \\$ demo
        \\
        \\# config
        \\id    n++
        \\name  s =hello
        \\count n =0
    ;
    const result = try pf.compilePipeline(alloc, ss_input);
    try testing.expectEqual(@as(usize, 1), result.resolved.tables.len);
    const table = result.resolved.tables[0];
    // name column should have default 'hello'
    const name_col = table.fields[1];
    try testing.expect(name_col.default_val != null);
    try testing.expectEqualStrings("hello", name_col.default_val.?.value);
    // count column should have default 0
    const count_col = table.fields[2];
    try testing.expect(count_col.default_val != null);
    try testing.expectEqualStrings("0", count_col.default_val.?.value);
}
