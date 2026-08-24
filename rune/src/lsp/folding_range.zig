const std = @import("std");
const protocol = @import("protocol.zig");
const FoldingRange = protocol.FoldingRange;
const FoldingRangeKind = protocol.FoldingRangeKind;

// ─── Folding Range ───────────────────────────────────────────
// Detects foldable regions in .ss files:
//   - Table blocks (# name { ... })
//   - Template blocks (% name ... until next top-level declaration)
//   - @if / @endif conditional blocks

/// Get folding ranges for the entire document.
pub fn getFoldingRanges(alloc: std.mem.Allocator, text: []const u8) ![]const FoldingRange {
    var ranges = try std.ArrayList(FoldingRange).initCapacity(alloc, 8);
    var block_stack = try std.ArrayList(BlockInfo).initCapacity(alloc, 8);
    defer block_stack.deinit(alloc);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: u32 = 0;
    var template_start: ?u32 = null;
    // Last line that had content — EOF regions end here, not at the
    // trailing-empty-line index a final newline produces.
    var last_content_line: u32 = 0;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");

        if (line.len == 0) {
            line_no += 1;
            continue;
        }
        last_content_line = line_no;

        const first_char = line[0];

        // Table block: # name { ... }  — or legacy/main brace-less form
        // `# name` + fields until the next top-level declaration.
        if (first_char == '#') {
            try closeTemplateBlock(alloc, &ranges, &template_start, line_no);
            // A new header closes any open brace-less table: the legacy form
            // has no closing brace, its region ends at the previous line.
            while (block_stack.items.len > 0) {
                const open = block_stack.items[block_stack.items.len - 1];
                if (open.kind != .table) break;
                if (line_no > open.start_line + 1) {
                    try ranges.append(alloc, .{
                        .start_line = open.start_line,
                        .end_line = line_no - 1,
                        .kind = .region,
                    });
                }
                _ = block_stack.pop();
            }
            try block_stack.append(alloc, .{
                .kind = .table,
                .start_line = line_no,
            });
        }

        // Template declaration: % name (folds until next top-level declaration)
        if (first_char == '%') {
            try closeTemplateBlock(alloc, &ranges, &template_start, line_no);
            template_start = line_no;
        }

        // Other top-level declarations close open template blocks
        if (first_char == '$' or first_char == '~' or first_char == '&' or first_char == '@') {
            try closeTemplateBlock(alloc, &ranges, &template_start, line_no);
        }

        // @if conditional block start
        if (line.len > 3 and std.mem.startsWith(u8, line, "@if(")) {
            try block_stack.append(alloc, .{
                .kind = .conditional,
                .start_line = line_no,
            });
        }

        // @endif — close conditional block
        if (std.mem.eql(u8, line, "@endif")) {
            if (block_stack.items.len > 0) {
                const last = block_stack.pop();
                if (last) |l| {
                    if (l.kind == .conditional) {
                        try ranges.append(alloc, .{
                            .start_line = l.start_line,
                            .end_line = line_no,
                            .kind = .region,
                        });
                    } else {
                        // Not a conditional block, put it back
                        try block_stack.append(alloc, l);
                    }
                }
            }
        }

        // End of table block: closing }
        if (first_char == '}') {
            if (block_stack.items.len > 0) {
                const last = block_stack.pop();
                if (last) |l| {
                    if (l.kind == .table) {
                        try ranges.append(alloc, .{
                            .start_line = l.start_line,
                            .end_line = line_no,
                            .kind = .region,
                        });
                    } else {
                        // Not a table block, put it back
                        try block_stack.append(alloc, l);
                    }
                }
            }
        }

        line_no += 1;
    }

    // Close brace-less blocks that ran to EOF: any open table/template block
    // without a closing `}` folds until the last content line. Without this,
    // the legacy/main `# name` + fields form produces no folding at all.
    for (block_stack.items) |open_block| {
        if (last_content_line > open_block.start_line) {
            try ranges.append(alloc, .{
                .start_line = open_block.start_line,
                .end_line = last_content_line,
                .kind = .region,
            });
        }
    }

    try closeTemplateBlock(alloc, &ranges, &template_start, last_content_line + 1);

    return try ranges.toOwnedSlice(alloc);
}

/// Emit a template region ending just before `at_line` and clear the marker.
fn closeTemplateBlock(alloc: std.mem.Allocator, ranges: *std.ArrayList(FoldingRange), template_start: *?u32, at_line: u32) !void {
    if (template_start.*) |ts| {
        if (at_line > ts + 1) {
            try ranges.append(alloc, .{
                .start_line = ts,
                .end_line = at_line - 1,
                .kind = .region,
            });
        }
        template_start.* = null;
    }
}

// ─── Internal Types ──────────────────────────────────────────

const BlockKind = enum {
    table,
    conditional,
};

const BlockInfo = struct {
    kind: BlockKind,
    start_line: u32,
};
