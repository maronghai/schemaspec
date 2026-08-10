const std = @import("std");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const Field = ast_mod.Field;
const Template = ast_mod.Template;
const SourceLocation = ast_mod.SourceLocation;
const locFromLine = @import("loc.zig").locFromLine;

// ─── Template Parsing ─────────────────────────────────────────
// Extracted from parser.zig for single-responsibility.
// Handles: template header parsing, slot detection, flush logic.

pub const TemplateHeader = struct {
    name: ?[]const u8,
    parents: []const []const u8,
    line_no: usize,
    loc: ?SourceLocation,
};

/// Parse a template header line (% name > parent1 + parent2).
pub fn parseTemplateHeader(alloc: std.mem.Allocator, line: tk.Line) !TemplateHeader {
    var name: ?[]const u8 = null;
    // Use stack-allocated buffer for parent names (max 4 parents).
    // Copy results to allocator for long-term storage.
    var parents_buf: [4][]const u8 = .{ "", "", "", "" };
    var parents_len: usize = 0;
    if (line.tokens.len >= 2) {
        if (!std.mem.eql(u8, line.tokens[1], ">") and !std.mem.eql(u8, line.tokens[1], "+")) {
            name = try alloc.dupe(u8, line.tokens[1]);
        }
    }
    // Collect parents: after name or after > keyword
    var start_idx: usize = 0;
    var found_keyword = false;
    for (line.tokens, 0..) |tok, i| {
        if (std.mem.eql(u8, tok, ">")) {
            start_idx = i + 1;
            found_keyword = true;
            break;
        }
    }
    // If no > found, parents start after the % and name tokens
    if (!found_keyword) {
        start_idx = if (name != null) 2 else 1;
    }
    var i: usize = start_idx;
    while (i < line.tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, line.tokens[i], "+")) {
            if (parents_len < parents_buf.len) {
                parents_buf[parents_len] = try alloc.dupe(u8, line.tokens[i]);
                parents_len += 1;
            }
        }
    }
    // Copy to allocated slice for long-term storage
    const result = try alloc.alloc([]const u8, parents_len);
    for (result, 0..) |*r, idx| {
        r.* = parents_buf[idx];
    }
    return .{
        .name = name,
        .parents = result,
        .line_no = line.line_no,
        .loc = locFromLine(line, line.tokens[0]),
    };
}

/// Find the slot marker ("...") index in a field list.
pub fn findSlot(fields: []const Field) ?usize {
    for (fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "...")) return i;
    }
    return null;
}

/// Flush a template block into the templates list.
pub fn flushTemplate(
    alloc: std.mem.Allocator,
    templates: *std.ArrayList(Template),
    name: ?[]const u8,
    parents_buf: []const []const u8,
    parents_len: usize,
    fields: *std.ArrayList(Field),
    doc: ?[]const u8,
    line_no: usize,
    loc: ?SourceLocation,
) !void {
    const slot_idx = findSlot(fields.items);
    // Allocate and copy parents to ensure they outlive the stack buffer.
    const parents = if (parents_len > 0) blk: {
        const result = try alloc.alloc([]const u8, parents_len);
        for (result, 0..) |*r, idx| {
            r.* = try alloc.dupe(u8, parents_buf[idx]);
        }
        break :blk result;
    } else &.{};
    try templates.append(alloc, .{
        .name = name,
        .parents = parents,
        .doc = doc,
        .fields = try fields.toOwnedSlice(alloc),
        .slot_index = slot_idx,
        .line_no = line_no,
        .loc = loc,
    });
}
