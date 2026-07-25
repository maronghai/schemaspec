const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");
const migrate = @import("../diff/migrate.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const typed_ast = @import("../types/typed_ast.zig");
const pipeline_forward = @import("../pipeline/forward.zig");

// ─── Diff/Migrate Pipeline ────────────────────────────────────

fn prepareDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect) !struct { old_ast: resolved_ast.ResolvedAst, new_ast: resolved_ast.ResolvedAst, schema_diff: diff_types.SchemaDiff } {
    const old_ast = try pipeline_forward.compileToAst(io, alloc, old_path);
    const new_ast = try pipeline_forward.compileToAst(io, alloc, new_path);
    const schema_diff = try diff.diff(old_ast, new_ast, alloc, dialect);
    return .{ .old_ast = old_ast, .new_ast = new_ast, .schema_diff = schema_diff };
}

pub fn handleDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect, trace: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);

    if (trace) {
        traceResolvedAst("old", result.old_ast);
        traceResolvedAst("new", result.new_ast);
        traceSchemaDiff(result.schema_diff);
    }

    const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, dialect);
    try @import("../io.zig").writeOutput(io, diff_text, null);
}

pub fn handleDiffJson(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);

    if (trace) {
        traceResolvedAst("old", result.old_ast);
        traceResolvedAst("new", result.new_ast);
        traceSchemaDiff(result.schema_diff);
    }

    const json_text = try diff_format.formatDiffJson(alloc, result.schema_diff);
    try @import("../io.zig").writeOutput(io, json_text, output_path);
}

pub fn handleMigrate(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);

    // Resolve new AST to TypedAst for migration generation
    var tr = typed_ast.TypeResolver.init(alloc);
    const new_typed = try tr.resolve(result.new_ast, dialect);

    if (trace) {
        traceResolvedAst("old", result.old_ast);
        traceResolvedAst("new", result.new_ast);
        traceSchemaDiff(result.schema_diff);
    }

    const migration_sql = try migrate.generateFromDiff(alloc, result.schema_diff, new_typed, result.new_ast, dialect);
    try @import("../io.zig").writeOutput(io, migration_sql, output_path);
}

pub fn handleMigrateJson(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect, trace: bool) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);

    if (trace) {
        traceResolvedAst("old", result.old_ast);
        traceResolvedAst("new", result.new_ast);
        traceSchemaDiff(result.schema_diff);
    }

    const json_text = try diff_format.formatDiffJson(alloc, result.schema_diff);
    try @import("../io.zig").writeOutput(io, json_text, output_path);
}

// ─── Trace Helpers ──────────────────────────────────────────────

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

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "diff: identical schemas produce no table diffs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io: std.Io = undefined;

    const ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(io, alloc, ss);
    const new_resolved = try pipeline_forward.compilePipeline(io, alloc, ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    try testing.expectEqual(@as(usize, 0), schema_diff.table_diffs.len);
    try testing.expectEqual(@as(usize, 0), schema_diff.dropped_tables.len);
}

test "diff: adding a table produces a create action" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io: std.Io = undefined;

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\
        \\# post
        \\
        \\id   n++
        \\title s
    ;
    const old_resolved = try pipeline_forward.compilePipeline(io, alloc, old_ss);
    const new_resolved = try pipeline_forward.compilePipeline(io, alloc, new_ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    try testing.expectEqual(@as(usize, 1), schema_diff.table_diffs.len);
    try testing.expectEqual(diff_types.TableAction.create, schema_diff.table_diffs[0].action);
    try testing.expectEqualStrings("post", schema_diff.table_diffs[0].name);
}

test "diff format json: produces valid JSON structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io: std.Io = undefined;

    const old_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
    ;
    const new_ss =
        \\$ demo
        \\
        \\# user
        \\
        \\id   n++
        \\name s
        \\
        \\# post
        \\
        \\id   n++
    ;
    const old_resolved = try pipeline_forward.compilePipeline(io, alloc, old_ss);
    const new_resolved = try pipeline_forward.compilePipeline(io, alloc, new_ss);
    const schema_diff = try diff.diff(old_resolved.resolved, new_resolved.resolved, alloc, .mysql);
    const json = try diff_format.formatDiffJson(alloc, schema_diff);

    try testing.expect(std.mem.indexOf(u8, json, "\"dropped_tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"table_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"view_diffs\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\": \"post\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"action\": \"create\"") != null);
}
