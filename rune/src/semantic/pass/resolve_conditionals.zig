const std = @import("std");
const pass_manager = @import("../pass_manager.zig");
const PassContext = pass_manager.PassContext;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../../types/ast.zig");
const Field = ast_mod.Field;
const ConditionalBlock = ast_mod.ConditionalBlock;
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

        // Collect fields to keep (non-conditional + matching conditional),
        // tracking each kept field's original index so embed insert
        // positions can be remapped to the filtered list.
        var kept = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len);
        var kept_orig = try std.ArrayList(usize).initCapacity(ctx.alloc, table.fields.len);

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
                try kept_orig.append(ctx.alloc, field_idx);
            }
            field_idx += 1;
        }

        // Embed positions refer to the pre-filter list — shift them to the
        // first surviving original field at or after the old position (or to
        // the end when all such fields were stripped).
        if (table.embeds.len > 0) {
            const embeds = try ctx.alloc.dupe(ast_mod.CompositeEmbed, table.embeds);
            for (embeds) |*embed| {
                var new_pos: ?usize = null;
                for (kept_orig.items, 0..) |orig, j| {
                    if (orig >= embed.insert_pos) {
                        new_pos = j;
                        break;
                    }
                }
                embed.insert_pos = new_pos orelse kept.items.len;
            }
            table.embeds = embeds;
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

fn makeEmbedTable(alloc: std.mem.Allocator, embed_pos: usize) !ResolvedTable {
    var fields = try std.ArrayList(Field).initCapacity(alloc, 3);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("mysql_only"));
    try fields.append(alloc, makeTestField("name"));

    const blocks = try alloc.alloc(ConditionalBlock, 1);
    blocks[0] = .{
        .dialects = &.{"mysql"},
        .start_field = 1,
        .end_field = 2,
        .line_no = 2,
    };

    const embeds = try alloc.alloc(ast_mod.CompositeEmbed, 1);
    embeds[0] = .{ .name = "audit", .insert_pos = embed_pos, .line_no = 5 };

    return .{
        .name = "orders",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = blocks,
        .embeds = embeds,
        .line_no = 3,
    };
}

test "resolve_conditionals: stripped field before embed shifts insert position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Embed at pos 2 (after id + strippable mysql_only). Compiling for pg
    // strips mysql_only → the embed must move from 2 to 1 (before name).
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, try makeEmbedTable(alloc, 2));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .pg;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 2), ctx.tables.items[0].fields.len);
    try testing.expectEqual(@as(usize, 1), ctx.tables.items[0].embeds[0].insert_pos);
}

test "resolve_conditionals: kept field after embed keeps position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Embed at pos 1 (between id and mysql_only); compiling for mysql keeps
    // everything — position must be unchanged.
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, try makeEmbedTable(alloc, 1));

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .mysql;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 3), ctx.tables.items[0].fields.len);
    try testing.expectEqual(@as(usize, 1), ctx.tables.items[0].embeds[0].insert_pos);
}

test "resolve_conditionals: all fields after embed stripped moves it to end" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Embed at pos 1; only fields [1,3) are conditional and both get
    // stripped for pg... except `name` is outside the block here — so use a
    // table where everything after the embed is inside the block.
    var fields = try std.ArrayList(Field).initCapacity(alloc, 2);
    try fields.append(alloc, makeTestField("id"));
    try fields.append(alloc, makeTestField("mysql_only"));

    const blocks = try alloc.alloc(ConditionalBlock, 1);
    blocks[0] = .{ .dialects = &.{"mysql"}, .start_field = 1, .end_field = 2, .line_no = 2 };

    const embeds = try alloc.alloc(ast_mod.CompositeEmbed, 1);
    embeds[0] = .{ .name = "audit", .insert_pos = 2, .line_no = 4 };

    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 1);
    try tables.append(alloc, .{
        .name = "orders",
        .fields = try fields.toOwnedSlice(alloc),
        .template_ref = null,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .doc = null,
        .engine = null,
        .conditional_blocks = blocks,
        .embeds = embeds,
        .line_no = 3,
    });

    var diagnostics = try diag_mod.DiagnosticCollector.init(alloc);
    var ctx = test_helpers.makePassCtx(alloc, &tables, &diagnostics, .{});
    ctx.dialect = .pg;

    try run(&ctx);
    try testing.expectEqual(@as(usize, 1), ctx.tables.items[0].fields.len);
    // Nothing survived at or after pos 2 → end of the filtered list.
    try testing.expectEqual(@as(usize, 1), ctx.tables.items[0].embeds[0].insert_pos);
}
