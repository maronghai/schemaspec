const std = @import("std");
const formatter = @import("formatter.zig");

test "formatter: strips trailing whitespace" {
    const alloc = std.testing.allocator;
    const input = "id  n++   \nname  s64   \n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("id  n++\nname  s64\n", result);
}

test "formatter: indents fields inside table" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\nname s64\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n  name s64\n", result);
}

test "formatter: collapses consecutive blank lines" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\n\n\nname s64\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n\n  name s64\n", result);
}

test "formatter: no trailing blank lines" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\n\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n", result);
}

test "formatter: empty input" {
    const alloc = std.testing.allocator;
    const result = try formatter.format(alloc, "");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("\n", result);
}

test "formatter: comments not indented" {
    const alloc = std.testing.allocator;
    const input = "; comment\n# users\n; another\nid n++\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("; comment\n# users\n  ; another\n  id n++\n", result);
}

test "formatter: schema declaration not indented" {
    const alloc = std.testing.allocator;
    const input = "$ mydb\n# users\nid n++\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("$ mydb\n# users\n  id n++\n", result);
}

test "formatter: index indented" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n++\nname s64\n@ name\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users\n  id n++\n  name s64\n  @ name\n", result);
}

test "formatter: template indented" {
    const alloc = std.testing.allocator;
    const input = "~ base\nid n++\ncreated_at t\n# users\n...\nname s64\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("~ base\n  id n++\n  created_at t\n# users\n  ...\n  name s64\n", result);
}

test "formatter: full example" {
    const alloc = std.testing.allocator;
    const input = "$ mydb\n\n\n; Users table\n# users\nid       n++\nemail    s128\nname     s64\n\n\n; Posts table\n# posts\nid         n++\ntitle      s256\nauthor_id  n\n@ author_id\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "$ mydb\n\n; Users table\n# users\n  id       n++\n  email    s128\n  name     s64\n\n  ; Posts table\n# posts\n  id         n++\n  title      s256\n  author_id  n\n  @ author_id\n";
    try std.testing.expectEqualStrings(expected, result);
}

// ─── v0.193.0: @if and doc directive tests ──────────────────

test "formatter: @if block not indented" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n pk\n\n@if(dialect=pg)\nbio T\n@endif\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "# users\n  id n pk\n\n@if(dialect=pg)\n  bio T\n@endif\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "formatter: @endif not indented even inside block" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n pk\n@if(dialect=pg)\n  bio T\n@endif\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "# users\n  id n pk\n@if(dialect=pg)\n  bio T\n@endif\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "formatter: doc directive indented inside block" {
    const alloc = std.testing.allocator;
    const input = "# users\n+ User table\nid n pk\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "# users\n  + User table\n  id n pk\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "formatter: doc directive not indented outside block" {
    const alloc = std.testing.allocator;
    const input = "+ Schema doc\n$ mydb\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "+ Schema doc\n$ mydb\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "formatter: template with @if and doc" {
    const alloc = std.testing.allocator;
    const input = "~ base\n+ Base template\nid n pk\n\n@if(dialect=pg)\nseq_id i\n@endif\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "~ base\n  + Base template\n  id n pk\n\n@if(dialect=pg)\n  seq_id i\n@endif\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "formatter: multiple tables with blank line" {
    const alloc = std.testing.allocator;
    const input = "# users\nid n pk\n\n# posts\nid n pk\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    const expected = "# users\n  id n pk\n\n# posts\n  id n pk\n";
    try std.testing.expectEqualStrings(expected, result);
}

// ─── v0.329.0: brace syntax ─────────────────────────────────

test "formatter: closing brace at column 0 closes the block" {
    const alloc = std.testing.allocator;
    const input = "# users {\nid n pk\n}\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users {\n  id n pk\n}\n", result);
}

test "formatter: brace format is idempotent" {
    const alloc = std.testing.allocator;
    const input = "# users {\nid n pk\nname s100\n}\n";
    const once = try formatter.format(alloc, input);
    defer alloc.free(once);
    const twice = try formatter.format(alloc, once);
    defer alloc.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}

test "formatter: multiple brace tables with blank line" {
    const alloc = std.testing.allocator;
    const input = "$ schema\n# users {\nid n\n}\n\n# posts {\ntitle s\n}\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("$ schema\n# users {\n  id n\n}\n\n# posts {\n  title s\n}\n", result);
}

test "formatter: nested @if braces inside a table" {
    const alloc = std.testing.allocator;
    const input = "# users {\n@if(dialect=pg) {\njsonb j\n}\n@endif\n}\n";
    const result = try formatter.format(alloc, input);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("# users {\n@if(dialect=pg) {\n  jsonb j\n}\n@endif\n}\n", result);
}

test "formatter: nested @if brace form is idempotent" {
    const alloc = std.testing.allocator;
    const input = "# users {\n@if(dialect=pg) {\njsonb j\n}\n@endif\n}\n";
    const once = try formatter.format(alloc, input);
    defer alloc.free(once);
    const twice = try formatter.format(alloc, once);
    defer alloc.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}
