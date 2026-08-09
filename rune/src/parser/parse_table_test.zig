const std = @import("std");
const parse_table = @import("parse_table.zig");
const tk = @import("tokenizer.zig");

// ─── Test Helpers ───────────────────────────────────────────

fn makeLine(tokens: []const []const u8, line_type: tk.LineType, line_no: usize) tk.Line {
    return .{
        .line_type = line_type,
        .tokens = tokens,
        .raw = "",
        .trimmed = "",
        .line_no = line_no,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "parseTableHeader: # table_name" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users" };
    const hdr = try parse_table.parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    defer {
        alloc.free(hdr.name);
        if (hdr.template_ref) |t| alloc.free(t);
        if (hdr.comment) |c| alloc.free(c);
    }
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.template_ref);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.comment);
}

test "parseTableHeader: # table_name : comment" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users", ":user accounts" };
    const hdr = try parse_table.parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    defer {
        alloc.free(hdr.name);
        if (hdr.template_ref) |t| alloc.free(t);
        if (hdr.comment) |c| alloc.free(c);
    }
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.template_ref);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqualStrings(":user accounts", hdr.comment.?);
}

test "parseTableHeader: # template_ref table_name" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "base_entity", "users" };
    const hdr = try parse_table.parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    defer {
        alloc.free(hdr.name);
        if (hdr.template_ref) |t| alloc.free(t);
        if (hdr.comment) |c| alloc.free(c);
    }
    try std.testing.expectEqualStrings("base_entity", hdr.template_ref.?);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.comment);
}

test "parseTableHeader: # template_ref table_name : comment" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "base_entity", "users", ":accounts" };
    const hdr = try parse_table.parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    defer {
        alloc.free(hdr.name);
        if (hdr.template_ref) |t| alloc.free(t);
        if (hdr.comment) |c| alloc.free(c);
    }
    try std.testing.expectEqualStrings("base_entity", hdr.template_ref.?);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqualStrings(":accounts", hdr.comment.?);
}

test "stripEngineTokens: ^ alone" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users", "^" };
    const result = try parse_table.stripEngineTokens(alloc, &tokens);
    defer alloc.free(result.stripped);
    // engine = "InnoDB" is a string literal, not allocated — don't free it
    try std.testing.expectEqualStrings("InnoDB", result.engine.?);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
    try std.testing.expectEqualStrings("#", result.stripped[0]);
    try std.testing.expectEqualStrings("users", result.stripped[1]);
}

test "stripEngineTokens: ^MyISAM" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "logs", "^MyISAM" };
    const result = try parse_table.stripEngineTokens(alloc, &tokens);
    defer {
        alloc.free(result.stripped);
        if (result.engine) |e| alloc.free(e);
    }
    try std.testing.expectEqualStrings("MyISAM", result.engine.?);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
}

test "stripEngineTokens: no engine token" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users" };
    const tokens_slice: []const []const u8 = &tokens;
    const result = try parse_table.stripEngineTokens(alloc, tokens_slice);
    defer {
        // When no engine token is found, result.stripped is the original tokens (not allocated)
        if (result.stripped.ptr != tokens_slice.ptr) {
            alloc.free(result.stripped);
        }
        if (result.engine) |e| alloc.free(e);
    }
    try std.testing.expect(result.engine == null);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
}

test "processViewLine: view with query" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "V", "active_users", "=", "SELECT * FROM users WHERE active = 1" };
    const view = try parse_table.processViewLine(alloc, &tokens, 1);
    defer {
        alloc.free(view.name);
        alloc.free(view.query);
    }
    try std.testing.expectEqualStrings("active_users", view.name);
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE active = 1", view.query);
}

test "processViewLine: view without query" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "V", "my_view" };
    const view = try parse_table.processViewLine(alloc, &tokens, 1);
    defer {
        alloc.free(view.name);
        alloc.free(view.query);
    }
    try std.testing.expectEqualStrings("my_view", view.name);
    try std.testing.expectEqualStrings("", view.query);
}
