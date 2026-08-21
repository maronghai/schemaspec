const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const Ast = ast_mod.Ast;
const Template = ast_mod.Template;
const Table = ast_mod.Table;
const Field = ast_mod.Field;
const ResolvedTable = resolved_ast.ResolvedTable;

// ─── Template Resolution & Application ──────────────────────────
//
// Extracted from semantic.zig for single-responsibility.
// Handles: template map building, circular inheritance detection,
// slot-based field merging, multi-parent (mixin) inheritance.

/// Resolve all templates in the AST and apply them to tables.
/// Returns the resolved tables with template fields merged.
pub fn resolveAndApply(
    alloc: std.mem.Allocator,
    tree: Ast,
) ![]const ResolvedTable {
    // Build template map
    var tmpl_map = std.StringHashMap(*const Template).init(alloc);
    for (tree.templates) |*t| {
        try tmpl_map.put(t.name orelse "", t);
    }
    var default_tmpl: ?*const Template = null;
    for (tree.templates) |*t| {
        if (t.name == null) default_tmpl = t;
    }

    // Template resolution (needs tree access)
    var resolved = std.StringHashMap([]const Field).init(alloc);
    var resolving = std.StringHashMap(bool).init(alloc);
    for (tree.templates) |*t| {
        const tname = t.name orelse "";
        if (!resolved.contains(tname)) {
            _ = try resolveTemplate(t, &tmpl_map, &resolved, &resolving);
        }
    }

    // Build initial tables with templates applied
    var tables = try std.ArrayList(ResolvedTable).initCapacity(alloc, 8);
    for (tree.tables) |*t| {
        var fields: []const Field = t.fields;
        var origin: []const ?usize = &.{};
        var tmpl_slot: ?usize = null;
        if (t.template_ref) |tref| {
            if (resolved.get(tref)) |parent_fields| {
                for (tree.templates) |*tmpl| {
                    if (tmpl.name) |tn| {
                        if (std.mem.eql(u8, tn, tref)) {
                            tmpl_slot = tmpl.slot_index;
                            break;
                        }
                    }
                }
                const merged = try applyTemplateWithOrigin(alloc, t, parent_fields, tmpl_slot);
                fields = merged.fields;
                origin = merged.origin;
            }
        } else if (default_tmpl) |dt| {
            const dname = dt.name orelse "";
            if (resolved.get(dname)) |parent_fields| {
                const merged = try applyTemplateWithOrigin(alloc, t, parent_fields, dt.slot_index);
                fields = merged.fields;
                origin = merged.origin;
            }
        }
        try tables.append(alloc, .{
            .name = t.name,
            .comment = t.comment,
            .doc = t.doc,
            .engine = t.engine,
            .fields = try alloc.dupe(Field, fields),
            .fks = t.fks,
            .indexes = t.indexes,
            // Conditional-block indices refer to the pre-merge field list —
            // remap them so @if ranges survive template field insertion.
            .conditional_blocks = remapConditionalBlocks(alloc, t.conditional_blocks, origin),
            .embeds = t.embeds,
            .line_no = t.line_no,
            .template_ref = t.template_ref,
        });
    }

    return try tables.toOwnedSlice(alloc);
}

/// Build the template name→pointer map for external use (e.g. validation pass).
pub fn buildTemplateMap(
    alloc: std.mem.Allocator,
    templates: []const Template,
) !std.StringHashMap(*const Template) {
    var tmpl_map = std.StringHashMap(*const Template).init(alloc);
    for (templates) |*t| {
        try tmpl_map.put(t.name orelse "", t);
    }
    return tmpl_map;
}

// ─── Internal Helpers ──────────────────────────────────────────

fn resolveTemplate(
    tmpl: *const Template,
    tmpl_map: *const std.StringHashMap(*const Template),
    resolved: *std.StringHashMap([]const Field),
    resolving: *std.StringHashMap(bool),
) ![]const Field {
    const tname = tmpl.name orelse "";
    if (resolved.get(tname)) |f| return f;

    if (resolving.contains(tname)) return error.CircularTemplateInheritance;
    try resolving.put(tname, true);
    defer _ = resolving.remove(tname);

    var base_fields: []const Field = &.{};
    for (tmpl.parents) |parent_name| {
        if (tmpl_map.get(parent_name)) |parent| {
            const parent_fields = try resolveTemplate(parent, tmpl_map, resolved, resolving);
            base_fields = try mergeFields(resolved.allocator, base_fields, parent_fields, &.{}, null);
        }
    }

    const result = try mergeFields(resolved.allocator, base_fields, tmpl.fields, &.{}, tmpl.slot_index);
    try resolved.put(tname, result);
    return result;
}

fn mergeFields(
    alloc: std.mem.Allocator,
    parent_fields: []const Field,
    child_fields: []const Field,
    concrete_fields: []const Field,
    child_slot: ?usize,
) ![]const Field {
    if (parent_fields.len == 0) return child_fields;

    var parent_slot: ?usize = null;
    for (parent_fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "...")) {
            parent_slot = i;
            break;
        }
    }

    const pslot = parent_slot orelse parent_fields.len;
    const cslot_raw = child_slot orelse pslot;
    const cslot = if (cslot_raw > child_fields.len) child_fields.len else cslot_raw;

    const parent_before = parent_fields[0..pslot];
    const parent_after = if (pslot < parent_fields.len) parent_fields[pslot + 1 ..] else &[_]Field{};
    const child_before = child_fields[0..cslot];
    const child_after = if (cslot < child_fields.len) child_fields[cslot + 1 ..] else &[_]Field{};

    var override_names = std.StringHashMap(void).init(alloc);
    for (child_before) |f| try override_names.put(f.name, {});
    for (child_after) |f| try override_names.put(f.name, {});
    for (concrete_fields) |f| try override_names.put(f.name, {});

    var result = try std.ArrayList(Field).initCapacity(alloc, 8);

    for (parent_before) |f| {
        if (!override_names.contains(f.name)) try result.append(alloc, f);
    }
    for (child_before) |f| try result.append(alloc, f);
    for (concrete_fields) |f| try result.append(alloc, f);
    for (child_after) |f| try result.append(alloc, f);
    for (parent_after) |f| {
        if (!override_names.contains(f.name)) try result.append(alloc, f);
    }

    return try result.toOwnedSlice(alloc);
}

fn applyTemplate(
    alloc: std.mem.Allocator,
    table: *const Table,
    template_fields: []const Field,
    template_slot: ?usize,
) ![]const Field {
    const merged = try applyTemplateWithOrigin(alloc, table, template_fields, template_slot);
    return merged.fields;
}

/// Merged fields plus, for each merged position, the index into the table's
/// original field list it came from (null = inserted from the template).
/// Used to remap conditional-block field indices after merging.
const MergedWithOrigin = struct {
    fields: []const Field,
    origin: []const ?usize,
};

fn applyTemplateWithOrigin(
    alloc: std.mem.Allocator,
    table: *const Table,
    template_fields: []const Field,
    template_slot: ?usize,
) !MergedWithOrigin {
    if (table.fields.len == 0) {
        return .{ .fields = template_fields, .origin = &.{} };
    }

    var table_slot: ?usize = null;
    for (table.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "...")) {
            table_slot = i;
            break;
        }
    }

    var table_names = std.StringHashMap(void).init(alloc);
    for (table.fields) |f| try table_names.put(f.name, {});

    var result = try std.ArrayList(Field).initCapacity(alloc, 8);
    var origin = try std.ArrayList(?usize).initCapacity(alloc, 8);

    if (table_slot) |slot| {
        const table_before = table.fields[0..slot];
        const table_after = table.fields[slot + 1 ..];

        for (table_before, 0..) |f, i| {
            try result.append(alloc, f);
            try origin.append(alloc, i);
        }
        for (template_fields) |f| {
            if (!table_names.contains(f.name)) {
                try result.append(alloc, f);
                try origin.append(alloc, null);
            }
        }
        for (table_after, 0..) |f, i| {
            const idx = slot + 1 + i;
            try result.append(alloc, f);
            try origin.append(alloc, idx);
        }
    } else {
        const insert_pos = template_slot orelse template_fields.len;
        for (template_fields[0..insert_pos]) |f| {
            if (!std.mem.eql(u8, f.name, "...") and !table_names.contains(f.name)) {
                try result.append(alloc, f);
                try origin.append(alloc, null);
            }
        }
        for (table.fields, 0..) |f, i| {
            try result.append(alloc, f);
            try origin.append(alloc, i);
        }
        if (insert_pos < template_fields.len) {
            for (template_fields[insert_pos..]) |f| {
                if (!std.mem.eql(u8, f.name, "...") and !table_names.contains(f.name)) {
                    try result.append(alloc, f);
                    try origin.append(alloc, null);
                }
            }
        }
    }
    return .{
        .fields = try result.toOwnedSlice(alloc),
        .origin = try origin.toOwnedSlice(alloc),
    };
}

/// Remap a table's conditional-block field indices from the original
/// (pre-merge) field positions to the merged field positions.
/// A block whose range collapses to zero fields is dropped.
fn remapConditionalBlocks(
    alloc: std.mem.Allocator,
    blocks: []const ast_mod.ConditionalBlock,
    origin: []const ?usize,
) []const ast_mod.ConditionalBlock {
    if (blocks.len == 0 or origin.len == 0) return blocks;

    var out = std.ArrayList(ast_mod.ConditionalBlock).initCapacity(alloc, blocks.len) catch return blocks;
    for (blocks) |block| {
        var new_start: ?usize = null;
        var new_end: usize = 0;
        for (origin, 0..) |o, j| {
            const oi = o orelse continue;
            if (oi >= block.start_field and oi < block.end_field) {
                if (new_start == null) new_start = j;
                new_end = j + 1;
            }
        }
        // Drop the block when none of its fields survived the merge.
        if (new_start == null or new_start.? >= new_end) continue;
        out.append(alloc, .{
            .dialects = block.dialects,
            .start_field = new_start.?,
            .end_field = new_end,
            .line_no = block.line_no,
        }) catch continue;
    }
    return out.toOwnedSlice(alloc) catch blocks;
}

// ─── Unit Tests ─────────────────────────────────────────────

const testing = std.testing;

fn makeField(name: []const u8) ast_mod.Field {
    return .{
        .name = name,
        .type_info = .{ .simple = "s" },
        .modifiers = &.{},
        .default_val = null,
        .check = null,
        .fk = null,
        .comment = null,
        .line_no = 1,
    };
}

fn makeTable(name: []const u8, field_names: []const []const u8) Table {
    const fields = std.heap.page_allocator.alloc(Field, field_names.len) catch unreachable;
    for (field_names, 0..) |n, i| fields[i] = makeField(n);
    return .{
        .template_ref = null,
        .name = name,
        .comment = null,
        .engine = null,
        .fields = fields,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

fn makeTemplate(name: []const u8, field_names: []const []const u8) Template {
    const fields = std.heap.page_allocator.alloc(Field, field_names.len) catch unreachable;
    for (field_names, 0..) |n, i| fields[i] = makeField(n);
    return .{
        .name = name,
        .parents = &.{},
        .fields = fields,
        .slot_index = null,
        .line_no = 1,
    };
}

test "remapConditionalBlocks: template inserts before block shifts indices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Original: [name(0), bio(1)] with block covering bio at [1,2).
    // Merge prepends template's id → merged [id, name, bio]; bio moves to 2.
    const origin = [_]?usize{ null, 0, 1 };
    const blocks = [_]ast_mod.ConditionalBlock{
        .{ .dialects = &.{"pg"}, .start_field = 1, .end_field = 2, .line_no = 3 },
    };
    const remapped = remapConditionalBlocks(alloc, &blocks, &origin);
    try testing.expectEqual(@as(usize, 1), remapped.len);
    try testing.expectEqual(@as(usize, 2), remapped[0].start_field);
    try testing.expectEqual(@as(usize, 3), remapped[0].end_field);
}

test "remapConditionalBlocks: template insertion after block keeps range" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Original: [bio(0), name(1)], block covers bio [0,1).
    // Merge appends template's id after slot → merged [bio, name, id].
    const origin = [_]?usize{ 0, 1, null };
    const blocks = [_]ast_mod.ConditionalBlock{
        .{ .dialects = &.{"pg"}, .start_field = 0, .end_field = 1, .line_no = 2 },
    };
    const remapped = remapConditionalBlocks(alloc, &blocks, &origin);
    try testing.expectEqual(@as(usize, 1), remapped.len);
    try testing.expectEqual(@as(usize, 0), remapped[0].start_field);
    try testing.expectEqual(@as(usize, 1), remapped[0].end_field);
}

test "remapConditionalBlocks: multi-field block spanning inserted fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Original: [a(0), b(1), c(2)] block covers [b, c] = [1,3).
    // Merge: template x before a, y between a and b → [x, a, y, b, c].
    const origin = [_]?usize{ null, 0, null, 1, 2 };
    const blocks = [_]ast_mod.ConditionalBlock{
        .{ .dialects = &.{"pg"}, .start_field = 1, .end_field = 3, .line_no = 4 },
    };
    const remapped = remapConditionalBlocks(alloc, &blocks, &origin);
    try testing.expectEqual(@as(usize, 1), remapped.len);
    try testing.expectEqual(@as(usize, 3), remapped[0].start_field);
    try testing.expectEqual(@as(usize, 5), remapped[0].end_field);
}

test "remapConditionalBlocks: fully dropped block is removed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Original block covered only a template-shadowed field that the merge
    // replaced (its origin index vanished). Origin has no entry in [0,1).
    const origin = [_]?usize{ null, 1 };
    const blocks = [_]ast_mod.ConditionalBlock{
        .{ .dialects = &.{"pg"}, .start_field = 0, .end_field = 1, .line_no = 1 },
    };
    const remapped = remapConditionalBlocks(alloc, &blocks, &origin);
    try testing.expectEqual(@as(usize, 0), remapped.len);
}

test "resolveAndApply end-to-end: @if survives template merge" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // % base: id + slot; table adds name, then an @if block around bio.
    // Merged order must be [id, name, bio] with the block remapped to [2,3).
    const base_tmpl = try alloc.create(Template);
    base_tmpl.* = makeTemplate("base", &.{ "id", "..." });
    base_tmpl.slot_index = 1;

    const tables = try alloc.alloc(Table, 1);
    tables[0] = makeTable("users", &.{ "name", "bio" });
    const blocks = try alloc.alloc(ast_mod.ConditionalBlock, 1);
    blocks[0] = .{ .dialects = &.{"pg"}, .start_field = 1, .end_field = 2, .line_no = 4 };
    tables[0].template_ref = "base";
    tables[0].conditional_blocks = blocks;

    const templates = try alloc.alloc(Template, 1);
    templates[0] = base_tmpl.*;

    const tree = ast_mod.Ast{
        .schema = null,
        .templates = templates,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };

    const resolved = try resolveAndApply(alloc, tree);
    try testing.expectEqual(@as(usize, 1), resolved.len);
    const t = resolved[0];
    try testing.expectEqual(@as(usize, 3), t.fields.len);
    try testing.expectEqualStrings("id", t.fields[0].name);
    try testing.expectEqualStrings("name", t.fields[1].name);
    try testing.expectEqualStrings("bio", t.fields[2].name);
    try testing.expectEqual(@as(usize, 1), t.conditional_blocks.len);
    try testing.expectEqual(@as(usize, 2), t.conditional_blocks[0].start_field);
    try testing.expectEqual(@as(usize, 3), t.conditional_blocks[0].end_field);
}
