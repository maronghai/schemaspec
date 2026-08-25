const std = @import("std");

pub const LineType = enum {
    Schema,
    Template,
    Table,
    View,
    Field,
    FK,
    Index,
    Slot,
    CompositePK,
    Engine,
    TypeDef,
    Import,
    ConditionalIf,
    ConditionalEnd,
    Doc,
    SQLComment,
    SpecComment,
    Empty,
    Version,
    Composite,
};

pub const Line = struct {
    line_type: LineType,
    tokens: []const []const u8,
    raw: []const u8,
    trimmed: []const u8,
    line_no: usize,
    offset: usize = 0, // 0-based byte offset from start of input
};

pub const Tokenizer = struct {
    lines: []const []const u8,

    pub fn init(lines: []const []const u8) Tokenizer {
        return .{ .lines = lines };
    }

    pub fn tokenizeAll(self: Tokenizer, alloc: std.mem.Allocator) ![]Line {
        var result = try std.ArrayList(Line).initCapacity(alloc, self.lines.len);
        var byte_offset: usize = 0;
        for (self.lines, 0..) |line, i| {
            const line_offset = byte_offset;
            byte_offset += line.len + 1; // +1 for '\n'
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) {
                try result.append(alloc, .{ .line_type = .Empty, .tokens = &.{}, .raw = line, .trimmed = line, .line_no = i + 1, .offset = line_offset });
                continue;
            }
            if (trimmed[0] == ';') {
                try result.append(alloc, .{ .line_type = .SpecComment, .tokens = &.{}, .raw = line, .trimmed = trimmed, .line_no = i + 1, .offset = line_offset });
                continue;
            }
            if (trimmed.len >= 2 and trimmed[0] == '-' and trimmed[1] == '-') {
                try result.append(alloc, .{ .line_type = .SQLComment, .tokens = &.{}, .raw = line, .trimmed = trimmed, .line_no = i + 1, .offset = line_offset });
                continue;
            }
            const lt = classifyLine(trimmed);
            // View lines: parse as [&, name, =, query...] — query is everything after first =
            if (lt == .View) {
                const view_tokens = try tokenizeViewLine(alloc, trimmed);
                try result.append(alloc, .{ .line_type = lt, .tokens = view_tokens, .raw = line, .trimmed = trimmed, .line_no = i + 1, .offset = line_offset });
                continue;
            }
            const toks = try tokenizeLine(alloc, trimmed);
            try result.append(alloc, .{ .line_type = lt, .tokens = toks, .raw = line, .trimmed = trimmed, .line_no = i + 1, .offset = line_offset });
        }
        return try result.toOwnedSlice(alloc);
    }

    pub fn classifyLine(line: []const u8) LineType {
        if (line[0] == '$') return .Schema;
        if (line[0] == '%') return .Template;
        if (line[0] == '#') return .Table;
        if (line[0] == '&') return .View;
        if (line[0] == '>') return .FK;
        if (line[0] == '!' and (line.len == 1 or line[1] == ' ')) return .CompositePK;
        if (line[0] == '^') return .Engine;
        if (line.len >= 3 and line[0] == '.' and line[1] == '.' and line[2] == '.') return .Slot;
        if (line[0] == '~') return .TypeDef;
        if (line.len >= 7 and line[0] == '@' and std.mem.eql(u8, line[0..7], "@import")) return .Import;
        if (line.len >= 4 and line[0] == '@' and std.mem.eql(u8, line[0..4], "@if(")) return .ConditionalIf;
        if (line.len >= 6 and line[0] == '@' and std.mem.eql(u8, line[0..6], "@endif")) return .ConditionalEnd;
        if (line.len >= 8 and line[0] == '@' and std.mem.eql(u8, line[0..8], "@version")) return .Version;
        if (line[0] == '*') return .Composite;
        if (line[0] == '@') return .Index;
        if (line[0] == '+') return .Doc;
        return .Field;
    }

    pub fn tokenizeLine(alloc: std.mem.Allocator, line: []const u8) ![]const []const u8 {
        // First pass: split by spaces, but a backtick-quoted segment
        // (`order details`) is one token even across spaces — quoted
        // identifiers may contain them.
        var raw_tokens = try std.ArrayList([]const u8).initCapacity(alloc, 8);
        defer raw_tokens.deinit(alloc);
        {
            var i: usize = 0;
            while (i < line.len) {
                const c = line[i];
                if (c == ' ' or c == '\t') {
                    i += 1;
                    continue;
                }
                if (c == '-' and i + 1 < line.len and line[i + 1] == '-') break;
                if (c == ';') break;
                if (c == ':') {
                    try raw_tokens.append(alloc, line[i..]);
                    break;
                }
                const start = i;
                if (c == '`') {
                    i += 1;
                    while (i < line.len and line[i] != '`') : (i += 1) {}
                    if (i < line.len) i += 1; // closing backtick
                    // Glue an immediately-following word (`` `name`s32 `` is
                    // not produced by the reverse emitter, but be tolerant).
                    while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {}
                    try raw_tokens.append(alloc, line[start..i]);
                    continue;
                }
                while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {}
                try raw_tokens.append(alloc, line[start..i]);
            }
        }

        // Second pass: iteratively split tokens
        var tokens = try std.ArrayList([]const u8).initCapacity(alloc, raw_tokens.items.len * 2);
        for (raw_tokens.items) |tok| {
            try splitToken(alloc, &tokens, tok);
        }
        const result = try alloc.dupe([]const u8, tokens.items);
        tokens.deinit(alloc);
        return result;
    }

    /// Tokenize a view line: `& name = SELECT ...` → [& , name, =, query]
    /// The query is everything after the first `=`, kept as a single token.
    fn tokenizeViewLine(alloc: std.mem.Allocator, line: []const u8) ![]const []const u8 {
        var tokens = try std.ArrayList([]const u8).initCapacity(alloc, 4);
        // & marker
        try tokens.append(alloc, line[0..1]);
        // Find first space after &
        const rest = std.mem.trimStart(u8, line[1..], " ");
        if (rest.len == 0) return try tokens.toOwnedSlice(alloc);
        // Find end of name (space or =)
        var name_end: usize = 0;
        while (name_end < rest.len and rest[name_end] != ' ' and rest[name_end] != '=') : (name_end += 1) {}
        try tokens.append(alloc, rest[0..name_end]);
        // Skip to = sign
        var eq_pos = name_end;
        while (eq_pos < rest.len and rest[eq_pos] != '=') : (eq_pos += 1) {}
        if (eq_pos < rest.len) {
            try tokens.append(alloc, rest[eq_pos .. eq_pos + 1]); // =
            const query = std.mem.trimStart(u8, rest[eq_pos + 1 ..], " ");
            if (query.len > 0) {
                // Strip trailing comment (-- ...)
                var qend = query.len;
                var i: usize = 0;
                while (i + 1 < query.len) : (i += 1) {
                    if (query[i] == '-' and query[i + 1] == '-') {
                        qend = i;
                        break;
                    }
                }
                try tokens.append(alloc, std.mem.trimEnd(u8, query[0..qend], " "));
            }
        }
        return try tokens.toOwnedSlice(alloc);
    }

    fn splitToken(alloc: std.mem.Allocator, tokens: *std.ArrayList([]const u8), tok: []const u8) !void {
        // Comment - keep as is
        if (tok[0] == ':') {
            try tokens.append(alloc, tok);
            return;
        }

        // Split leading structural markers: #base → #, base
        if (tok.len > 1 and (tok[0] == '#' or tok[0] == '%' or tok[0] == '$' or tok[0] == '@' or tok[0] == '^' or tok[0] == '~' or tok[0] == '&' or tok[0] == '*')) {
            try tokens.append(alloc, tok[0..1]);
            try splitToken(alloc, tokens, tok[1..]);
            return;
        }

        // Split leading (: (email → (, email
        if (tok.len > 1 and tok[0] == '(') {
            try tokens.append(alloc, "(");
            try splitToken(alloc, tokens, tok[1..]);
            return;
        }

        // Split enum type: e(M,F,X) → e, (, M, ,, F, ,, X, )
        if (tok.len > 2 and tok[0] == 'e' and tok[1] == '(') {
            try tokens.append(alloc, "e");
            try splitToken(alloc, tokens, tok[1..]);
            return;
        }

        // Split trailing ): email) → email, )
        if (tok.len > 1 and tok[tok.len - 1] == ')') {
            try splitToken(alloc, tokens, tok[0 .. tok.len - 1]);
            try tokens.append(alloc, ")");
            return;
        }

        // Split trailing comma: user_id, → user_id, ,
        if (tok.len > 1 and tok[tok.len - 1] == ',') {
            try splitToken(alloc, tokens, tok[0 .. tok.len - 1]);
            try tokens.append(alloc, ",");
            return;
        }

        // Split embedded (: order_item(order_id → order_item, (, order_id
        if (tok.len > 2 and tok[0] != '(' and std.mem.indexOfScalar(u8, tok, '(') != null) {
            if (std.mem.indexOfScalar(u8, tok, '(')) |paren_pos| {
                if (paren_pos > 0) try tokens.append(alloc, tok[0..paren_pos]);
                try splitToken(alloc, tokens, tok[paren_pos..]);
                return;
            }
        }

        // Split leading [: [0,1] → [, 0,1]
        if (tok.len > 1 and tok[0] == '[') {
            try tokens.append(alloc, tok[0..1]);
            try splitToken(alloc, tokens, tok[1..]);
            return;
        }

        // Split trailing ]: 0,1] → 0,1, ]
        if (tok.len > 1 and tok[tok.len - 1] == ']') {
            try splitToken(alloc, tokens, tok[0 .. tok.len - 1]);
            try tokens.append(alloc, "]");
            return;
        }

        // Split leading {: {0,1} → {, 0,1}
        if (tok.len > 1 and tok[0] == '{') {
            try tokens.append(alloc, tok[0..1]);
            try splitToken(alloc, tokens, tok[1..]);
            return;
        }

        // Split trailing }: 0,1} → 0,1, }
        if (tok.len > 1 and tok[tok.len - 1] == '}') {
            try splitToken(alloc, tokens, tok[0 .. tok.len - 1]);
            try tokens.append(alloc, "}");
            return;
        }

        // No split needed
        try tokens.append(alloc, tok);
    }

    pub fn diagnosticTrace(lines: []const Line) void {
        std.debug.print("=== [Stage 1: Tokenizer] ===\n", .{});
        std.debug.print("Input lines: {d}\n\n", .{lines.len});
        for (lines) |line| {
            if (line.line_type == .Empty or line.line_type == .SpecComment) continue;
            std.debug.print("  L{d: >4} [{s: <12}] ", .{ line.line_no, @tagName(line.line_type) });
            for (line.tokens, 0..) |tok, ti| {
                if (ti > 0) std.debug.print(" ", .{});
                std.debug.print("{s}", .{tok});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }
};
