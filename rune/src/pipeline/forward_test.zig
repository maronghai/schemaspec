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

test "compilePipeline: syntax error returns error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const bad_input = "### invalid $$$";
    const result = pf.compilePipeline(alloc, bad_input);
    try testing.expectError(error.ParseError, result);
}
