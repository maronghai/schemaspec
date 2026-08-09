const std = @import("std");

// ─── SS Formatter ─────────────────────────────────────────────
// Auto-formats .ss files with consistent style:
//   - Strip trailing whitespace
//   - 2-space indentation for fields inside tables/templates
//   - Single blank line between blocks
//   - No trailing blank lines
//   - @if/@endif at root level (not indented)
//   - + doc directives indented at field level

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

        // Detect block boundaries and special constructs
        if (first_char == '#' or first_char == '~') {
            // Table or template header — end any previous block, start new block
            in_block = true;
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if (first_char == '$' or first_char == '!') {
            // Schema declaration or end marker — end block
            in_block = false;
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if ((line.len >= 3 and std.mem.startsWith(u8, line, "@if") and (line.len == 3 or line[3] == '(')) or std.mem.eql(u8, line, "@endif")) {
            // @if(...) / @endif — conditional block control flow, always at root level
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if (first_char == ';' or first_char == '@' or first_char == '(' or first_char == ')') {
            // Comment, index, or inline index — inside block, indented
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if (first_char == '+' and line.len >= 2) {
            // Doc directive (+ ...) — indented at field level inside blocks
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else {
            // Field definition — indented inside block
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        }
    }

    // Trim trailing blank lines
    while (result.items.len > 0 and result.items[result.items.len - 1] == '\n') {
        result.items.len -= 1;
    }
    try result.append(alloc, '\n');

    return try result.toOwnedSlice(alloc);
}

// ─── Tests ──────────────────────────────────────────────────

test "basic table formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  name s\n", result);
}

test "strips trailing whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk   \n  name s  \n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  name s\n", result);
}

test "collapses consecutive blank lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk\n\n\n  name s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n  name s\n", result);
}

test "no blank line at start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "\n\n# users\n  id n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n", result);
}

test "trim trailing blank lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk\n\n\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n", result);
}

test "@if block not indented" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n@if(dialect=pg)\nbio T\n@endif\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n@if(dialect=pg)\n  bio T\n@endif\n", result);
}

test "@endif not indented" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n@if(dialect=pg)\n  bio T\n@endif\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n@if(dialect=pg)\n  bio T\n@endif\n", result);
}

test "doc directive indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n+ User table\nid n pk\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  + User table\n  id n pk\n  name s\n", result);
}

test "doc directive not indented outside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "+ Schema documentation\n$ mydb\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("+ Schema documentation\n$ mydb\n", result);
}

test "template parent syntax formatted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "~ base\nid n pk\ncreated_at d\n\n# users +base\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("~ base\n  id n pk\n  created_at d\n\n# users +base\n  name s\n", result);
}

test "schema declaration ends block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "$ mydb\n# users\nid n pk\n# posts\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("$ mydb\n# users\n  id n pk\n# posts\n  id n pk\n", result);
}

test "comments not indented outside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "; This is a comment\n$ mydb\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("; This is a comment\n$ mydb\n", result);
}

test "comments indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n; Comment inside table\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  ; Comment inside table\n  id n pk\n", result);
}

test "index indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n@email_idx (email)\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  @email_idx (email)\n", result);
}

test "multiple tables with blank line separation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n# posts\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n# posts\n  id n pk\n", result);
}
