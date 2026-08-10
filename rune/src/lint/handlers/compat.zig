const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── Compatibility Rules ───────────────────────────────────────
// Rules that check cross-dialect compatibility: serial types,
// column lengths, and dialect-specific types.

pub fn checkSerialType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .simple => |s| {
                    if (std.mem.eql(u8, s, "serial") or std.mem.eql(u8, s, "bigserial")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses PostgreSQL-specific type '{s}' — use auto_increment modifier for cross-dialect compatibility", .{ field.name, s });
                        try results.append(alloc, .{
                            .rule = "serial-type",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    }
                },
                else => {},
            }
        }
    }
}

pub fn checkColumnLength(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .varchar_explicit => |len| {
                    if (len == 0) {
                        const msg = try std.fmt.allocPrint(alloc, "string column '{s}' has no explicit length — consider adding length (e.g., s64) for cross-dialect compatibility", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-length",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                .simple => |s| {
                    if (std.mem.eql(u8, s, "S")) {
                        const msg = try std.fmt.allocPrint(alloc, "string column '{s}' has no explicit length — consider adding length (e.g., s64) for cross-dialect compatibility", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-length",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                else => {},
            }
        }
    }
}

pub fn checkCrossDialectTypes(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .simple => |s| {
                    // MySQL-specific types that don't port to other dialects
                    if (std.mem.eql(u8, s, "serial") or std.mem.eql(u8, s, "bigserial")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses PostgreSQL-specific type '{s}' — use n++ for cross-dialect portability", .{ field.name, s });
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    } else if (std.mem.eql(u8, s, "unsigned") or std.mem.eql(u8, s, "unsigned_bigint")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific UNSIGNED type — not supported in PostgreSQL, SQLite, or MSSQL", .{field.name});
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    } else if (std.mem.eql(u8, s, "tinyint")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific TINYINT — use 'i' (smallint) for cross-dialect portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "mediumint")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific MEDIUMINT — use 'n' (int) for cross-dialect portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "mediumtext")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific MEDIUMTEXT — use 'S' (text) for cross-dialect portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "longtext")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific LONGTEXT — use 'S' (text) for cross-dialect portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                .enum_type => |values| {
                    if (values.len > 10) {
                        const msg = try std.fmt.allocPrint(alloc, "enum type on column '{s}' has {d} values — consider using a lookup table for >10 values", .{ field.name, values.len });
                        try results.append(alloc, .{
                            .rule = "cross-dialect-types",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                else => {},
            }
        }
    }
}
