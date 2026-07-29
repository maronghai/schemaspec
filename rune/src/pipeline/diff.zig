const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");
const migrate = @import("../diff/migrate.zig");
const migrate_json = @import("../diff/migrate_json.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const typed_ast = @import("../types/typed_ast.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const pipeline_forward = @import("../pipeline/forward.zig");
const io_mod = @import("../io.zig");

// ─── Diff/Migrate Pipeline ────────────────────────────────────

const DiffResult = struct {
    old_ast: resolved_ast.ResolvedAst,
    new_ast: resolved_ast.ResolvedAst,
    schema_diff: diff_types.SchemaDiff,
};

/// Compile both schemas and compute their diff. Shared by all diff/migrate handlers.
fn prepareDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect) !DiffResult {
    const old_ast = try pipeline_forward.compileToAst(io, alloc, old_path);
    const new_ast = try pipeline_forward.compileToAst(io, alloc, new_path);
    const schema_diff = try diff.diff(old_ast, new_ast, alloc, dialect);
    return .{ .old_ast = old_ast, .new_ast = new_ast, .schema_diff = schema_diff };
}

/// Handle `rune diff`: output human-readable text diff between two .ss files.
pub fn handleDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect, trace: bool, stats: bool, check: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    emitTraceAndStats(result, trace, stats);
    const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, dialect);
    if (check) {
        if (result.schema_diff.hasChanges()) {
            try io_mod.writeOutput(io, diff_text, null, false);
            return error.CheckFailed;
        }
        return;
    }
    try io_mod.writeOutput(io, diff_text, null, false);
}

/// Handle `rune diff --format json`: output structured JSON diff.
pub fn handleDiffJson(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool, stats: bool, check: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    emitTraceAndStats(result, trace, stats);
    if (check) {
        if (result.schema_diff.hasChanges()) return error.CheckFailed;
        return;
    }
    const json_text = try diff_format.formatDiffJson(alloc, result.schema_diff);
    try io_mod.writeOutput(io, json_text, output_path, false);
}

/// Handle `rune diff --format sarif`: output SARIF-formatted diff for CI/CD integration.
pub fn handleDiffSarif(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect, trace: bool, stats: bool, check: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    emitTraceAndStats(result, trace, stats);
    if (check) {
        if (result.schema_diff.hasChanges()) return error.CheckFailed;
        return;
    }
    const sarif_text = try diff_format.formatDiffSarif(alloc, result.schema_diff, dialect);
    try io_mod.writeOutput(io, sarif_text, null, false);
}

/// Handle `rune migrate`: generate ALTER TABLE migration SQL (or rollback SQL with --rollback).
pub fn handleMigrate(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool, rollback: bool, stats: bool, dry_run: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    emitTraceAndStats(result, trace, stats);
    if (rollback) {
        const old_typed = try TypeResolver.resolve(alloc, result.old_ast, dialect);
        const rollback_sql = try migrate.generateRollback(alloc, result.schema_diff, old_typed, result.old_ast, dialect);
        if (dry_run) {
            try io_mod.writeOutput(io, rollback_sql, null, false);
        } else {
            try io_mod.writeOutput(io, rollback_sql, output_path, false);
        }
    } else {
        const new_typed = try TypeResolver.resolve(alloc, result.new_ast, dialect);
        const migration_sql = try migrate.generateFromDiff(alloc, result.schema_diff, new_typed, result.new_ast, dialect);
        if (dry_run) {
            try io_mod.writeOutput(io, migration_sql, null, false);
        } else {
            try io_mod.writeOutput(io, migration_sql, output_path, false);
        }
    }
}

/// Handle `rune migrate --format json`: output structured JSON migration operations.
pub fn handleMigrateDiffJson(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool, stats: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    emitTraceAndStats(result, trace, stats);
    const json_text = try migrate_json.generateMigrationJson(alloc, result.schema_diff, dialect);
    try io_mod.writeOutput(io, json_text, output_path, false);
}

/// Emit trace and stats for a diff result — extracted to eliminate 4x duplication.
fn emitTraceAndStats(result: DiffResult, trace: bool, stats: bool) void {
    if (trace) traceDiffResult(result);
    if (stats) {
        const old_s = pipeline_forward.computeStats(result.old_ast);
        const new_s = pipeline_forward.computeStats(result.new_ast);
        std.debug.print("old: tables={d} fields={d} views={d}\n", .{ old_s.tables, old_s.fields, old_s.views });
        std.debug.print("new: tables={d} fields={d} views={d}\n", .{ new_s.tables, new_s.fields, new_s.views });
    }
}

// ─── Trace Helpers ──────────────────────────────────────────────

fn traceDiffResult(result: DiffResult) void {
    traceResolvedAst("old", result.old_ast);
    traceResolvedAst("new", result.new_ast);
    traceSchemaDiff(result.schema_diff);
}

fn traceResolvedAst(label: []const u8, ast: resolved_ast.ResolvedAst) void {
    std.debug.print("=== [{s} ResolvedAst] ===\n\n", .{label});
    std.debug.print("Schema: {?s}\n", .{ast.schema_name});
    std.debug.print("Tables ({d}):\n", .{ast.tables.len});
    for (ast.tables) |table| {
        std.debug.print("  # {s} ({d} fields, {d} fks, {d} indexes)\n", .{ table.name, table.fields.len, table.fks.len, table.indexes.len });
    }
    std.debug.print("\n", .{});
}

fn traceSchemaDiff(sd: diff_types.SchemaDiff) void {
    std.debug.print("=== [SchemaDiff] ===\n\n", .{});
    if (sd.dropped_tables.len > 0) {
        std.debug.print("Dropped tables ({d}):\n", .{sd.dropped_tables.len});
        for (sd.dropped_tables) |tname| {
            std.debug.print("  - {s}\n", .{tname});
        }
    }
    for (sd.table_diffs) |td| {
        std.debug.print("Table {s}: {s}\n", .{ td.name, @tagName(td.action) });
        for (td.field_diffs) |fd| {
            std.debug.print("  field {s}: {s}", .{ fd.name, @tagName(fd.action) });
            if (fd.rename_from) |rf| std.debug.print(" from {s}", .{rf});
            std.debug.print("\n", .{});
        }
        for (td.index_diffs) |idx| {
            std.debug.print("  index {s}: {s}\n", .{ idx.name, @tagName(idx.action) });
        }
    }
    std.debug.print("\n", .{});
}
