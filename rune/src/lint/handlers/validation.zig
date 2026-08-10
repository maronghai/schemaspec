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
