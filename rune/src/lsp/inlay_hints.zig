const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Range = protocol.Range;
const InlayHint = protocol.InlayHint;
const InlayHintKind = protocol.InlayHintKind;
const makeRange = @import("helpers.zig").makeRange;
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── Inlay Hints ─────────────────────────────────────────────
// Show resolved SQL types next to SS type symbols in the editor.
// For example: `n` shows as `n -> int`, `s64` shows as `s64 -> varchar(64)`.

/// Format a SqlType to a human-readable string for inlay hints.
fn formatSqlTypeForHint(alloc: std.mem.Allocator, sql_type: anytype, dialect: Dialect) ?[]const u8 {
    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    sql_type.toSql(dialect, &law.writer) catch return null;
    return law.toOwnedSlice() catch null;
}

/// Generate inlay hints for a document.
/// Iterates all tables and columns, emitting type hints at the end of each
/// column's type symbol position (line_no, after the type token).
pub fn getInlayHints(
    alloc: std.mem.Allocator,
    ast: TypedAst,
    dialect: Dialect,
) ![]const InlayHint {
    var hints = try std.ArrayList(InlayHint).initCapacity(alloc, ast.tables.len * 4);
    errdefer {
        for (hints.items) |h| alloc.free(h.label);
        hints.deinit(alloc);
    }

    for (ast.tables) |table| {
        for (table.columns) |col| {
            // Skip columns with raw_sql type (already explicit SQL)
            switch (col.sql_type) {
                .raw_sql, .passthrough => continue,
                else => {},
            }

            const sql_type_str = formatSqlTypeForHint(alloc, col.sql_type, dialect) orelse continue;
            errdefer alloc.free(sql_type_str);

            // Build the hint label: " -> <type>"
            var label_buf = std.Io.Writer.Allocating.init(alloc);
            defer label_buf.deinit();
            label_buf.writer.print(" -> {s}", .{sql_type_str}) catch {
                alloc.free(sql_type_str);
                continue;
            };
            alloc.free(sql_type_str);

            const label = try label_buf.toOwnedSlice();
            errdefer alloc.free(label);

            // Position: at the end of the column line (line_no is 1-based)
            const line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;

            hints.appendAssumeCapacity(.{
                .position = .{ .line = line, .character = 1000 },
                .label = label,
                .kind = .type_hint,
            });
        }
    }

    return try hints.toOwnedSlice(alloc);
}
