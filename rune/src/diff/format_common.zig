const std = @import("std");
const ast_mod = @import("../types/ast.zig");

/// Format TypeInfo to a user-friendly string representation.
/// Shared by text and markdown diff formatters.
pub fn formatTypeInfo(info: ast_mod.TypeInfo, buf: []u8) []const u8 {
    return switch (info) {
        .none => "any",
        .simple => |s| s,
        .int_explicit => |n| {
            const len = std.fmt.bufPrint(buf, "int({d})", .{n}) catch return "int";
            return len;
        },
        .decimal_explicit => |ds| {
            const len = std.fmt.bufPrint(buf, "decimal({d},{d})", .{ ds.precision, ds.scale }) catch return "decimal";
            return len;
        },
        .varchar_explicit => |n| {
            const len = std.fmt.bufPrint(buf, "varchar({d})", .{n}) catch return "varchar";
            return len;
        },
        .enum_type => "enum",
        .raw_sql => |s| s,
    };
}
