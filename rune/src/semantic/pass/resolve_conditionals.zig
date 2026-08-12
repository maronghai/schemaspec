const std = @import("std");
const pass_manager = @import("../pass_manager.zig");
const PassContext = pass_manager.PassContext;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const Field = @import("../../types/ast.zig").Field;
const ConditionalBlock = @import("../../types/ast.zig").ConditionalBlock;
const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");
const diag_mod = @import("../../diagnostic.zig");

// ─── Resolve Conditional Blocks ───────────────────────────────
// Filters fields in @if(dialect=...) blocks based on the target dialect.
// Fields within a conditional block are only included when the target dialect
// matches one of the block's dialects. Fields outside conditional blocks
// are always included.

pub fn run(ctx: *PassContext) !void {
    const target_dialect = ctx.dialect;
    const target_name = @tagName(target_dialect);

    var i: usize = 0;
    while (i < ctx.tables.items.len) : (i += 1) {
        const table = &ctx.tables.items[i];
        if (table.conditional_blocks.len == 0) continue;

        // Collect fields to keep (non-conditional + matching conditional)
        var kept = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len);

        var field_idx: usize = 0;
        while (field_idx < table.fields.len) {
            // Check if this field is inside a conditional block
            var in_conditional = false;
            var should_keep = true;
            for (table.conditional_blocks) |block| {
                if (field_idx >= block.start_field and field_idx < block.end_field) {
                    in_conditional = true;
                    // Check if any of the block's dialects match the target
                    should_keep = false;
                    for (block.dialects) |dialect_name| {
                        if (std.mem.eql(u8, dialect_name, target_name)) {
                            should_keep = true;
                            break;
                        }
                    }
                    break;
                }
            }

            if (!in_conditional or should_keep) {
                try kept.append(ctx.alloc, table.fields[field_idx]);
            }
            field_idx += 1;
        }

        // Replace fields with filtered version
        table.fields = try kept.toOwnedSlice(ctx.alloc);
    }
}

// ─── Tests ──────────────────────────────────────────────────

fn makeTestField(name: []const u8) Field {
    return .{
        .name = name,
        .type_info = .{ .simple = "n" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

test "resolve_conditionals: no conditional blocks keeps all fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);

    var fields = try std.ArrayList(Field).initCapacity(alloc, 2);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("name"));

    const table = ResolvedTable{
        .name = "users",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = &.{},
        .line_no = 1,
    };
    try tables.append(alloc, table);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .pg;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 2), ctx.tables.items[0].fields.len);
}

test "resolve_conditionals: matching dialect keeps conditional field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);

    var fields = try std.ArrayList(Field).initCapacity(alloc, 2);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("pg_only"));

    const blocks = try alloc.alloc(ConditionalBlock, 1);
    blocks[0] = .{
        .dialects = &.{"pg"},
        .start_field = 1,
        .end_field = 2,
        .line_no = 1,
    };

    const table = ResolvedTable{
        .name = "users",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = blocks,
        .line_no = 1,
    };
    try tables.append(alloc, table);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .pg;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 2), ctx.tables.items[0].fields.len);
    try testing.expectEqualStrings("pg_only", ctx.tables.items[0].fields[1].name);
}

test "resolve_conditionals: non-matching dialect removes conditional field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);

    var fields = try std.ArrayList(Field).initCapacity(alloc, 2);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("pg_only"));

    const blocks = try alloc.alloc(ConditionalBlock, 1);
    blocks[0] = .{
        .dialects = &.{"pg"},
        .start_field = 1,
        .end_field = 2,
        .line_no = 1,
    };

    const table = ResolvedTable{
        .name = "users",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = blocks,
        .line_no = 1,
    };
    try tables.append(alloc, table);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .mysql;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 1), ctx.tables.items[0].fields.len);
    try testing.expectEqualStrings("id", ctx.tables.items[0].fields[0].name);
}

test "resolve_conditionals: multiple dialects in block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);

    var fields = try std.ArrayList(Field).initCapacity(alloc, 2);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("multi_dialect"));

    const dialects = try alloc.alloc([]const u8, 2);
    dialects[0] = "pg";
    dialects[1] = "sqlite";

    const blocks = try alloc.alloc(ConditionalBlock, 1);
    blocks[0] = .{
        .dialects = dialects,
        .start_field = 1,
        .end_field = 2,
        .line_no = 1,
    };

    const table = ResolvedTable{
        .name = "users",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = blocks,
        .line_no = 1,
    };
    try tables.append(alloc, table);

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .sqlite;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 2), ctx.tables.items[0].fields.len);
}
