const std = @import("std");
const protocol = @import("protocol.zig");
const compile_svc = @import("compile_service.zig");
const DocumentManager = @import("documents.zig").DocumentManager;

// ─── Code Lens ─────────────────────────────────────────────
// Provides inline actionable lenses in the editor:
// - "Validate schema" on the first line
// - "Generate SQL" on the first line
// - "Lint" on each table definition

/// A code lens item with its associated command.
pub const CodeLensItem = struct {
    line: u32,
    title: []const u8,
    command: []const u8,
};

/// Get code lenses for a document.
/// Returns an array of CodeLensItem that can be serialized to LSP CodeLens.
pub fn getCodeLens(
    alloc: std.mem.Allocator,
    text: []const u8,
    compile_result: ?compile_svc.CompileResult,
) ![]CodeLensItem {
    var lenses = try std.ArrayList(CodeLensItem).initCapacity(alloc, 8);

    // Always show file-level actions on line 0
    try lenses.append(alloc, .{
        .line = 0,
        .title = "\u{26a1} Validate",
        .command = "rune.validate",
    });
    try lenses.append(alloc, .{
        .line = 0,
        .title = "\u{1f4c4} Generate SQL",
        .command = "rune.generateSql",
    });
    try lenses.append(alloc, .{
        .line = 0,
        .title = "\u{1f50d} Lint",
        .command = "rune.lint",
    });

    // If we have a compile result, add per-table lenses
    if (compile_result) |result| {
        if (result.typed_ast) |typed_ast| {
            for (typed_ast.tables) |table| {
                // Add a "Validate" lens on each table definition line
                if (table.line_no > 0) {
                    try lenses.append(alloc, .{
                        .line = @intCast(table.line_no - 1), // Convert to 0-based
                        .title = "\u{2705} Validate table",
                        .command = "rune.validateTable",
                    });
                }
            }
        }
    } else {
        // No compile result yet — scan for table definitions in source
        var line_no: u32 = 0;
        var remaining = text;
        while (remaining.len > 0) {
            if (std.mem.startsWith(u8, remaining, "table ")) {
                try lenses.append(alloc, .{
                    .line = line_no,
                    .title = "\u{2705} Validate table",
                    .command = "rune.validateTable",
                });
            }
            // Advance to next line
            if (std.mem.indexOfScalar(u8, remaining, '\n')) |nl| {
                remaining = remaining[nl + 1 ..];
                line_no += 1;
            } else {
                break;
            }
        }
    }

    return try lenses.toOwnedSlice(alloc);
}

// ─── Tests ─────────────────────────────────────────────────

test "getCodeLens: empty file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const lenses = try getCodeLens(alloc, "", null);
    // Empty file still gets file-level lenses
    try std.testing.expectEqual(@as(usize, 3), lenses.len);
    try std.testing.expectEqual(@as(u32, 0), lenses[0].line);
    try std.testing.expectEqualStrings("\u{26a1} Validate", lenses[0].title);
    try std.testing.expectEqualStrings("rune.validate", lenses[0].command);
}

test "getCodeLens: file with tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const text =
        \\table users {
        \\  id n ++ PK
        \\}
        \\
        \\table posts {
        \\  id n ++ PK
        \\}
    ;
    const lenses = try getCodeLens(alloc, text, null);
    // 3 file-level + 2 table-level = 5
    try std.testing.expectEqual(@as(usize, 5), lenses.len);
    // Table lenses should be on lines 0 and 4 (0-based)
    try std.testing.expectEqual(@as(u32, 0), lenses[3].line);
    try std.testing.expectEqual(@as(u32, 4), lenses[4].line);
}

test "getCodeLens: table at various positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const text =
        \\# This is a comment
        \\
        \\table users {
        \\  id n ++ PK
        \\}
    ;
    const lenses = try getCodeLens(alloc, text, null);
    // 3 file-level + 1 table-level = 4
    try std.testing.expectEqual(@as(usize, 4), lenses.len);
    try std.testing.expectEqual(@as(u32, 2), lenses[3].line);
}

test "getCodeLens: template definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const text =
        \\% base {
        \\  id n ++ PK
        \\}
        \\
        \\table users #base {
        \\  name s64
        \\}
    ;
    const lenses = try getCodeLens(alloc, text, null);
    // Only "table users" gets a lens, not "% base"
    // 3 file-level + 1 table-level = 4
    try std.testing.expectEqual(@as(usize, 4), lenses.len);
    try std.testing.expectEqual(@as(u32, 4), lenses[3].line);
}
