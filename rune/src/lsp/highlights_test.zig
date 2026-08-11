const std = @import("std");
const highlights_mod = @import("highlights.zig");
const typed_ast = @import("../types/typed_ast.zig");

const testing = std.testing;

// ─── Helper: Create empty TypedAst ───────────────────────────

fn emptyTypedAst() typed_ast.TypedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
}

// ─── getDocumentHighlights Tests ─────────────────────────────

test "getDocumentHighlights: no matches returns empty" {
    const doc = "# users {\n  id n ++ PK\n}\n";
    const ast = emptyTypedAst();
    const highlights = highlights_mod.getDocumentHighlights(testing.allocator, ast, 0, 0, doc);
    defer testing.allocator.free(highlights);
    try testing.expectEqual(@as(usize, 0), highlights.len);
}

test "getDocumentHighlights: HighlightKind enum values" {
    // Verify the enum has the expected values
    try testing.expectEqual(@as(u32, 1), @intFromEnum(highlights_mod.HighlightKind.text));
    try testing.expectEqual(@as(u32, 2), @intFromEnum(highlights_mod.HighlightKind.read));
    try testing.expectEqual(@as(u32, 3), @intFromEnum(highlights_mod.HighlightKind.write));
}

test "getDocumentHighlights: DocumentHighlight struct fields" {
    // Verify the struct has the expected fields
    const highlight = highlights_mod.DocumentHighlight{
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 0, .character = 5 },
        },
        .kind = .write,
    };
    try testing.expectEqual(highlights_mod.HighlightKind.write, highlight.kind);
    try testing.expectEqual(@as(u32, 0), highlight.range.start.line);
    try testing.expectEqual(@as(u32, 5), highlight.range.end.character);
}
