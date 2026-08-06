const std = @import("std");
const ResolvedAst = @import("types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("types/ast.zig");

// ─── Lint Engine ──────────────────────────────────────────────
// Schema quality analysis — catches anti-patterns that validation passes miss.

pub const LintSeverity = enum { warning, info };

pub const LintResult = struct {
    rule: []const u8,
    table: []const u8,
    message: []const u8,
    severity: LintSeverity,
};

pub const LintConfig = struct {
    check_pk: bool = true,
    check_naming: bool = true,
    check_fk_index: bool = true,
    check_timestamps: bool = true,
};

pub const LintOutput = enum { text, json };

/// Run all enabled lint checks on a resolved schema.
pub fn lintSchema(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (ast.tables) |table| {
        if (cfg.check_pk) try lintNoPk(alloc, &results, table);
        if (cfg.check_naming) try lintNamingConventions(alloc, &results, table);
        if (cfg.check_fk_index) try lintNoIndexFk(alloc, &results, table);
        if (cfg.check_timestamps) try lintNoTimestamps(alloc, &results, table);
    }

    return results;
}

// ─── Lint: No Primary Key ─────────────────────────────────────
// Warns when a table has no primary key field.
// Tables without PKs break ORM mapping and complicate replication.

fn lintNoPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return;
        }
    }
    // Also check for composite PK via standalone indexes
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) return;
    }
    try results.append(alloc, .{
        .rule = "no-pk",
        .table = table.name,
        .message = "table has no primary key",
        .severity = .warning,
    });
}

// ─── Lint: Naming Conventions ─────────────────────────────────
// Warns when table or column names use camelCase instead of snake_case.
// Rune convention is snake_case for all identifiers.

fn lintNamingConventions(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    if (!isSnakeCase(table.name)) {
        const msg = try std.fmt.allocPrint(alloc, "table name '{s}' should use snake_case", .{table.name});
        try results.append(alloc, .{
            .rule = "naming",
            .table = table.name,
            .message = msg,
            .severity = .info,
        });
    }
    for (table.fields) |field| {
        if (!isSnakeCase(field.name)) {
            const msg = try std.fmt.allocPrint(alloc, "column name '{s}' should use snake_case", .{field.name});
            try results.append(alloc, .{
                .rule = "naming",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

// ─── Lint: No Index on FK ─────────────────────────────────────
// Warns when FK columns lack a corresponding index.
// FKs without indexes cause slow JOIN performance on MySQL/SQLite.

fn lintNoIndexFk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        if (field.fk != null and !fieldHasIndex(table, field.name)) {
            const msg = try std.fmt.allocPrint(alloc, "foreign key column '{s}' has no index", .{field.name});
            try results.append(alloc, .{
                .rule = "no-index-fk",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

// ─── Lint: No Timestamps ──────────────────────────────────────
// Warns when tables have no created_at/updated_at fields.
// Most production tables benefit from audit timestamps.

fn lintNoTimestamps(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable) !void {
    for (table.fields) |field| {
        if (std.mem.eql(u8, field.name, "created_at") or std.mem.eql(u8, field.name, "updated_at")) return;
    }
    try results.append(alloc, .{
        .rule = "no-timestamps",
        .table = table.name,
        .message = "no created_at/updated_at fields",
        .severity = .info,
    });
}

// ─── Helpers ──────────────────────────────────────────────────

fn hasPrimaryKey(table: ResolvedTable) bool {
    for (table.fields) |field| {
        for (field.modifiers) |mod| {
            if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return true;
        }
    }
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) return true;
    }
    return false;
}

fn isSnakeCase(name: []const u8) bool {
    for (name) |c| {
        if (std.ascii.isUpper(c)) return false;
    }
    return true;
}

fn fieldHasIndex(table: ResolvedTable, field_name: []const u8) bool {
    for (table.indexes) |idx| {
        for (idx.fields) |idx_field| {
            if (std.mem.eql(u8, idx_field, field_name)) return true;
        }
    }
    return false;
}

// ─── Output Formatting ────────────────────────────────────────

/// Format lint results as human-readable text.
pub fn formatLintResults(results: []const LintResult, use_color: bool) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer aw.deinit();

    if (results.len == 0) {
        try aw.writer.writeAll("No lint issues found.\n");
        return try aw.toOwnedSlice();
    }

    var warnings: usize = 0;
    var infos: usize = 0;
    for (results) |r| {
        const severity_str = if (r.severity == .warning) "warning" else "info";
        const prefix = if (use_color) "\x1b[33m" else "";
        const suffix = if (use_color) "\x1b[0m" else "";
        try aw.writer.print("{s}{s}{s}: [{s}] {s}: {s}\n", .{
            prefix, severity_str, suffix, r.rule, r.table, r.message,
        });
        if (r.severity == .warning) warnings += 1 else infos += 1;
    }
    try aw.writer.print("\n{s}Lint summary: {d} warning(s), {d} info(s)\n", .{
        if (use_color) "\x1b[1m" else "", warnings, infos,
    });
    if (use_color) try aw.writer.writeAll("\x1b[0m");

    return try aw.toOwnedSlice();
}

/// Format lint results as JSON (machine-readable).
pub fn formatLintJson(results: []const LintResult) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer aw.deinit();

    try aw.writer.writeAll("{\"issues\":[");
    for (results, 0..) |r, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"rule\":\"");
        try aw.writer.writeAll(r.rule);
        try aw.writer.writeAll("\",\"table\":\"");
        try aw.writer.writeAll(r.table);
        try aw.writer.writeAll("\",\"message\":\"");
        // Escape JSON string
        for (r.message) |c| {
            switch (c) {
                '"' => try aw.writer.writeAll("\\\""),
                '\\' => try aw.writer.writeAll("\\\\"),
                '\n' => try aw.writer.writeAll("\\n"),
                else => try aw.writer.writeByte(c),
            }
        }
        try aw.writer.writeAll("\",\"severity\":\"");
        try aw.writer.writeAll(if (r.severity == .warning) "warning" else "info");
        try aw.writer.writeAll("\"}");
    }
    const has_warnings = for (results) |r| {
        if (r.severity == .warning) break true;
    } else false;
    try aw.writer.writeAll("],\"count\":");
    // Write count as decimal
    var count_buf: [20]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{results.len}) catch "0";
    try aw.writer.writeAll(count_str);
    try aw.writer.writeAll(",\"has_warnings\":");
    try aw.writer.writeAll(if (has_warnings) "true" else "false");
    try aw.writer.writeAll("}");

    return try aw.toOwnedSlice();
}
