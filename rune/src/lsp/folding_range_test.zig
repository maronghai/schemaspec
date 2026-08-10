const std = @import("std");
const testing = std.testing;
const folding_range = @import("folding_range.zig");

test "folding range: table block" {
    const text =
        \\# users {
        \\  id n++
        \\  name s32
        \\}
    ;
    const ranges = try folding_range.getFoldingRanges(testing.allocator, text);
    defer testing.allocator.free(ranges);

    try testing.expectEqual(@as(usize, 1), ranges.len);
    try testing.expectEqual(@as(u32, 0), ranges[0].start_line);
    try testing.expectEqual(@as(u32, 3), ranges[0].end_line);
}

test "folding range: template block" {
    const text =
        \\% base
        \\id n++
        \\...
        \\version N
        \\
        \\# user
        \\name s32
    ;
    const ranges = try folding_range.getFoldingRanges(testing.allocator, text);
    defer testing.allocator.free(ranges);

    // Template % base folds from line 0 to line 4 (before # user at line 5)
    try testing.expectEqual(@as(usize, 1), ranges.len);
    try testing.expectEqual(@as(u32, 0), ranges[0].start_line);
    try testing.expectEqual(@as(u32, 4), ranges[0].end_line);
}

test "folding range: @if/@endif block" {
    const text =
        \\# users {
        \\  id n++
        \\@if(dialect=pg)
        \\  uuid_col uuid
        \\@endif
        \\}
    ;
    const ranges = try folding_range.getFoldingRanges(testing.allocator, text);
    defer testing.allocator.free(ranges);

    // Should have 2 ranges: @if/@endif and table block
    try testing.expectEqual(@as(usize, 2), ranges.len);
    // First range is @if/@endif
    try testing.expectEqual(@as(u32, 2), ranges[0].start_line);
    try testing.expectEqual(@as(u32, 4), ranges[0].end_line);
}

test "folding range: multiple tables" {
    const text =
        \\# users {
        \\  id n++
        \\}
        \\
        \\# posts {
        \\  id n++
        \\}
    ;
    const ranges = try folding_range.getFoldingRanges(testing.allocator, text);
    defer testing.allocator.free(ranges);

    try testing.expectEqual(@as(usize, 2), ranges.len);
    try testing.expectEqual(@as(u32, 0), ranges[0].start_line);
    try testing.expectEqual(@as(u32, 2), ranges[0].end_line);
    try testing.expectEqual(@as(u32, 4), ranges[1].start_line);
    try testing.expectEqual(@as(u32, 6), ranges[1].end_line);
}

test "folding range: empty input" {
    const text = "";
    const ranges = try folding_range.getFoldingRanges(testing.allocator, text);
    defer testing.allocator.free(ranges);

    try testing.expectEqual(@as(usize, 0), ranges.len);
}
