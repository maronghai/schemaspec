const std = @import("std");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const SourceLocation = ast_mod.SourceLocation;
const locFromLine = @import("loc.zig").locFromLine;

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

/// Parse a table header line (# table_name > template_ref [: comment]).
/// Also supports the legacy format (# template_ref table_name [: comment]).
pub fn parseTableHeader(alloc: std.mem.Allocator, line: tk.Line) !TableHeader {
    var template_ref: ?[]const u8 = null;
    var table_name: []const u8 = "";
    var comment: ?[]const u8 = null;

    const tokens = line.tokens;

    // Check for > operator: # table_name > template_ref [: comment]
    var gt_idx: ?usize = null;
    for (tokens, 0..) |tok, i| {
        if (std.mem.eql(u8, tok, ">")) {
            gt_idx = i;
            break;
        }
    }

    if (gt_idx) |gt| {
        // # table_name > template_ref [: comment]
        if (gt >= 1 and gt + 1 < tokens.len) {
            table_name = try alloc.dupe(u8, tokens[gt - 1]);
            template_ref = try alloc.dupe(u8, tokens[gt + 1]);
            if (gt + 2 < tokens.len) {
                const cand = tokens[gt + 2];
                if (cand.len >= 1 and cand[0] == ':') {
                    comment = try alloc.dupe(u8, cand);
                }
            }
        }
    } else if (tokens.len == 2) {
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
    const result = try stripped.toOwnedSlice(alloc);
    stripped.deinit(alloc);
    return .{ .stripped = result, .engine = engine };
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
        // Detect UNION/INTERSECT/EXCEPT in query
        const union_result = detectSetOperation(query);
        return .{
            .name = view_name,
            .query = if (union_result) |u| u.first else query,
            .comment = null,
            .line_no = line_no,
            .loc = locFromLine(.{ .line_no = line_no, .raw = "", .trimmed = "", .tokens = tokens, .line_type = .View, .offset = 0 }, tokens[0]),
            .union_op = if (union_result) |u| u.op else null,
            .second_query = if (union_result) |u| u.second else null,
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

const SetOperationResult = struct {
    first: []const u8,
    op: ast_mod.ViewUnionOp,
    second: []const u8,
};

/// Detect UNION/UNION ALL/INTERSECT/EXCEPT in a query string.
/// Returns null if no set operation found at the top level (outside quotes).
fn detectSetOperation(query: ?[]const u8) ?SetOperationResult {
    const q = query orelse return null;
    if (q.len == 0) return null;

    // Keywords to search for (ordered by length, longest first for UNION ALL)
    const keywords = [_]struct { text: []const u8, op: ast_mod.ViewUnionOp }{
        .{ .text = " UNION ALL ", .op = .union_all },
        .{ .text = " union all ", .op = .union_all },
        .{ .text = " UNION ", .op = .union_distinct },
        .{ .text = " union ", .op = .union_distinct },
        .{ .text = " INTERSECT ", .op = .intersect },
        .{ .text = " intersect ", .op = .intersect },
        .{ .text = " EXCEPT ", .op = .except },
        .{ .text = " except ", .op = .except },
    };

    // Track quote state to avoid matching inside string literals
    var in_single_quote = false;
    var in_double_quote = false;
    var i: usize = 0;
    while (i < q.len) : (i += 1) {
        const c = q[i];
        if (c == '\'' and !in_double_quote) {
            in_single_quote = !in_single_quote;
        } else if (c == '"' and !in_single_quote) {
            in_double_quote = !in_double_quote;
        } else if (!in_single_quote and !in_double_quote) {
            for (keywords) |kw| {
                if (i + kw.text.len <= q.len and std.mem.eql(u8, q[i .. i + kw.text.len], kw.text)) {
                    return .{
                        .first = std.mem.trimEnd(u8, q[0..i], " "),
                        .op = kw.op,
                        .second = std.mem.trimStart(u8, q[i + kw.text.len ..], " "),
                    };
                }
            }
        }
    }
    return null;
}
