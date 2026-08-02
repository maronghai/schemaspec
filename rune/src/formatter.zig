const std = @import("std");

// ─── SS Formatter ─────────────────────────────────────────────
// Auto-formats .ss files with consistent style:
//   - Strip trailing whitespace
//   - 2-space indentation for fields inside tables/templates
//   - Single blank line between blocks
//   - No trailing blank lines

/// Pre-allocation padding to avoid repeated reallocations for small inputs.
const INITIAL_PADDING = 64;

pub fn format(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, input.len + INITIAL_PADDING);
    var lines = std.mem.splitScalar(u8, input, '\n');
    var in_block = false; // inside a table or template
    var prev_blank = false;
    var first_line = true;

    while (lines.next()) |raw_line| {
        // Strip trailing whitespace
        const line = std.mem.trim(u8, raw_line, " \t\r");

        if (line.len == 0) {
            // Blank line: collapse consecutive blanks, skip at start
            if (!first_line and !prev_blank) {
                prev_blank = true;
                // Don't emit yet — wait for next non-blank to decide
            }
            continue;
        }

        // Non-blank line
        first_line = false;

        // Emit deferred blank line
        if (prev_blank) {
            try result.append(alloc, '\n');
            prev_blank = false;
        }

        const first_char = line[0];

        // Detect block boundaries
        switch (first_char) {
            '#', '~' => {
                // Table or template header — start block
                in_block = true;
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
            '$', '!' => {
                // Schema declaration or end marker — end block
                in_block = false;
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
            ';' => {
                // Comment — no indentation change
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
            '@', '(' => {
                // Index — inside block, indented
                if (in_block) {
                    try result.appendSlice(alloc, "  ");
                }
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
            ')' => {
                // End inline index
                if (in_block) {
                    try result.appendSlice(alloc, "  ");
                }
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
            else => {
                // Field definition — indented inside block
                if (in_block) {
                    try result.appendSlice(alloc, "  ");
                }
                try result.appendSlice(alloc, line);
                try result.append(alloc, '\n');
            },
        }
    }

    // Trim trailing blank lines
    while (result.items.len > 0 and result.items[result.items.len - 1] == '\n') {
        result.items.len -= 1;
    }
    try result.append(alloc, '\n');

    return try result.toOwnedSlice(alloc);
}
