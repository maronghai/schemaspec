const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Location = protocol.Location;
const helpers = @import("helpers.zig");
const makeRange = helpers.makeRange;
const lineNoToZeroBased = helpers.lineNoToZeroBased;

// ─── Type Definition ─────────────────────────────────────────
// Navigate from a field's type to its custom type definition.
// For example, from `status  = Status` to `~ Status = { ... }`.
//
// Since TypedColumn doesn't carry a direct reference to the custom type
// name (the resolver inlines it), we match by enum values to find the
// source custom type definition.

/// Find the type definition location for the symbol at the given position.
/// Returns the location of the custom type definition if the cursor is on
/// a field that references a custom type, or null otherwise.
pub fn getTypeDefinition(alloc: std.mem.Allocator, ast: TypedAst, uri: []const u8, position: Position) ?Location {
    _ = alloc;
    const line = position.line;

    // Check if cursor is on a table field line
    for (ast.tables) |table| {
        for (table.columns) |col| {
            const col_line = lineNoToZeroBased(col.line_no);
            if (line == col_line) {
                // Check if this column uses a custom type (has enum values)
                if (col.flags.is_enum and col.enum_values.len > 0) {
                    // Find the custom type definition by matching enum values
                    for (ast.custom_types) |ct| {
                        if (ct.base == .enum_type) {
                            if (enumValuesMatch(col.enum_values, ct.base.enum_type)) {
                                const def_line = lineNoToZeroBased(ct.line_no);
                                return .{
                                    .uri = uri,
                                    .range = makeRange(def_line, 0, def_line, @intCast(ct.name.len + 2)), // +2 for "~ "
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    return null;
}

/// Check if two enum value slices are equal.
fn enumValuesMatch(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |val, i| {
        if (!std.mem.eql(u8, val, b[i])) return false;
    }
    return true;
}
