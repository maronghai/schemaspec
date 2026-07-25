const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
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

pub fn handleDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, dialect: codegen.Dialect) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);
    const diff_text = try diff.formatDiff(alloc, result.schema_diff, dialect);
    try @import("../io.zig").writeOutput(io, diff_text, null);
}

pub fn handleMigrate(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8, output_path: ?[]const u8, dialect: codegen.Dialect) !void {
    const result = try prepareDiff(io, alloc, old_path, new_path, dialect);

    // Resolve new AST to TypedAst for migration generation
    var tr = typed_ast.TypeResolver.init(alloc);
    const new_typed = try tr.resolve(result.new_ast, dialect);

    const migration_sql = try migrate.generateFromDiff(alloc, result.schema_diff, new_typed, result.new_ast, dialect);
    try @import("../io.zig").writeOutput(io, migration_sql, output_path);
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
