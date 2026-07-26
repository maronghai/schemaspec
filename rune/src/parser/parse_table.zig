const std = @import("std");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const SourceLocation = ast_mod.SourceLocation;

// ─── Table Parsing ────────────────────────────────────────────
// Extracted from parser.zig for single-responsibility.
// Handles: table header parsing, engine token stripping.

pub const TableHeader = struct {
    template_ref: ?[]const u8,
    name: []const u8,
    comment: ?[]const u8,
    line_no: usize,
    loc: ?SourceLocation,
};

/// Parse a table header line (# [template_ref] table_name [: comment]).
pub fn parseTableHeader(alloc: std.mem.Allocator, line: tk.Line) !TableHeader {
    var template_ref: ?[]const u8 = null;
    var table_name: []const u8 = "";
    var comment: ?[]const u8 = null;

    const tokens = line.tokens;
    if (tokens.len == 2) {
        // # table_name  (no template ref)
        table_name = try alloc.dupe(u8, tokens[1]);
    } else if (tokens.len >= 3) {
        // Check if tokens[2] is a comment
        if (tokens[2].len >= 1 and tokens[2][0] == ':') {
            // # table_name : comment
            table_name = try alloc.dupe(u8, tokens[1]);
            comment = try alloc.dupe(u8, tokens[2]);
        } else {
            // # template_ref table_name [: comment]
            template_ref = try alloc.dupe(u8, tokens[1]);
            table_name = try alloc.dupe(u8, tokens[2]);
            if (tokens.len >= 4) {
                comment = try alloc.dupe(u8, tokens[3]);
            }
        }
    }

    return .{
        .template_ref = template_ref,
        .name = table_name,
        .comment = comment,
        .line_no = line.line_no,
        .loc = locFromLine(line, line.tokens[0]),
    };
}

/// Strip engine tokens (^ or ^EngineName) from a table line's tokens.
pub fn stripEngineTokens(alloc: std.mem.Allocator, tokens: []const []const u8) !struct { stripped: []const []const u8, engine: ?[]const u8 } {
    var engine: ?[]const u8 = null;
    var stripped = try std.ArrayList([]const u8).initCapacity(alloc, tokens.len);
    var ti: usize = 0;
    while (ti < tokens.len) : (ti += 1) {
        const tok = tokens[ti];
        if (std.mem.eql(u8, tok, "^")) {
            if (ti + 1 < tokens.len and !std.mem.eql(u8, tokens[ti + 1], ":")) {
                engine = try alloc.dupe(u8, tokens[ti + 1]);
                ti += 1;
            } else {
                engine = "InnoDB";
            }
            continue;
        }
        if (tok.len > 1 and tok[0] == '^') {
            engine = try alloc.dupe(u8, tok[1..]);
            continue;
        }
        try stripped.append(alloc, tok);
    }
    return .{ .stripped = try stripped.toOwnedSlice(alloc), .engine = engine };
}

/// Parse a view line into a View AST node.
pub fn processViewLine(alloc: std.mem.Allocator, tokens: []const []const u8, line_no: usize) !ast_mod.View {
    if (tokens.len >= 4) {
        const view_name = try alloc.dupe(u8, tokens[1]);
        var query: []const u8 = "";
        for (tokens, 0..) |tok, ti| {
            if (std.mem.eql(u8, tok, "=") and ti + 1 < tokens.len) {
                query = try alloc.dupe(u8, tokens[ti + 1]);
                break;
            }
        }
        return .{
            .name = view_name,
            .query = query,
            .comment = null,
            .line_no = line_no,
            .loc = locFromLine(.{ .line_no = line_no, .raw = "", .trimmed = "", .tokens = tokens, .line_type = .View, .offset = 0 }, tokens[0]),
        };
    } else if (tokens.len == 2) {
        return .{
            .name = try alloc.dupe(u8, tokens[1]),
            .query = "",
            .comment = null,
            .line_no = line_no,
            .loc = locFromLine(.{ .line_no = line_no, .raw = "", .trimmed = "", .tokens = tokens, .line_type = .View, .offset = 0 }, tokens[0]),
        };
    }
    return error.InvalidView;
}

/// Compute SourceLocation from a tokenized line and a token within it.
fn locFromLine(line: tk.Line, tok: []const u8) SourceLocation {
    const col = @import("../semantic/diagnostic.zig").tokenColumn(tok, line.raw);
    return .{
        .line = line.line_no,
        .col = col,
        .offset = line.offset + col - 1,
    };
}

// ─── Unit Tests ──────────────────────────────────────────────

fn makeLine(tokens: []const []const u8, line_type: tk.LineType, line_no: usize) tk.Line {
    return .{
        .line_type = line_type,
        .tokens = tokens,
        .raw = "",
        .trimmed = "",
        .line_no = line_no,
    };
}

test "parseTableHeader: # table_name" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users" };
    const hdr = try parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.template_ref);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.comment);
}

test "parseTableHeader: # table_name : comment" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users", ":user accounts" };
    const hdr = try parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.template_ref);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqualStrings(":user accounts", hdr.comment.?);
}

test "parseTableHeader: # template_ref table_name" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "base_entity", "users" };
    const hdr = try parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    try std.testing.expectEqualStrings("base_entity", hdr.template_ref.?);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqual(@as(?[]const u8, null), hdr.comment);
}

test "parseTableHeader: # template_ref table_name : comment" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "base_entity", "users", ":accounts" };
    const hdr = try parseTableHeader(alloc, makeLine(&tokens, .Table, 1));
    try std.testing.expectEqualStrings("base_entity", hdr.template_ref.?);
    try std.testing.expectEqualStrings("users", hdr.name);
    try std.testing.expectEqualStrings(":accounts", hdr.comment.?);
}

test "stripEngineTokens: ^ alone" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users", "^" };
    const result = try stripEngineTokens(alloc, &tokens);
    try std.testing.expectEqualStrings("InnoDB", result.engine.?);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
    try std.testing.expectEqualStrings("#", result.stripped[0]);
    try std.testing.expectEqualStrings("users", result.stripped[1]);
}

test "stripEngineTokens: ^MyISAM" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "logs", "^MyISAM" };
    const result = try stripEngineTokens(alloc, &tokens);
    try std.testing.expectEqualStrings("MyISAM", result.engine.?);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
}

test "stripEngineTokens: no engine token" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "#", "users" };
    const result = try stripEngineTokens(alloc, &tokens);
    try std.testing.expect(result.engine == null);
    try std.testing.expectEqual(@as(usize, 2), result.stripped.len);
}

test "processViewLine: view with query" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "V", "active_users", "=", "SELECT * FROM users WHERE active = 1" };
    const view = try processViewLine(alloc, &tokens, 1);
    try std.testing.expectEqualStrings("active_users", view.name);
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE active = 1", view.query);
}

test "processViewLine: view without query" {
    const alloc = std.testing.allocator;
    const tokens = [_][]const u8{ "V", "my_view" };
    const view = try processViewLine(alloc, &tokens, 1);
    try std.testing.expectEqualStrings("my_view", view.name);
    try std.testing.expectEqualStrings("", view.query);
}
