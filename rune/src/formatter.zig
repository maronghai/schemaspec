const std = @import("std");

// ─── SS Formatter ─────────────────────────────────────────────
// Auto-formats .ss files with consistent style:
//   - Strip trailing whitespace
//   - 2-space indentation for fields inside tables/templates
//   - Single blank line between blocks
//   - No trailing blank lines

pub fn format(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, input.len + 64);
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
            if (in_block) {
                try result.append(alloc, '\n');
            } else {
                try result.append(alloc, '\n');
            }
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

// ─── Tests ─────────────────────────────────────────────────────

test "formatter: strips trailing whitespace" {
    const alloc = std.testing.allocator;
    const input = "id  n++   \nname  s64   \n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("id  n++\nname  s64\n", result);
}

test "formatter: indents fields inside table" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\nname s64\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n  name s64\n", result);
}

test "formatter: collapses consecutive blank lines" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\n\n\nname s64\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n\n  name s64\n", result);
}

test "formatter: no trailing blank lines" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\n\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n", result);
}

test "formatter: empty input" {
    const alloc = std.testing.allocator;
    const result = try format(alloc, "");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("\n", result);
}

test "formatter: comments not indented" {
    const alloc = std.testing.allocator;
    const input = "; comment\n# users\n; another\nid n++\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("; comment\n# users\n; another\n  id n++\n", result);
}

test "formatter: schema declaration not indented" {
    const alloc = std.testing.allocator;
    const input = "$ mydb\n# users\nid n++\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("$ mydb\n# users\n  id n++\n", result);
}

test "formatter: index indented" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\nname s64\n@ name\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n  name s64\n  @ name\n", result);
}

test "formatter: template indented" {
    const alloc = std.testing.allocator;
    const input = "~ base\nid n++\ncreated_at t\n# users\n...\nname s64\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("~ base\n  id n++\n  created_at t\n# users\n  ...\n  name s64\n", result);
}

test "formatter: full example" {
    const alloc = std.testing.allocator;
    const input = "$ mydb\n\n\n; Users table\n# users\nid       n++\nemail    s128 *\nname     s64\n\n\n; Posts table\n# posts\nid         n++\ntitle      s256 *\nauthor_id  n *\n@ author_id\n";
    const result = try format(alloc, input);
    defer alloc.free(result);
    const expected = "$ mydb\n\n; Users table\n# users\n  id       n++\n  email    s128 *\n  name     s64\n\n; Posts table\n# posts\n  id         n++\n  title      s256 *\n  author_id  n *\n  @ author_id\n";
    try std.testing.expectEqualStrings(expected, result);
}
