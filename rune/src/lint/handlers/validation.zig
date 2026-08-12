const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── Re-exports ──────────────────────────────────────────────
// Domain-specific validation rules are now in focused modules.
pub const fk = @import("fk.zig");
pub const index = @import("index.zig");
pub const view = @import("view.zig");
pub const enum_ = @import("enum.zig");

// ─── Shared Field Helpers ──────────────────────────────────────

/// Check if a field has a primary key modifier (auto_inc_pk or primary_key).
pub fn isPrimaryKey(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return true;
    }
    return false;
}

/// Check if a field has the nullable modifier.
pub fn isNullable(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .nullable) return true;
    }
    return false;
}

/// Check if a field has an explicit default value.
pub fn hasExplicitDefault(field: ast_mod.Field) bool {
    return field.default_val != null;
}

// ─── General Validation Rules ──────────────────────────────────
// Rules that don't fit into FK, index, view, or enum categories.

pub fn checkNullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field) and isNullable(field)) {
                const msg = try std.fmt.allocPrint(alloc, "primary key column '{s}' should not be nullable", .{field.name});
                try results.append(alloc, .{
                    .rule = "nullable-pk",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

pub fn checkBoolDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (!field.type_info.isBoolean()) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "boolean column '{s}' has no explicit default value", .{field.name});
            try results.append(alloc, .{
                .rule = "bool-default",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkColumnDefaultRequired(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "column '{s}' has no explicit DEFAULT value", .{field.name});
            try results.append(alloc, .{
                .rule = "column-default-required",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkNullableColumnDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (!isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "nullable column '{s}' has no explicit DEFAULT — consider adding `= null` for clarity", .{field.name});
            try results.append(alloc, .{
                .rule = "nullable-column-default",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkDuplicateColumn(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Track seen column names
        var seen = std.StringHashMap(void).init(alloc);
        defer seen.deinit();

        for (table.fields) |field| {
            if (seen.contains(field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "duplicate column name '{s}' in table", .{field.name});
                try results.append(alloc, .{
                    .rule = "duplicate-column",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            } else {
                try seen.put(field.name, {});
            }
        }
    }
}

/// Check if a table has a UNIQUE constraint on a column that is already the primary key.
/// A single-column UNIQUE on the PK is redundant since PRIMARY KEY implies UNIQUE.
pub fn checkUniqueConstraint(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Find the primary key column name(s)
        var pk_columns = std.ArrayList([]const u8).initCapacity(alloc, table.fields.len) catch return;
        defer pk_columns.deinit(alloc);

        for (table.fields) |field| {
            if (isPrimaryKey(field)) {
                pk_columns.append(alloc, field.name) catch return;
            }
        }

        // Check if any UNIQUE index targets a single PK column
        for (table.indexes) |idx| {
            if (idx.kind == .unique and idx.fields.len == 1) {
                for (pk_columns.items) |pk_col| {
                    if (std.mem.eql(u8, idx.fields[0], pk_col)) {
                        const msg = try std.fmt.allocPrint(alloc, "UNIQUE constraint on '{s}' is redundant (already primary key)", .{pk_col});
                        try results.append(alloc, .{
                            .rule = "unique-constraint",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    }
                }
            }
        }
    }
}

/// Check if a table has multiple auto-increment primary keys (invalid).
/// Only one auto-increment PK is allowed per table.
pub fn checkCompositePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var auto_inc_count: usize = 0;
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk) {
                    auto_inc_count += 1;
                }
            }
        }
        if (auto_inc_count > 1) {
            const msg = try std.fmt.allocPrint(alloc, "table has {d} auto-increment primary keys (only 1 allowed)", .{auto_inc_count});
            try results.append(alloc, .{
                .rule = "composite-pk",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

/// Check if a nullable column has a UNIQUE constraint (inline_unique modifier).
/// Multiple NULLs are allowed in UNIQUE columns in most databases (SQL standard),
/// which is often unintended and leads to data integrity issues.
pub fn checkColumnUniqueNullable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_unique = false;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_unique) has_unique = true;
                if (mod.kind == .nullable) has_nullable = true;
            }
            if (has_unique and has_nullable) {
                const msg = try std.fmt.allocPrint(alloc, "UNIQUE constraint on nullable column '{s}' — multiple NULLs are allowed", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-unique-nullable",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if auto-increment modifier (@ or @++) is used on a non-integer type.
/// Auto-increment only works with integer types (n, N, i, I, m, M, p).
pub fn checkColumnAutoIncrementType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_auto_inc = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .auto_inc) {
                    has_auto_inc = true;
                    break;
                }
            }
            if (!has_auto_inc) continue;
            // Check if the type is non-integer
            if (field.type_info.isString() or field.type_info.isBoolean() or field.type_info.isDatetime() or field.type_info.isBlob()) {
                const type_name = switch (field.type_info) {
                    .simple => |s| s,
                    .varchar_explicit => "varchar",
                    .enum_type => "enum",
                    .raw_sql => "raw",
                    else => "unknown",
                };
                const msg = try std.fmt.allocPrint(alloc, "auto-increment on column '{s}' with non-integer type '{s}'", .{ field.name, type_name });
                try results.append(alloc, .{
                    .rule = "column-auto-increment-type",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if columns in the same table have names that differ only by case.
/// This can cause confusion and bugs in case-insensitive databases.
pub fn checkColumnUniqueNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Compare each pair of columns (O(n²) but n is typically small)
        for (table.fields, 0..) |field_a, i| {
            for (table.fields[i + 1 ..]) |field_b| {
                if (std.mem.eql(u8, field_a.name, field_b.name)) continue; // exact duplicates handled by duplicate-column
                // Case-insensitive comparison
                var buf_a: [256]u8 = undefined;
                var buf_b: [256]u8 = undefined;
                if (field_a.name.len > 256 or field_b.name.len > 256) continue;
                const lower_a = std.ascii.lowerString(&buf_a, field_a.name);
                const lower_b = std.ascii.lowerString(&buf_b, field_b.name);
                if (std.mem.eql(u8, lower_a, lower_b)) {
                    const msg = try std.fmt.allocPrint(alloc, "columns '{s}' and '{s}' differ only by case", .{ field_a.name, field_b.name });
                    try results.append(alloc, .{
                        .rule = "column-unique-naming",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            }
        }
    }
}

/// Check if auto-increment modifier (@/++) is used on a nullable column.
/// Auto-increment columns should always be NOT NULL — nullable auto-increment
/// is contradictory and indicates a schema design error.
pub fn checkColumnAutoIncrementNullable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_auto_inc = false;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .auto_inc) has_auto_inc = true;
                if (mod.kind == .nullable) has_nullable = true;
            }
            if (has_auto_inc and has_nullable) {
                const msg = try std.fmt.allocPrint(alloc, "auto-increment on nullable column '{s}' — should be NOT NULL", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-auto-increment-nullable",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if a column's default value matches its type category.
/// Warns when numeric defaults are on string columns, boolean defaults on numeric columns, etc.
pub fn checkColumnBadDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            const dv = field.default_val orelse continue;
            const val = dv.value;
            if (val.len == 0) continue;

            const cat = field.type_info.category();

            // Check for quoted string defaults on non-string types
            if (val[0] == '\'' and val.len >= 2 and val[val.len - 1] == '\'') {
                if (cat == .numeric) {
                    const msg = try std.fmt.allocPrint(alloc, "column '{s}' has string default {s} but is a numeric type", .{ field.name, val });
                    try results.append(alloc, .{
                        .rule = "column-bad-default",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                } else if (cat == .boolean) {
                    const inner = val[1 .. val.len - 1];
                    if (!std.mem.eql(u8, inner, "true") and !std.mem.eql(u8, inner, "false") and !std.mem.eql(u8, inner, "1") and !std.mem.eql(u8, inner, "0")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' has string default {s} but is a boolean type", .{ field.name, val });
                        try results.append(alloc, .{
                            .rule = "column-bad-default",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    }
                }
            }

            // Check for numeric defaults on boolean columns
            if (cat == .boolean) {
                var is_numeric = true;
                for (val) |ch| {
                    if (ch < '0' or ch > '9') {
                        is_numeric = false;
                        break;
                    }
                }
                if (is_numeric and val.len > 0 and !std.mem.eql(u8, val, "0") and !std.mem.eql(u8, val, "1")) {
                    const msg = try std.fmt.allocPrint(alloc, "column '{s}' has numeric default {s} but is a boolean type (use true/false or 0/1)", .{ field.name, val });
                    try results.append(alloc, .{
                        .rule = "column-bad-default",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            }
        }
    }
}
