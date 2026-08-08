const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Location = protocol.Location;
const makeRange = @import("helpers.zig").makeRange;

// ─── Go-to-Definition ───────────────────────────────────────

/// Find the definition location for a symbol at the given position.
pub fn getDefinition(alloc: std.mem.Allocator, ast: TypedAst, uri: []const u8, position: Position) ?Location {
    _ = alloc;
    const line = position.line;

    for (ast.tables) |table| {
        for (table.fks) |fk| {
            const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else 0;
            if (line == fk_line) {
                for (ast.tables) |target| {
                    if (std.mem.eql(u8, target.name, fk.ref_table)) {
                        const target_line: u32 = if (target.line_no > 0) @intCast(target.line_no - 1) else 0;
                        return .{
                            .uri = uri,
                            .range = makeRange(target_line, 0, target_line, @intCast(target.name.len)),
                        };
                    }
                }
            }
        }
    }

    for (ast.tables) |table| {
        for (table.columns) |col| {
            const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
            if (line == col_line) {
                for (table.fks) |fk| {
                    // Check all FK fields (not just the first) for multi-column FKs
                    for (fk.fields) |field| {
                        if (std.mem.eql(u8, field, col.name)) {
                            for (ast.tables) |target| {
                                if (std.mem.eql(u8, target.name, fk.ref_table)) {
                                    const target_line: u32 = if (target.line_no > 0) @intCast(target.line_no - 1) else 0;
                                    return .{
                                        .uri = uri,
                                        .range = makeRange(target_line, 0, target_line, @intCast(target.name.len)),
                                    };
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return null;
}
