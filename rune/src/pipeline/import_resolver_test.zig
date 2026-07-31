const std = @import("std");
const ir = @import("import_resolver.zig");

const testing = std.testing;

// ─── splitLines ──────────────────────────────────────────────

test "splitLines: splits by newline" {
    const alloc = testing.allocator;
    const data = "line1\nline2\nline3";
    const lines = try ir.splitLines(alloc, data);
    defer alloc.free(lines);

    try testing.expectEqual(@as(usize, 3), lines.len);
    try testing.expectEqualStrings("line1", lines[0]);
    try testing.expectEqualStrings("line2", lines[1]);
    try testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines: strips trailing carriage return" {
    const alloc = testing.allocator;
    const data = "line1\r\nline2\r\n";
    const lines = try ir.splitLines(alloc, data);
    defer alloc.free(lines);

    try testing.expectEqual(@as(usize, 3), lines.len); // trailing \n produces empty last line
    try testing.expectEqualStrings("line1", lines[0]);
    try testing.expectEqualStrings("line2", lines[1]);
}

test "splitLines: empty input" {
    const alloc = testing.allocator;
    const data = "";
    const lines = try ir.splitLines(alloc, data);
    defer alloc.free(lines);

    try testing.expectEqual(@as(usize, 1), lines.len); // empty string produces one empty line
}

test "splitLines: single line no trailing newline" {
    const alloc = testing.allocator;
    const data = "hello world";
    const lines = try ir.splitLines(alloc, data);
    defer alloc.free(lines);

    try testing.expectEqual(@as(usize, 1), lines.len);
    try testing.expectEqualStrings("hello world", lines[0]);
}

// ─── computeBaseDir ──────────────────────────────────────────

test "computeBaseDir: extracts directory from unix path" {
    const alloc = testing.allocator;
    const dir = ir.computeBaseDir(alloc, "/foo/bar/schema.ss");
    defer alloc.free(dir);
    try testing.expectEqualStrings("/foo/bar", dir);
}

test "computeBaseDir: extracts directory from relative path" {
    const alloc = testing.allocator;
    const dir = ir.computeBaseDir(alloc, "src/schemas/main.ss");
    defer alloc.free(dir);
    try testing.expectEqualStrings("src/schemas", dir);
}

test "computeBaseDir: returns empty for bare filename" {
    const alloc = testing.allocator;
    const dir = ir.computeBaseDir(alloc, "schema.ss");
    try testing.expectEqualStrings("", dir);
}

// ─── concatSlices ────────────────────────────────────────────

test "concatSlices: merges two slices" {
    const alloc = testing.allocator;
    const a = [_]u32{ 1, 2, 3 };
    const b = [_]u32{ 4, 5 };
    const result = try ir.concatSlices(alloc, u32, &a, &b);
    defer alloc.free(result);

    try testing.expectEqual(@as(usize, 5), result.len);
    try testing.expectEqual(@as(u32, 1), result[0]);
    try testing.expectEqual(@as(u32, 5), result[4]);
}

test "concatSlices: first empty" {
    const alloc = testing.allocator;
    const a = [_]u32{};
    const b = [_]u32{ 4, 5 };
    const result = try ir.concatSlices(alloc, u32, &a, &b);
    defer alloc.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
}

test "concatSlices: second empty" {
    const alloc = testing.allocator;
    const a = [_]u32{ 1, 2 };
    const b = [_]u32{};
    const result = try ir.concatSlices(alloc, u32, &a, &b);
    defer alloc.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
}

// ─── ImportContext defaults ──────────────────────────────────

test "ImportContext: default values" {
    const ctx = ir.ImportContext{
        .base_dir = "",
        .imported = undefined,
    };
    try testing.expectEqual(@as(u8, 0), ctx.depth);
    try testing.expectEqual(@as(u8, 8), ctx.max_depth);
    try testing.expectEqual(@as(usize, 0), ctx.import_paths.len);
}
