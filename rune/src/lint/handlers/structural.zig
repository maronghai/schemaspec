const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;
const validation = @import("validation.zig");

// ─── Structural Rules ──────────────────────────────────────────
// Rules that check table structure: primary keys, timestamps,
// field count, comments, and naming length.

pub fn checkNoPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var has_pk = false;
        for (table.fields) |field| {
            if (validation.isPrimaryKey(field)) {
                has_pk = true;
                break;
            }
        }
        if (!has_pk) {
            for (table.indexes) |idx| {
                if (idx.kind == .primary_key) {
                    has_pk = true;
                    break;
                }
            }
        }
        if (!has_pk) {
            try results.append(alloc, .{
                .rule = "no-pk",
                .table = table.name,
                .message = "table has no primary key",
                .severity = .warning,
            });
        }
    }
}

pub fn checkNoTimestamps(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var has_ts = false;
        for (table.fields) |field| {
            if (std.mem.eql(u8, field.name, "created_at") or std.mem.eql(u8, field.name, "updated_at")) {
                has_ts = true;
                break;
            }
        }
        if (!has_ts) {
            try results.append(alloc, .{
                .rule = "no-timestamps",
                .table = table.name,
                .message = "no created_at/updated_at fields",
                .severity = .info,
            });
        }
    }
}

pub fn checkWideTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.fields.len > cfg.wide_table_max) {
            const msg = try std.fmt.allocPrint(alloc, "table has {d} fields (threshold: {d})", .{ table.fields.len, cfg.wide_table_max });
            try results.append(alloc, .{
                .rule = "wide-table",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

pub fn checkCount(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        var non_pk_count: usize = 0;
        for (table.fields) |field| {
            if (!validation.isPrimaryKey(field)) non_pk_count += 1;
        }
        if (non_pk_count < cfg.count_min) {
            const msg = try std.fmt.allocPrint(alloc, "table has only {d} non-PK field(s) — is this a junction table?", .{non_pk_count});
            try results.append(alloc, .{
                .rule = "count",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkEmptyTable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.fields.len == 0) {
            try results.append(alloc, .{
                .rule = "empty-table",
                .table = table.name,
                .message = "table has no fields",
                .severity = .warning,
            });
        }
    }
}

pub fn checkTableComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.comment == null or (table.comment != null and table.comment.?.len == 0)) {
            const msg = try std.fmt.allocPrint(alloc, "table '{s}' has no comment", .{table.name});
            try results.append(alloc, .{
                .rule = "table-comment",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkTableNameLength(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        if (table.name.len > cfg.table_name_max) {
            const msg = try std.fmt.allocPrint(alloc, "table name '{s}' is {d} chars (max: {d})", .{ table.name, table.name.len, cfg.table_name_max });
            try results.append(alloc, .{
                .rule = "table-name-length",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

pub fn checkIndexColumnsMax(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.indexes) |idx| {
            if (idx.fields.len > cfg.index_columns_max) {
                const msg = try std.fmt.allocPrint(alloc, "index on '{s}' has {d} columns (max: {d})", .{ table.name, idx.fields.len, cfg.index_columns_max });
                try results.append(alloc, .{
                    .rule = "index-columns-max",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkColumnNameTooLong(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (field.name.len > cfg.column_name_max) {
                const msg = try std.fmt.allocPrint(alloc, "column name '{s}' on table '{s}' is {d} chars (max: {d})", .{ field.name, table.name, field.name.len, cfg.column_name_max });
                try results.append(alloc, .{
                    .rule = "column-name-too-long",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if columns lack documentation comments.
/// Suggests adding `: comment` to improve schema documentation.
pub fn checkColumnNoComment(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Skip if table has no comment either (table_comment rule covers that)
        if (table.comment == null) continue;

        for (table.fields) |field| {
            if (field.comment == null) {
                const msg = try std.fmt.allocPrint(alloc, "column '{s}' lacks documentation comment", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-no-comment",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}


/// True when a column name follows timestamp naming conventions:
/// exactly `created_at` / `updated_at` / `deleted_at`, or ending in `_at` / `_on`.
fn isTimestampName(name: []const u8) bool {
    if (std.mem.eql(u8, name, "created_at") or
        std.mem.eql(u8, name, "updated_at") or
        std.mem.eql(u8, name, "deleted_at"))
    {
        return true;
    }
    if (name.len >= 3 and std.mem.eql(u8, name[name.len - 3 ..], "_at")) return true;
    if (name.len >= 3 and std.mem.eql(u8, name[name.len - 3 ..], "_on")) return true;
    return false;
}

pub fn checkTimestampType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isTimestampName(field.name) and !field.type_info.isDatetime()) {
                const msg = try std.fmt.allocPrint(
                    alloc,
                    "column '{s}' follows timestamp naming but is not a datetime type",
                    .{field.name},
                );
                try results.append(alloc, .{
                    .rule = "timestamp-type",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

pub fn checkPkNotFirst(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var pk_index: ?usize = null;
        var pk_count: usize = 0;
        for (table.fields, 0..) |field, idx| {
            if (validation.isPrimaryKey(field)) {
                pk_count += 1;
                if (pk_index == null) pk_index = idx;
            }
        }
        if (pk_count == 1 and pk_index != null and pk_index.? != 0) {
            const msg = try std.fmt.allocPrint(
                alloc,
                "primary key column is not the first column (position {d})",
                .{pk_index.? + 1},
            );
            try results.append(alloc, .{
                .rule = "pk-not-first",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}
