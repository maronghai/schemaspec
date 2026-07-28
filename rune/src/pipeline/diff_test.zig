const std = @import("std");
const pipeline_diff = @import("diff.zig");
const pipeline_forward = @import("forward.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");

const testing = std.testing;

test "diff: identical schemas produce no table diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, ss);
    const new_resolved = try pipeline_forward.compilePipeline(alloc, ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    try testing.expectEqual(@as(usize, 0), schema_diff.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), schema_diff.dropped_tables.len);
}

test "diff: adding a table produces a create action" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\
        \\# post
        \\
        \\id   n++
        \\title s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, old_ss);
    const new_resolved = try pipeline_forward.compilePipeline(alloc, new_ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    try testing.expectEqual(@as(usize, 1), schema_diff.table_diffs.len);
    try testing.expectEqual(diff_types.TableAction.create, schema_diff.table_diffs[0].action);
    try testing.expectEqualStrings("post", schema_diff.table_diffs[0].name);
}

test "diff format json: produces valid JSON structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
        \\
        \\# post
        \\
        \\id   n++
    ;
    const old_resolved = try pipeline_forward.compilePipeline(alloc, old_ss);
    const new_resolved = try pipeline_forward.compilePipeline(alloc, new_ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    const json = try diff_format.formatDiffJson(alloc, schema_diff);

    try testing.expect(std.mem.indexOf(u8, json, "\"dropped_tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"table_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"view_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\": \"post\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"action\": \"create\"") != null);
}
