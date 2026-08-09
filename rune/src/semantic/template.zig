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
                fields = try applyTemplate(alloc, t, parent_fields, tmpl_slot);
            }
        } else if (default_tmpl) |dt| {
            const dname = dt.name orelse "";
            if (resolved.get(dname)) |parent_fields| {
                fields = try applyTemplate(alloc, t, parent_fields, dt.slot_index);
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
            .conditional_blocks = t.conditional_blocks,
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
    if (table.fields.len == 0) return template_fields;

    var table_slot: ?usize = null;
    for (table.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "...")) {
            table_slot = i;
            break;
        }
    }

    var table_names = std.StringHashMap(void).init(alloc);
    for (table.fields) |f| try table_names.put(f.name, {});

    if (table_slot) |slot| {
        const table_before = table.fields[0..slot];
        const table_after = table.fields[slot + 1 ..];

        var result = try std.ArrayList(Field).initCapacity(alloc, 8);
        for (table_before) |f| try result.append(alloc, f);
        for (template_fields) |f| {
            if (!table_names.contains(f.name)) try result.append(alloc, f);
        }
        for (table_after) |f| try result.append(alloc, f);
        return try result.toOwnedSlice(alloc);
    } else {
        const insert_pos = template_slot orelse template_fields.len;
        var result = try std.ArrayList(Field).initCapacity(alloc, 8);
        for (template_fields[0..insert_pos]) |f| {
            if (!std.mem.eql(u8, f.name, "...") and !table_names.contains(f.name)) try result.append(alloc, f);
        }
        for (table.fields) |f| try result.append(alloc, f);
        if (insert_pos < template_fields.len) {
            for (template_fields[insert_pos..]) |f| {
                if (!std.mem.eql(u8, f.name, "...") and !table_names.contains(f.name)) try result.append(alloc, f);
            }
        }
        return try result.toOwnedSlice(alloc);
    }
}
