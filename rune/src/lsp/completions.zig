const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const CompletionItem = protocol.CompletionItem;
const CompletionList = protocol.CompletionList;
const CompletionItemKind = protocol.CompletionItemKind;
const makeRange = @import("helpers.zig").makeRange;
const formatColumnDetail = @import("document_symbols.zig").formatColumnDetail;

// ─── Completion ─────────────────────────────────────────────

const KEYWORDS = [_]struct { label: []const u8, kind: CompletionItemKind }{
    .{ .label = "table", .kind = .keyword },
    .{ .label = "view", .kind = .keyword },
    .{ .label = "template", .kind = .keyword },
    .{ .label = "enum", .kind = .keyword },
    .{ .label = "PK", .kind = .keyword },
    .{ .label = "FK", .kind = .keyword },
    .{ .label = "UK", .kind = .keyword },
    .{ .label = "CK", .kind = .keyword },
    .{ .label = "IX", .kind = .keyword },
    .{ .label = "PKI", .kind = .keyword },
    .{ .label = "FKI", .kind = .keyword },
    .{ .label = "UKI", .kind = .keyword },
    .{ .label = "CKI", .kind = .keyword },
    .{ .label = "IXI", .kind = .keyword },
};

// Type symbols mirror parser.tryParseType / dialect DEFAULT_SYM_MAP exactly
// (schemaspec/type.md §Type Symbols). Every label here must parse as a real
// type — suggesting nonexistent symbols inserts tokens the compiler warns on.
const TYPE_SYMBOLS = [_]struct { label: []const u8, detail: []const u8, kind: CompletionItemKind }{
    .{ .label = "n", .detail = "INT", .kind = .value },
    .{ .label = "N", .detail = "BIGINT", .kind = .value },
    .{ .label = "i", .detail = "SMALLINT", .kind = .value },
    .{ .label = "m", .detail = "DECIMAL(16,2)", .kind = .value },
    .{ .label = "M", .detail = "DECIMAL(20,6)", .kind = .value },
    .{ .label = "s", .detail = "VARCHAR(255)", .kind = .value },
    .{ .label = "s32", .detail = "VARCHAR(32)", .kind = .value },
    .{ .label = "s64", .detail = "VARCHAR(64)", .kind = .value },
    .{ .label = "s128", .detail = "VARCHAR(128)", .kind = .value },
    .{ .label = "S", .detail = "TEXT", .kind = .value },
    .{ .label = "b", .detail = "BOOLEAN", .kind = .value },
    .{ .label = "B", .detail = "BLOB", .kind = .value },
    .{ .label = "j", .detail = "JSON", .kind = .value },
    .{ .label = "J", .detail = "JSONB", .kind = .value },
    .{ .label = "I", .detail = "INET", .kind = .value },
    .{ .label = "d", .detail = "DATE", .kind = .value },
    .{ .label = "t", .detail = "DATETIME (+ = CURRENT_TIMESTAMP default)", .kind = .value },
    .{ .label = "T", .detail = "TIMESTAMP WITH TIME ZONE", .kind = .value },
    .{ .label = "U", .detail = "UUID", .kind = .value },
    .{ .label = "p", .detail = "SERIAL (auto-incrementing PK)", .kind = .value },
};

// Modifiers mirror schemaspec/schema.md §Modifiers. `!` is PRIMARY KEY,
// `+`/`++` are AUTO_INCREMENT / timestamp defaults (type-sensitive),
// `@`/`@u` are INDEX / UNIQUE INDEX. Fields are NOT NULL by default.
const MODIFIERS = [_]struct { label: []const u8, detail: []const u8, kind: CompletionItemKind }{
    .{ .label = "++", .detail = "AUTO_INCREMENT + PRIMARY KEY (datetime: + ON UPDATE CURRENT_TIMESTAMP)", .kind = .keyword },
    .{ .label = "+", .detail = "AUTO_INCREMENT (datetime: DEFAULT CURRENT_TIMESTAMP)", .kind = .keyword },
    .{ .label = "!", .detail = "PRIMARY KEY", .kind = .keyword },
    .{ .label = "?", .detail = "NULL (fields are NOT NULL by default)", .kind = .keyword },
    .{ .label = "=value", .detail = "DEFAULT value (attached: =0, ='x')", .kind = .keyword },
    .{ .label = "@u", .detail = "UNIQUE INDEX", .kind = .keyword },
    .{ .label = "@", .detail = "INDEX", .kind = .keyword },
    .{ .label = "[min,max]", .detail = "CHECK constraint range", .kind = .keyword },
    .{ .label = ":text", .detail = "COMMENT", .kind = .keyword },
};

/// Extract the word being typed at cursor position (for prefix filtering).
pub fn wordAtCursor(text: []const u8, position: Position) []const u8 {
    var line_start: usize = 0;
    var current_line: u32 = 0;

    for (text, 0..) |c, i| {
        if (c == '\n' or i == text.len - 1) {
            if (current_line == position.line) {
                const line_end = if (c == '\n') i else i + 1;
                const line = text[line_start..line_end];
                const cursor_offset = @min(position.character + 1, line.len);
                const before_cursor = line[0..cursor_offset];
                var word_end = before_cursor.len;
                while (word_end > 0) : (word_end -= 1) {
                    const wc = before_cursor[word_end - 1];
                    if (std.ascii.isAlphanumeric(wc) or wc == '_' or wc == '.') continue;
                    break;
                }
                return before_cursor[word_end..];
            }
            if (c == '\n') {
                line_start = i + 1;
                current_line += 1;
            }
        }
    }
    return "";
}

/// Context type for cursor position in a .ss file.
pub const CompletionContext = enum {
    top_level,
    inside_table,
    after_fk_keyword,
    after_percent,
    after_at,
    after_hash,
};

/// Strip comments from a line (everything after `#` or `//` that's not inside a string).
fn stripLineComments(line: []const u8) []const u8 {
    var in_string = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (c == '\'' or c == '"') {
            in_string = !in_string;
        } else if (!in_string) {
            if (c == '#' or (c == '/' and i + 1 < line.len and line[i + 1] == '/')) {
                return line[0..i];
            }
        }
    }
    return line;
}

/// Detect the completion context from document text and cursor position.
pub fn detectContext(text: []const u8, position: Position) CompletionContext {
    var line_start: usize = 0;
    var current_line: u32 = 0;

    for (text, 0..) |c, i| {
        if (c == '\n' or i == text.len - 1) {
            if (current_line == position.line) {
                const line_end = if (c == '\n') i else i + 1;
                const line_text = text[line_start..line_end];
                const stripped = stripLineComments(line_text);
                const trimmed = std.mem.trim(u8, stripped, " \t\r\n");

                if (std.mem.indexOf(u8, trimmed, "FK") != null) {
                    return .after_fk_keyword;
                }
                if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '%') {
                    return .after_percent;
                }
                if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '@') {
                    return .after_at;
                }
                if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '#') {
                    return .after_hash;
                }

                var brace_depth: u32 = 0;
                var in_str = false;
                var str_char: u8 = 0;
                var j: usize = 0;
                while (j <= i) : (j += 1) {
                    const tc = text[j];
                    if (in_str) {
                        if (tc == str_char) in_str = false;
                    } else if (tc == '\'' or tc == '"') {
                        in_str = true;
                        str_char = tc;
                    } else if (tc == '#') {
                        while (j < text.len and text[j] != '\n') j += 1;
                    } else if (tc == '/' and j + 1 < text.len and text[j + 1] == '/') {
                        while (j < text.len and text[j] != '\n') j += 1;
                    } else if (tc == '{') {
                        brace_depth += 1;
                    } else if (tc == '}') {
                        if (brace_depth > 0) brace_depth -= 1;
                    }
                }
                if (brace_depth > 0) return .inside_table;

                return .top_level;
            }
            if (c == '\n') {
                line_start = i + 1;
                current_line += 1;
            }
        }
    }

    return .top_level;
}

/// Generate completion items based on cursor position and document context.
pub fn getCompletions(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: ?[]const u8) CompletionList {
    var items = std.ArrayList(CompletionItem).initCapacity(alloc, 64) catch return .{
        .is_incomplete = false,
        .items = &.{},
    };

    const context = if (doc_text) |text| detectContext(text, position) else .top_level;
    const prefix = if (doc_text) |text| wordAtCursor(text, position) else "";

    switch (context) {
        .top_level => {
            for (KEYWORDS) |kw| {
                if (prefix.len == 0 or std.mem.startsWith(u8, kw.label, prefix)) {
                    items.append(alloc, .{
                        .label = kw.label,
                        .kind = kw.kind,
                        .detail = null,
                    }) catch {};
                }
            }
        },
        .inside_table => {
            for (TYPE_SYMBOLS) |ts| {
                if (prefix.len == 0 or std.mem.startsWith(u8, ts.label, prefix)) {
                    items.append(alloc, .{
                        .label = ts.label,
                        .kind = ts.kind,
                        .detail = ts.detail,
                        .documentation = ts.detail,
                    }) catch {};
                }
            }
            for (MODIFIERS) |mod| {
                if (prefix.len == 0 or std.mem.startsWith(u8, mod.label, prefix)) {
                    items.append(alloc, .{
                        .label = mod.label,
                        .kind = mod.kind,
                        .detail = mod.detail,
                    }) catch {};
                }
            }
            for (ast.tables) |table| {
                for (table.columns) |col| {
                    var law = std.Io.Writer.Allocating.init(alloc);
                    law.writer.print("{s}.{s}", .{ table.name, col.name }) catch continue;
                    const label = law.toOwnedSlice() catch continue;
                    if (prefix.len == 0 or std.mem.startsWith(u8, label, prefix)) {
                        items.append(alloc, .{
                            .label = label,
                            .kind = .field,
                            .detail = formatColumnDetail(alloc, col),
                        }) catch {};
                    }
                }
            }
        },
        .after_fk_keyword => {
            for (ast.tables) |table| {
                if (prefix.len == 0 or std.mem.startsWith(u8, table.name, prefix)) {
                    items.append(alloc, .{
                        .label = table.name,
                        .kind = .class,
                        .detail = table.comment,
                    }) catch {};
                }
                for (table.columns) |col| {
                    var law = std.Io.Writer.Allocating.init(alloc);
                    law.writer.print("{s}.{s}", .{ table.name, col.name }) catch continue;
                    const label = law.toOwnedSlice() catch continue;
                    if (prefix.len == 0 or std.mem.startsWith(u8, label, prefix)) {
                        items.append(alloc, .{
                            .label = label,
                            .kind = .field,
                            .detail = formatColumnDetail(alloc, col),
                        }) catch {};
                    }
                }
            }
        },
        .after_percent => {
            for (ast.tables) |table| {
                if (prefix.len == 0 or std.mem.startsWith(u8, table.name, prefix)) {
                    items.append(alloc, .{
                        .label = table.name,
                        .kind = .class,
                        .detail = table.comment,
                    }) catch {};
                }
            }
        },
        .after_at => {
            const gen_keywords = [_]struct { label: []const u8, detail: []const u8 }{
                .{ .label = "generated", .detail = "Generated column (STORED)" },
            };
            for (gen_keywords) |kw| {
                if (prefix.len == 0 or std.mem.startsWith(u8, kw.label, prefix)) {
                    items.append(alloc, .{
                        .label = kw.label,
                        .kind = .keyword,
                        .detail = kw.detail,
                    }) catch {};
                }
            }
        },
        .after_hash => {
            const comment_hints = [_]struct { label: []const u8, detail: []const u8 }{
                .{ .label = "TODO", .detail = "TODO comment" },
                .{ .label = "NOTE", .detail = "Note comment" },
                .{ .label = "FIXME", .detail = "Fixme comment" },
            };
            for (comment_hints) |hint| {
                if (prefix.len == 0 or std.mem.startsWith(u8, hint.label, prefix)) {
                    items.append(alloc, .{
                        .label = hint.label,
                        .kind = .text,
                        .detail = hint.detail,
                    }) catch {};
                }
            }
        },
    }

    return .{
        .is_incomplete = false,
        .items = items.toOwnedSlice(alloc) catch &.{},
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "Completion: offers keywords and types" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 0, .character = 0 }, null);
    defer std.testing.allocator.free(list.items);
    try std.testing.expect(list.items.len > 0);
}

test "Completion: context-sensitive top level" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 0, .character = 0 }, "table users {\n");
    defer std.testing.allocator.free(list.items);
    // Should return completions (either type symbols for inside_table or keywords for top_level)
    try std.testing.expect(list.items.len > 0);
}

test "Completion: context-sensitive inside table" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 1, .character = 2 }, "table users {\n  ");
    defer std.testing.allocator.free(list.items);
    var has_type = false;
    for (list.items) |item| {
        if (std.mem.eql(u8, item.label, "n")) {
            has_type = true;
            break;
        }
    }
    try std.testing.expect(has_type);
}

test "Completion: every type symbol parses as a real type" {
    // The catalog must never suggest a token the parser rejects — each label
    // goes through the same tryParseType the compiler uses.
    const parse_field = @import("../parser/parse_field.zig");
    for (TYPE_SYMBOLS) |ts| {
        const parsed = parse_field.tryParseType(ts.label);
        if (parsed == null) {
            // Multi-char suggestion forms like "=value" are modifier-side; type
            // symbols must all be parseable, no exceptions.
            std.debug.print("type symbol '{s}' does not parse\n", .{ts.label});
            try std.testing.expect(false);
        }
    }
}

test "Completion: i is SMALLINT and t is DATETIME per spec" {
    var found_i = false;
    var found_t = false;
    for (TYPE_SYMBOLS) |ts| {
        if (std.mem.eql(u8, ts.label, "i")) {
            found_i = true;
            try std.testing.expect(std.mem.indexOf(u8, ts.detail, "SMALLINT") != null);
        }
        if (std.mem.eql(u8, ts.label, "t")) {
            found_t = true;
            try std.testing.expect(std.mem.indexOf(u8, ts.detail, "DATETIME") != null);
        }
    }
    try std.testing.expect(found_i);
    try std.testing.expect(found_t);
}

test "Completion: ! is PRIMARY KEY and @ is INDEX per spec" {
    for (MODIFIERS) |m| {
        if (std.mem.eql(u8, m.label, "!")) {
            try std.testing.expect(std.mem.indexOf(u8, m.detail, "PRIMARY KEY") != null);
        }
        if (std.mem.eql(u8, m.label, "@")) {
            try std.testing.expect(std.mem.indexOf(u8, m.detail, "INDEX") != null);
        }
    }
}
