const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;
const naming = @import("naming.zig");

// ─── Custom Type / Enum Validation Rules ──────────────────────
// Rules that validate custom type definitions: naming, usage,
// empty enums, and duplicate values.

pub fn checkEnumCase(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        if (!naming.isUpperSnakeCase(ct.name)) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' should use UPPER_CASE naming", .{ct.name});
            try results.append(alloc, .{
                .rule = "enum-case",
                .table = ct.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkOrphanType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        var used = false;
        for (ast.tables) |table| {
            for (table.fields) |field| {
                switch (field.type_info) {
                    .simple => |s| if (std.mem.eql(u8, s, ct.name)) {
                        used = true;
                        break;
                    },
                    else => {},
                }
                if (used) break;
            }
            if (used) break;
        }
        if (!used) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is defined but never used by any table", .{ct.name});
            try results.append(alloc, .{
                .rule = "orphan-type",
                .table = ct.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkEnumEmpty(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        // Check if custom type is an enum with no values
        if (ct.base == .enum_type and ct.base.enum_type.len == 0) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is an enum with no values — add at least one value", .{ct.name});
            try results.append(alloc, .{
                .rule = "enum-empty",
                .table = ct.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

pub fn checkEnumValueDuplicate(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        switch (ct.base) {
            .enum_type => |values| {
                var seen = std.StringHashMap(u32).init(alloc);
                defer seen.deinit();
                for (values, 0..) |val, idx| {
                    const gop = try seen.getOrPut(val);
                    if (gop.found_existing) {
                        const msg = try std.fmt.allocPrint(alloc, "enum value '{s}' in type '{s}' is duplicated (first at position {d})", .{ val, ct.name, gop.value_ptr.* });
                        try results.append(alloc, .{
                            .rule = "enum-value-duplicate",
                            .table = ct.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    } else {
                        gop.value_ptr.* = @intCast(idx);
                    }
                }
            },
            else => {},
        }
    }
}
