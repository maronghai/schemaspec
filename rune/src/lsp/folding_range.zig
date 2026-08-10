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

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");

        if (line.len == 0) {
            line_no += 1;
            continue;
        }

        const first_char = line[0];

        // Table block: # name { ... }
        if (first_char == '#') {
            // Close any open template block
            if (template_start) |ts| {
                if (line_no > ts + 1) {
                    try ranges.append(alloc, .{
                        .start_line = ts,
                        .end_line = line_no - 1,
                        .kind = .region,
                    });
                }
                template_start = null;
            }
            try block_stack.append(alloc, .{
                .kind = .table,
                .start_line = line_no,
            });
        }

        // Template declaration: % name (folds until next top-level declaration)
        if (first_char == '%') {
            // Close any open template block
            if (template_start) |ts| {
                if (line_no > ts + 1) {
                    try ranges.append(alloc, .{
                        .start_line = ts,
                        .end_line = line_no - 1,
                        .kind = .region,
                    });
                }
            }
            template_start = line_no;
        }

        // Other top-level declarations close open template blocks
        if (first_char == '$' or first_char == '~' or first_char == '&' or first_char == '@') {
            if (template_start) |ts| {
                if (line_no > ts + 1) {
                    try ranges.append(alloc, .{
                        .start_line = ts,
                        .end_line = line_no - 1,
                        .kind = .region,
                    });
                }
                template_start = null;
            }
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

    // Close any remaining template block at end of file
    if (template_start) |ts| {
        if (line_no > ts + 1) {
            try ranges.append(alloc, .{
                .start_line = ts,
                .end_line = line_no - 1,
                .kind = .region,
            });
        }
    }

    return try ranges.toOwnedSlice(alloc);
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
