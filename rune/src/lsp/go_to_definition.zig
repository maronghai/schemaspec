const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Location = protocol.Location;
const helpers = @import("helpers.zig");
const makeRange = helpers.makeRange;
const lineNoToZeroBased = helpers.lineNoToZeroBased;

// ─── Go-to-Definition ───────────────────────────────────────

/// Find the definition location for a symbol at the given position.
pub fn getDefinition(alloc: std.mem.Allocator, ast: TypedAst, uri: []const u8, position: Position) ?Location {
    _ = alloc;
    const line = position.line;

    for (ast.tables) |table| {
        for (table.fks) |fk| {
            const fk_line = lineNoToZeroBased(fk.line_no);
            if (line == fk_line) {
                for (ast.tables) |target| {
                    if (std.mem.eql(u8, target.name, fk.ref_table)) {
                        const target_line = lineNoToZeroBased(target.line_no);
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
            const col_line = lineNoToZeroBased(col.line_no);
            if (line == col_line) {
                for (table.fks) |fk| {
                    // Check all FK fields (not just the first) for multi-column FKs
                    for (fk.fields) |field| {
                        if (std.mem.eql(u8, field, col.name)) {
                            for (ast.tables) |target| {
                                if (std.mem.eql(u8, target.name, fk.ref_table)) {
                                    const target_line = lineNoToZeroBased(target.line_no);
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
