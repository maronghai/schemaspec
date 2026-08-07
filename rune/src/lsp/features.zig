const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const TypedTable = @import("../types/typed_ast.zig").TypedTable;
const TypedColumn = @import("../types/typed_ast.zig").TypedColumn;
const TypedView = @import("../types/typed_ast.zig").TypedView;
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
const protocol = @import("protocol.zig");
const Position = protocol.Position;
const Range = protocol.Range;
const DocumentSymbol = protocol.DocumentSymbol;
const SymbolKind = protocol.SymbolKind;
const CompletionItem = protocol.CompletionItem;
const CompletionList = protocol.CompletionList;
const CompletionItemKind = protocol.CompletionItemKind;
const Hover = protocol.Hover;
const MarkupContent = protocol.MarkupContent;
const MarkupKind = protocol.MarkupKind;
const Location = protocol.Location;
const CodeAction = protocol.CodeAction;
const CodeActionKind = protocol.CodeActionKind;
const TextEdit = protocol.TextEdit;
const Diagnostic = protocol.Diagnostic;
const DiagnosticSeverity = protocol.DiagnosticSeverity;

// ─── LSP Features ───────────────────────────────────────────
// Implements Document Symbols, Completion, Hover, and Go-to-Definition
// using the cached TypedAst from compilation.

// ─── Document Symbols ───────────────────────────────────────

/// Generate document symbols from a TypedAst for the outline view.
pub fn getDocumentSymbols(alloc: std.mem.Allocator, ast: TypedAst) []DocumentSymbol {
    var symbols = std.ArrayList(DocumentSymbol).initCapacity(alloc, ast.tables.len + ast.views.len) catch return &.{};

    for (ast.tables) |table| {
        const line_no: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
        const end_line: u32 = line_no + 1;

        // Collect child symbols: columns, FKs, indexes
        var children = std.ArrayList(DocumentSymbol).initCapacity(alloc, table.columns.len + table.fks.len + table.indexes.len) catch null;

        if (children) |*ch| {
            // Columns
            for (table.columns) |col| {
                const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = col.name,
                    .detail = formatColumnDetail(alloc, col),
                    .kind = if (col.flags.primary_key) .constant else .field,
                    .range = makeRange(col_line, 0, col_line, 100),
                    .selection_range = makeRange(col_line, 0, col_line, @intCast(col.name.len)),
                }) catch {};
            }

            // Foreign keys
            for (table.fks) |fk| {
                const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = if (fk.fields.len > 0) fk.fields[0] else "FK",
                    .detail = formatFkDetail(alloc, fk),
                    .kind = .constant,
                    .range = makeRange(fk_line, 0, fk_line, 100),
                    .selection_range = makeRange(fk_line, 0, fk_line, 4),
                }) catch {};
            }

            // Indexes
            for (table.indexes) |idx| {
                const idx_line: u32 = if (idx.line_no > 0) @intCast(idx.line_no - 1) else line_no;
                ch.append(alloc, .{
                    .name = idx.name,
                    .detail = formatIndexDetail(alloc, idx),
                    .kind = .key,
                    .range = makeRange(idx_line, 0, idx_line, 100),
                    .selection_range = makeRange(idx_line, 0, idx_line, 4),
                }) catch {};
            }
        }

        symbols.append(alloc, .{
            .name = table.name,
            .detail = table.comment,
            .kind = .class,
            .range = makeRange(line_no, 0, end_line, 0),
            .selection_range = makeRange(line_no, 0, line_no, @intCast(table.name.len)),
            .children = if (children) |ch| ch.items else null,
        }) catch {};
    }

    // Views
    for (ast.views) |view| {
        const line_no: u32 = if (view.line_no > 0) @intCast(view.line_no - 1) else 0;
        symbols.append(alloc, .{
            .name = view.name,
            .detail = view.comment,
            .kind = .event,
            .range = makeRange(line_no, 0, line_no + 1, 0),
            .selection_range = makeRange(line_no, 0, line_no, @intCast(view.name.len)),
        }) catch {};
    }

    return symbols.items;
}

fn formatColumnDetail(alloc: std.mem.Allocator, col: TypedColumn) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    aw.writer.print("{s}", .{@tagName(col.sql_type)}) catch return null;

    // Add size for varchar/decimal
    switch (col.sql_type) {
        .varchar => |n| {
            if (n > 0) {
                aw.writer.print("({d})", .{n}) catch {};
            }
        },
        .decimal => |ds| {
            aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
        },
        else => {},
    }

    // Add flags
    if (col.flags.primary_key) aw.writer.writeAll(" PK") catch {};
    if (col.flags.auto_increment) aw.writer.writeAll(" AUTO_INCREMENT") catch {};
    if (col.flags.nullable) aw.writer.writeAll(" NULL") catch {};
    if (col.flags.unsigned) aw.writer.writeAll(" UNSIGNED") catch {};

    return aw.toOwnedSlice() catch return null;
}

fn formatFkDetail(alloc: std.mem.Allocator, fk: FkDecl) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    aw.writer.writeAll("-> ") catch return null;
    aw.writer.writeAll(fk.ref_table) catch return null;
    aw.writer.writeByte('.') catch return null;
    if (fk.ref_fields.len > 0) {
        aw.writer.writeAll(fk.ref_fields[0]) catch return null;
    }
    return aw.toOwnedSlice() catch return null;
}

fn formatIndexDetail(alloc: std.mem.Allocator, idx: IndexDecl) ?[]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    switch (idx.kind) {
        .unique => aw.writer.writeAll("UNIQUE ") catch {},
        .fulltext => aw.writer.writeAll("FULLTEXT ") catch {},
        .primary_key => aw.writer.writeAll("PRIMARY ") catch {},
        .regular => {},
    }
    aw.writer.writeAll("(") catch return null;
    for (idx.fields, 0..) |f, i| {
        if (i > 0) aw.writer.writeAll(", ") catch {};
        aw.writer.writeAll(f) catch {};
    }
    aw.writer.writeByte(')') catch return null;
    return aw.toOwnedSlice() catch return null;
}

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

const TYPE_SYMBOLS = [_]struct { label: []const u8, detail: []const u8, kind: CompletionItemKind }{
    .{ .label = "n", .detail = "INT", .kind = .value },
    .{ .label = "i", .detail = "BIGINT", .kind = .value },
    .{ .label = "u", .detail = "INT UNSIGNED", .kind = .value },
    .{ .label = "s", .detail = "VARCHAR(255)", .kind = .value },
    .{ .label = "s64", .detail = "VARCHAR(64)", .kind = .value },
    .{ .label = "s128", .detail = "VARCHAR(128)", .kind = .value },
    .{ .label = "s512", .detail = "VARCHAR(512)", .kind = .value },
    .{ .label = "m", .detail = "TEXT", .kind = .value },
    .{ .label = "f", .detail = "FLOAT", .kind = .value },
    .{ .label = "d", .detail = "DATE", .kind = .value },
    .{ .label = "dt", .detail = "DATETIME", .kind = .value },
    .{ .label = "t", .detail = "TIMESTAMP", .kind = .value },
    .{ .label = "b", .detail = "BOOLEAN", .kind = .value },
    .{ .label = "uid", .detail = "UUID", .kind = .value },
    .{ .label = "json", .detail = "JSON", .kind = .value },
    .{ .label = "jsonb", .detail = "JSONB", .kind = .value },
    .{ .label = "text", .detail = "TEXT", .kind = .value },
};

const MODIFIERS = [_]struct { label: []const u8, detail: []const u8, kind: CompletionItemKind }{
    .{ .label = "++", .detail = "Auto-increment PK", .kind = .keyword },
    .{ .label = "!", .detail = "NOT NULL", .kind = .keyword },
    .{ .label = "*", .detail = "UNIQUE", .kind = .keyword },
    .{ .label = "+", .detail = "Inline index", .kind = .keyword },
    .{ .label = "-", .detail = "Inline unique", .kind = .keyword },
    .{ .label = "@", .detail = "Generated column", .kind = .keyword },
};

/// Extract the word being typed at cursor position (for prefix filtering).
fn wordAtCursor(text: []const u8, position: Position) []const u8 {
    var line_start: usize = 0;
    var current_line: u32 = 0;

    for (text, 0..) |c, i| {
        if (current_line == position.line) {
            const cursor_offset = i - line_start;
            const line = text[line_start .. line_start + cursor_offset];
            // Find the start of the current word (scan backward from cursor)
            var word_end = line.len;
            while (word_end > 0) : (word_end -= 1) {
                const wc = line[word_end - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_' or wc == '.') continue;
                break;
            }
            return line[word_end..];
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }
    return "";
}

/// Generate completion items based on cursor position and document context.
pub fn getCompletions(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: ?[]const u8) CompletionList {
    var items = std.ArrayList(CompletionItem).initCapacity(alloc, 64) catch return .{
        .is_incomplete = false,
        .items = &.{},
    };

    // Determine context from document text and cursor position
    const context = if (doc_text) |text| detectContext(text, position) else .top_level;
    const prefix = if (doc_text) |text| wordAtCursor(text, position) else "";

    switch (context) {
        .top_level => {
            // Offer keywords only
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
            // Offer type symbols and modifiers
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
            // Also offer table.column for FK references
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
            // Offer table names and table.column for FK references with prefix filtering
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
            // Offer table/template names
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
            // Offer generated column keywords
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
            // Offer comment template hints
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
        .items = items.items,
    };
}

/// Context type for cursor position in a .ss file.
const CompletionContext = enum {
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
fn detectContext(text: []const u8, position: Position) CompletionContext {
    // Find the line at cursor position
    var line_start: usize = 0;
    var current_line: u32 = 0;

    for (text, 0..) |c, i| {
        if (current_line == position.line) {
            // Found the target line — extract up to cursor position
            const cursor_offset = i - line_start;
            const line_text = text[line_start .. line_start + cursor_offset];
            const stripped = stripLineComments(line_text);
            const trimmed = std.mem.trim(u8, stripped, " \t\r\n");

            // Check for FK keyword context (FK anywhere on line, not just at end)
            if (std.mem.indexOf(u8, trimmed, "FK") != null) {
                return .after_fk_keyword;
            }

            // Check for template reference context (after %)
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '%') {
                return .after_percent;
            }

            // Check for generated column context (after @)
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '@') {
                return .after_at;
            }

            // Check for comment context (after #)
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '#') {
                return .after_hash;
            }

            // Check if we're inside a table body
            // Count braces, skipping comments and strings
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
                    // Skip to end of line
                    while (j < text.len and text[j] != '\n') j += 1;
                } else if (tc == '/' and j + 1 < text.len and text[j + 1] == '/') {
                    // Skip to end of line
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

    return .top_level;
}

// ─── Hover ──────────────────────────────────────────────────

/// Format a SqlType to a human-readable SQL string for hover display.
fn formatSqlTypeForHover(alloc: std.mem.Allocator, sql_type: anytype) []const u8 {
    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    sql_type.toSql(.mysql, &law.writer) catch return @tagName(sql_type);
    return law.toOwnedSlice() catch return @tagName(sql_type);
}

/// Format column flags as a human-readable string for hover display.
fn formatFlagsForHover(alloc: std.mem.Allocator, flags: anytype) []const u8 {
    var parts = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return "";
    if (flags.primary_key) parts.append(alloc, "PRIMARY KEY") catch {};
    if (flags.auto_increment) parts.append(alloc, "AUTO_INCREMENT") catch {};
    if (flags.nullable) parts.append(alloc, "NULL") catch {};
    if (flags.unsigned) parts.append(alloc, "UNSIGNED") catch {};
    if (flags.inline_unique) parts.append(alloc, "UNIQUE") catch {};
    if (flags.inline_index) parts.append(alloc, "INDEX") catch {};
    if (flags.is_enum) parts.append(alloc, "ENUM") catch {};
    if (flags.is_virtual) parts.append(alloc, "VIRTUAL") catch {};
    if (flags.is_stored) parts.append(alloc, "STORED") catch {};

    var law = std.Io.Writer.Allocating.init(alloc);
    defer law.deinit();
    for (parts.items, 0..) |p, i| {
        if (i > 0) law.writer.writeAll(" ") catch {};
        law.writer.writeAll(p) catch {};
    }
    return law.toOwnedSlice() catch return "";
}

/// Generate hover information for a position in the document.
pub fn getHover(alloc: std.mem.Allocator, ast: TypedAst, position: Position) ?Hover {
    const line = position.line;

    // Find the table containing this line
    for (ast.tables) |table| {
        const table_start: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;

        // Check if cursor is on the table declaration line
        if (line == table_start) {
            var aw = std.Io.Writer.Allocating.init(alloc);
            defer aw.deinit();
            aw.writer.print("**{s}**", .{table.name}) catch return null;
            if (table.comment) |c| {
                aw.writer.print("\n\n{s}", .{c}) catch {};
            }
            aw.writer.print("\n\n| Property | Value |", .{}) catch {};
            aw.writer.print("\n|----------|-------|", .{}) catch {};
            aw.writer.print("\n| Columns | {d} |", .{table.columns.len}) catch {};
            aw.writer.print("\n| Foreign Keys | {d} |", .{table.fks.len}) catch {};
            aw.writer.print("\n| Indexes | {d} |", .{table.indexes.len}) catch {};
            if (table.engine) |e| {
                aw.writer.print("\n| Engine | `{s}` |", .{e}) catch {};
            }
            // Show FK relationships
            if (table.fks.len > 0) {
                aw.writer.writeAll("\n\n**Relationships:**\n") catch {};
                for (table.fks) |fk| {
                    if (fk.fields.len > 0) {
                        aw.writer.print("- `{s}` → `{s}.{s}`", .{ fk.fields[0], fk.ref_table, if (fk.ref_fields.len > 0) fk.ref_fields[0] else "" }) catch {};
                        if (fk.actions.len > 0) {
                            aw.writer.writeAll(" (") catch {};
                            for (fk.actions, 0..) |action, ai| {
                                if (ai > 0) aw.writer.writeAll(", ") catch {};
                                aw.writer.print("{s} {s}", .{ @tagName(action.trigger), @tagName(action.action) }) catch {};
                            }
                            aw.writer.writeAll(")") catch {};
                        }
                        aw.writer.writeByte('\n') catch {};
                    }
                }
            }
            return .{
                .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                .range = makeRange(table_start, 0, table_start, @intCast(table.name.len)),
            };
        }

        // Check if cursor is on a column line
        for (table.columns) |col| {
            const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
            if (line == col_line) {
                var aw = std.Io.Writer.Allocating.init(alloc);
                defer aw.deinit();

                // Column name and type
                aw.writer.print("**{s}** : `{s}`", .{ col.name, @tagName(col.sql_type) }) catch return null;

                // Type size
                switch (col.sql_type) {
                    .varchar => |n| {
                        if (n > 0) aw.writer.print("({d})", .{n}) catch {};
                    },
                    .decimal => |ds| {
                        aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
                    },
                    else => {},
                }

                // SQL DDL snippet
                aw.writer.writeAll("\n\n```sql\n") catch {};
                aw.writer.print("{s} {s}", .{ col.name, @tagName(col.sql_type) }) catch {};
                switch (col.sql_type) {
                    .varchar => |n| {
                        if (n > 0) aw.writer.print("({d})", .{n}) catch {};
                    },
                    .decimal => |ds| {
                        aw.writer.print("({d},{d})", .{ ds.precision, ds.scale }) catch {};
                    },
                    else => {},
                }
                const flags_str = formatFlagsForHover(alloc, col.flags);
                if (flags_str.len > 0) {
                    aw.writer.print(" {s}", .{flags_str}) catch {};
                }
                if (col.default) |dflt| {
                    aw.writer.print(" DEFAULT {s}", .{dflt}) catch {};
                }
                aw.writer.writeAll("\n```\n") catch {};

                // Flags
                var flags = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return null;
                if (col.flags.primary_key) flags.append(alloc, "PRIMARY KEY") catch {};
                if (col.flags.auto_increment) flags.append(alloc, "AUTO_INCREMENT") catch {};
                if (col.flags.nullable) flags.append(alloc, "NULLABLE") catch {};
                if (col.flags.unsigned) flags.append(alloc, "UNSIGNED") catch {};
                if (col.flags.inline_unique) flags.append(alloc, "UNIQUE") catch {};
                if (col.flags.inline_index) flags.append(alloc, "INDEXED") catch {};
                if (col.flags.is_enum) flags.append(alloc, "ENUM") catch {};
                if (col.flags.is_virtual) flags.append(alloc, "VIRTUAL") catch {};
                if (col.flags.is_stored) flags.append(alloc, "STORED") catch {};

                if (flags.items.len > 0) {
                    aw.writer.writeAll("**Flags:** ") catch {};
                    for (flags.items, 0..) |f, i| {
                        if (i > 0) aw.writer.writeAll(", ") catch {};
                        aw.writer.print("`{s}`", .{f}) catch {};
                    }
                    aw.writer.writeByte('\n') catch {};
                }

                // Default value
                if (col.default) |dflt| {
                    aw.writer.print("\n**Default:** `{s}`", .{dflt}) catch {};
                }

                // Comment
                if (col.comment) |c| {
                    aw.writer.print("\n\n{s}", .{c}) catch {};
                }

                return .{
                    .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                    .range = makeRange(col_line, 0, col_line, @intCast(col.name.len)),
                };
            }
        }

        // Check if cursor is on a FK line (within the table's range)
        if (table_start <= line) {
            // Estimate FK line from FK list
            for (table.fks) |fk| {
                const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else 0;
                if (line == fk_line) {
                    var aw = std.Io.Writer.Allocating.init(alloc);
                    defer aw.deinit();
                    aw.writer.writeAll("**Foreign Key**\n\n") catch return null;
                    if (fk.fields.len > 0) {
                        aw.writer.print("Column: `{s}`\n", .{fk.fields[0]}) catch {};
                    }
                    aw.writer.print("Target: `{s}.{s}`\n", .{ fk.ref_table, if (fk.ref_fields.len > 0) fk.ref_fields[0] else "" }) catch {};
                    // Show actions
                    if (fk.actions.len > 0) {
                        aw.writer.writeAll("\n**Actions:**\n") catch {};
                        for (fk.actions) |action| {
                            aw.writer.print("- {s} {s}\n", .{ @tagName(action.trigger), @tagName(action.action) }) catch {};
                        }
                    }
                    return .{
                        .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                        .range = makeRange(fk_line, 0, fk_line, 4),
                    };
                }
            }
        }
    }

    // Check views
    for (ast.views) |view| {
        const view_line: u32 = if (view.line_no > 0) @intCast(view.line_no - 1) else 0;
        if (line == view_line) {
            var aw = std.Io.Writer.Allocating.init(alloc);
            defer aw.deinit();
            aw.writer.print("**View: {s}**", .{view.name}) catch return null;
            if (view.comment) |c| {
                aw.writer.print("\n\n{s}", .{c}) catch {};
            }
            // Show SQL definition
            aw.writer.writeAll("\n\n```sql\n") catch {};
            aw.writer.writeAll(view.query) catch {};
            aw.writer.writeAll("\n```\n") catch {};
            return .{
                .contents = .{ .kind = .markdown, .value = aw.toOwnedSlice() catch return null },
                .range = makeRange(view_line, 0, view_line, @intCast(view.name.len)),
            };
        }
    }

    return null;
}

// ─── Go-to-Definition ───────────────────────────────────────

/// Find the definition location for a symbol at the given position.
pub fn getDefinition(alloc: std.mem.Allocator, ast: TypedAst, uri: []const u8, position: Position) ?Location {
    _ = alloc;
    const line = position.line;

    // Find FK references that point to other tables
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            const fk_line: u32 = if (fk.line_no > 0) @intCast(fk.line_no - 1) else 0;
            if (line == fk_line) {
                // FK found — navigate to target table
                for (ast.tables) |target| {
                    if (std.mem.eql(u8, target.name, fk.ref_table)) {
                        const target_line: u32 = if (target.line_no > 0) @intCast(target.line_no - 1) else 0;
                        return .{
                            .uri = uri,
                            .range = makeRange(target_line, 0, target_line, @intCast(target.name.len)),
                        };
                    }
                }
            }
        }
    }

    // Check if cursor is on a column name that's a FK reference
    for (ast.tables) |table| {
        for (table.columns) |col| {
            const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
            if (line == col_line) {
                // Check if this column has an FK in the table
                for (table.fks) |fk| {
                    if (fk.fields.len > 0 and std.mem.eql(u8, fk.fields[0], col.name)) {
                        for (ast.tables) |target| {
                            if (std.mem.eql(u8, target.name, fk.ref_table)) {
                                const target_line: u32 = if (target.line_no > 0) @intCast(target.line_no - 1) else 0;
                                return .{
                                    .uri = uri,
                                    .range = makeRange(target_line, 0, target_line, @intCast(target.name.len)),
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    return null;
}

// ─── Code Actions ──────────────────────────────────────────

/// Generate code actions (quick fixes) for a given range and diagnostics.
pub fn getCodeActions(
    alloc: std.mem.Allocator,
    ast: TypedAst,
    diagnostics: []const Diagnostic,
    range: Range,
) []CodeAction {
    var actions = std.ArrayList(CodeAction).initCapacity(alloc, 8) catch return &.{};

    for (diagnostics) |diag| {
        // Only offer fixes for diagnostics in the selected range
        if (diag.range.start.line < range.start.line or diag.range.end.line > range.end.line) continue;

        // Missing PK suggestion
        if (std.mem.indexOf(u8, diag.message, "no primary key") != null) {
            // Find the table at this line
            for (ast.tables) |table| {
                const table_line: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
                if (table_line == diag.range.start.line and table.columns.len > 0) {
                    const first_col = table.columns[0];
                    const col_line: u32 = if (first_col.line_no > 0) @intCast(first_col.line_no - 1) else table_line;
                    // Build edit: append ++ to first column
                    var new_text_buf = std.Io.Writer.Allocating.init(alloc);
                    new_text_buf.writer.print("{s} ++", .{first_col.name}) catch continue;
                    const new_text = new_text_buf.toOwnedSlice() catch continue;

                    actions.append(alloc, .{
                        .title = "Add primary key to first column",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = makeRange(col_line, 0, col_line, @intCast(first_col.name.len)),
                            .new_text = new_text,
                        }} },
                    }) catch {};
                    break;
                }
            }
        }

        // Missing table comment suggestion
        if (std.mem.indexOf(u8, diag.message, "missing table comment") != null or
            std.mem.indexOf(u8, diag.message, "lacks a comment") != null)
        {
            for (ast.tables) |table| {
                const table_line: u32 = if (table.line_no > 0) @intCast(table.line_no - 1) else 0;
                if (table_line == diag.range.start.line) {
                    // Find the table name end position
                    const name_end: u32 = @intCast(table.name.len);
                    actions.append(alloc, .{
                        .title = "Add table comment",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = makeRange(table_line, name_end, table_line, name_end),
                            .new_text = " # Add a description here",
                        }} },
                    }) catch {};
                    break;
                }
            }
        }

        // Naming convention suggestion
        if (std.mem.indexOf(u8, diag.message, "should be snake_case") != null) {
            // Extract the table/column name from the diagnostic
            if (std.mem.indexOf(u8, diag.message, "\"")) |start_q| {
                const rest = diag.message[start_q + 1 ..];
                if (std.mem.indexOf(u8, rest, "\"")) |end_q| {
                    const name = rest[0..end_q];
                    const snake = toSnakeCase(alloc, name) catch continue;
                    actions.append(alloc, .{
                        .title = "Rename to snake_case",
                        .kind = .quick_fix,
                        .diagnostics = &.{diag},
                        .edit = .{ .changes = &.{.{
                            .range = diag.range,
                            .new_text = snake,
                        }} },
                    }) catch {};
                }
            }
        }
    }

    // Add FK index code action: check if any FK column lacks an index
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            if (fk.fields.len == 0) continue;
            const fk_col = fk.fields[0];

            // Check if this column has an inline index or standalone index
            var has_index = false;
            for (table.columns) |col| {
                if (std.mem.eql(u8, col.name, fk_col) and (col.flags.inline_index or col.flags.inline_unique)) {
                    has_index = true;
                    break;
                }
            }
            if (!has_index) {
                for (table.indexes) |idx| {
                    for (idx.fields) |f| {
                        if (std.mem.eql(u8, f, fk_col)) {
                            has_index = true;
                            break;
                        }
                    }
                    if (has_index) break;
                }
            }

            if (!has_index) {
                // Find the column line and offer to add + modifier
                for (table.columns) |col| {
                    if (std.mem.eql(u8, col.name, fk_col)) {
                        const col_line: u32 = if (col.line_no > 0) @intCast(col.line_no - 1) else 0;
                        const col_name_end: u32 = @intCast(col.name.len);
                        actions.append(alloc, .{
                            .title = "Add index for FK column",
                            .kind = .quick_fix,
                            .edit = .{ .changes = &.{.{
                                .range = makeRange(col_line, col_name_end, col_line, col_name_end),
                                .new_text = " +",
                            }} },
                        }) catch {};
                        break;
                    }
                }
            }
        }
    }

    return actions.items;
}

/// Convert camelCase or PascalCase to snake_case.
fn toSnakeCase(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).initCapacity(alloc, input.len * 2) catch return error.OutOfMemory;
    for (input, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) try result.append(alloc, '_');
            try result.append(alloc, std.ascii.toLower(c));
        } else {
            try result.append(alloc, c);
        }
    }
    return try result.toOwnedSlice(alloc);
}

// ─── Rename ──────────────────────────────────────────────

/// Result of a rename operation: list of edits to apply.
pub const RenameResult = struct {
    changes: []const TextEdit,
};

/// Check if rename is valid at the given position.
/// Returns the symbol name if rename is supported, null otherwise.
pub fn prepareRename(ast: TypedAst, position: Position, doc_text: []const u8) ?[]const u8 {
    const line = position.line;
    const character = position.character;

    // Extract the word at cursor position
    var line_start: usize = 0;
    var current_line: u32 = 0;
    for (doc_text, 0..) |c, i| {
        if (current_line == line) {
            const line_text = doc_text[line_start..i];
            if (character > line_text.len) return null;
            const before_cursor = line_text[0..character];
            // Find word boundaries
            var word_end = before_cursor.len;
            while (word_end > 0) : (word_end -= 1) {
                const wc = before_cursor[word_end - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            var word_start = word_end;
            while (word_start > 0) : (word_start -= 1) {
                const wc = before_cursor[word_start - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            const word = before_cursor[word_start..word_end];
            if (word.len == 0) return null;

            // Check if the word is a table name or column name
            for (ast.tables) |table| {
                if (std.mem.eql(u8, table.name, word)) return word;
                for (table.columns) |col| {
                    if (std.mem.eql(u8, col.name, word)) return word;
                }
            }
            return null;
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }
    return null;
}

/// Find all references to a symbol at the given position and return rename edits.
pub fn getRenameLinks(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: []const u8, new_name: []const u8) ?RenameResult {
    const line = position.line;
    const character = position.character;

    // Extract the word at cursor position
    var line_start: usize = 0;
    var current_line: u32 = 0;
    var old_name: ?[]const u8 = null;
    for (doc_text, 0..) |c, i| {
        if (current_line == line) {
            const line_text = doc_text[line_start..i];
            if (character > line_text.len) return null;
            const before_cursor = line_text[0..character];
            var word_end = before_cursor.len;
            while (word_end > 0) : (word_end -= 1) {
                const wc = before_cursor[word_end - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            var word_start = word_end;
            while (word_start > 0) : (word_start -= 1) {
                const wc = before_cursor[word_start - 1];
                if (std.ascii.isAlphanumeric(wc) or wc == '_') continue;
                break;
            }
            old_name = before_cursor[word_start..word_end];
            break;
        }
        if (c == '\n') {
            line_start = i + 1;
            current_line += 1;
        }
    }

    const name = old_name orelse return null;
    var edits = std.ArrayList(TextEdit).initCapacity(alloc, 16) catch return null;

    // Scan all lines for references to the old name
    line_start = 0;
    current_line = 0;
    for (doc_text, 0..) |c, i| {
        const is_last = i == doc_text.len - 1;
        const line_text = if (is_last) doc_text[line_start..] else doc_text[line_start..i];

        // Find all occurrences of the old name in this line
        var search_start: usize = 0;
        while (search_start < line_text.len) {
            const pos = std.mem.indexOf(u8, line_text[search_start..], name) orelse break;
            const abs_pos = search_start + pos;

            // Check word boundaries
            const before_ok = abs_pos == 0 or !std.ascii.isAlphanumeric(doc_text[line_start + abs_pos - 1]);
            const after_end = line_start + abs_pos + name.len;
            const after_ok = after_end >= doc_text.len or !std.ascii.isAlphanumeric(doc_text[after_end]);

            if (before_ok and after_ok) {
                // Determine what kind of reference this is
                const is_table_decl = isTableDeclaration(line_text, name);
                const is_fk_ref = isFkReference(line_text, name, ast);

                // Only rename table declarations, column declarations, and FK references
                if (is_table_decl or is_fk_ref) {
                    edits.append(alloc, .{
                        .range = makeRange(current_line, @intCast(abs_pos), current_line, @intCast(abs_pos + name.len)),
                        .new_text = new_name,
                    }) catch {};
                }
            }

            search_start = abs_pos + 1;
        }

        if (c == '\n' or is_last) {
            line_start = i + 1;
            current_line += 1;
        }
    }

    if (edits.items.len == 0) return null;
    return .{ .changes = edits.items };
}

/// Check if a line is a table declaration for the given name.
fn isTableDeclaration(line_text: []const u8, name: []const u8) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    // Table declarations start with "table <name>" or "template <name>" or "view <name>"
    if (std.mem.startsWith(u8, trimmed, "table ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "template ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    if (std.mem.startsWith(u8, trimmed, "view ") and std.mem.indexOf(u8, trimmed, name) != null) return true;
    return false;
}

/// Check if a line is an FK reference to the given name.
fn isFkReference(line_text: []const u8, name: []const u8, ast: TypedAst) bool {
    const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
    // FK references: "FK col → table" or "FK col → table.col"
    if (std.mem.indexOf(u8, trimmed, "FK") == null) return false;
    // Check if the name appears as a table reference in any FK
    for (ast.tables) |table| {
        for (table.fks) |fk| {
            if (std.mem.eql(u8, fk.ref_table, name)) return true;
            for (fk.ref_fields) |rf| {
                if (std.mem.eql(u8, rf, name)) return true;
            }
            for (fk.fields) |f| {
                if (std.mem.eql(u8, f, name)) return true;
            }
        }
    }
    return false;
}

// ─── Document Formatting ───────────────────────────────────

/// Format the entire document using the Rune formatter.
/// Returns the formatted text, or null on error.
pub fn getFormatting(alloc: std.mem.Allocator, text: []const u8) ?[]const u8 {
    const formatter = @import("../formatter.zig");
    return formatter.format(alloc, text) catch null;
}

// ─── Helpers ────────────────────────────────────────────────

fn makeRange(start_line: u32, start_char: u32, end_line: u32, end_char: u32) Range {
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "DocumentSymbols: empty schema" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    try std.testing.expectEqual(@as(usize, 0), symbols.len);
}

test "DocumentSymbols: single table" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = "User accounts",
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true, .auto_increment = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                    .{
                        .name = "name",
                        .sql_type = .{ .varchar = 255 },
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 3,
                    },
                },
                .fks = &.{
                    .{
                        .fields = &.{"user_id"},
                        .ref_table = "users",
                        .ref_fields = &.{"id"},
                        .actions = &.{},
                        .line_no = 5,
                    },
                },
                .indexes = &.{
                    .{
                        .kind = .regular,
                        .name = "idx_name",
                        .fields = &.{"name"},
                        .descending = &.{false},
                        .line_no = 6,
                    },
                },
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    defer std.testing.allocator.free(symbols);

    try std.testing.expectEqual(@as(usize, 1), symbols.len);
    try std.testing.expectEqualStrings("users", symbols[0].name);
    try std.testing.expectEqual(SymbolKind.class, symbols[0].kind);
    try std.testing.expect(symbols[0].children != null);
    // 2 columns + 1 FK + 1 index = 4 children
    try std.testing.expectEqual(@as(usize, 4), symbols[0].children.?.len);
}

test "Completion: offers keywords and types" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 0, .character = 0 }, null);
    defer {
        for (list.items) |item| {
            if (item.detail) |d| std.testing.allocator.free(d);
            if (item.documentation) |doc| std.testing.allocator.free(doc);
            if (item.insert_text) |it| std.testing.allocator.free(it);
        }
        std.testing.allocator.free(list.items);
    }

    // Should have keywords + type symbols + modifiers
    try std.testing.expect(list.items.len > 20);
}

test "Hover: table hover" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = "User accounts",
                .engine = null,
                .columns = &.{.{
                    .name = "id",
                    .sql_type = .int,
                    .flags = .{ .primary_key = true },
                    .default = null,
                    .check = null,
                    .comment = null,
                    .enum_values = &.{},
                    .line_no = 2,
                }},
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = getHover(std.testing.allocator, ast, .{ .line = 0, .character = 0 });
    try std.testing.expect(result != null);
    if (result) |h| {
        try std.testing.expectEqual(MarkupKind.markdown, h.contents.kind);
        try std.testing.expect(std.mem.indexOf(u8, h.contents.value, "users") != null);
    }
}

test "CodeActions: empty diagnostics" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const actions = getCodeActions(std.testing.allocator, ast, &.{}, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 10, .character = 0 },
    });
    try std.testing.expectEqual(@as(usize, 0), actions.len);
}

test "CodeActions: missing PK suggestion" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const diags = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .warning,
            .message = "Table 'users' has no primary key",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    try std.testing.expect(actions.len > 0);
}

test "toSnakeCase" {
    const result1 = try toSnakeCase(std.testing.allocator, "userName");
    defer std.testing.allocator.free(result1);
    try std.testing.expectEqualStrings("user_name", result1);

    const result2 = try toSnakeCase(std.testing.allocator, "UserName");
    defer std.testing.allocator.free(result2);
    try std.testing.expectEqualStrings("user_name", result2);

    const result3 = try toSnakeCase(std.testing.allocator, "already_snake");
    defer std.testing.allocator.free(result3);
    try std.testing.expectEqualStrings("already_snake", result3);
}

test "Completion: context-sensitive top level" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    // Top-level context: should offer keywords
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 0, .character = 0 }, "table users {\n");
    defer {
        for (list.items) |item| {
            if (item.detail) |d| std.testing.allocator.free(d);
            if (item.documentation) |doc| std.testing.allocator.free(doc);
            if (item.insert_text) |it| std.testing.allocator.free(it);
        }
        std.testing.allocator.free(list.items);
    }
    // Should have keywords (table, view, template, enum, etc.)
    var has_table_kw = false;
    for (list.items) |item| {
        if (std.mem.eql(u8, item.label, "table")) {
            has_table_kw = true;
            break;
        }
    }
    try std.testing.expect(has_table_kw);
}

test "Completion: context-sensitive inside table" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    // Inside table context: should offer type symbols
    const list = getCompletions(std.testing.allocator, ast, .{ .line = 1, .character = 2 }, "table users {\n  ");
    defer {
        for (list.items) |item| {
            if (item.detail) |d| std.testing.allocator.free(d);
            if (item.documentation) |doc| std.testing.allocator.free(doc);
            if (item.insert_text) |it| std.testing.allocator.free(it);
        }
        std.testing.allocator.free(list.items);
    }
    // Should have type symbols (n, i, s, etc.)
    var has_type = false;
    for (list.items) |item| {
        if (std.mem.eql(u8, item.label, "n")) {
            has_type = true;
            break;
        }
    }
    try std.testing.expect(has_type);
}

test "CodeActions: multiple diagnostics" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "orders",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{},
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const diags = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .warning,
            .message = "Table 'orders' has no primary key",
        },
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 10 },
            },
            .severity = .info,
            .message = "Consider adding timestamps",
        },
    };
    const actions = getCodeActions(std.testing.allocator, ast, &diags, .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 0 },
    });
    // Should produce at least one action (add PK) from the diagnostics
    try std.testing.expect(actions.len > 0);
}

test "Hover: column hover" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "email",
                        .sql_type = .varchar,
                        .flags = .{ .unique = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 3,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const result = getHover(std.testing.allocator, ast, .{ .line = 2, .character = 2 });
    try std.testing.expect(result != null);
    if (result) |r| {
        defer std.testing.allocator.free(r.contents.value);
        // Should contain the column name and type
        try std.testing.expect(std.mem.indexOf(u8, r.contents.value, "email") != null);
    }
}

test "DocumentSymbols: multiple tables" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{
            .{
                .name = "users",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 2,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 1,
            },
            .{
                .name = "posts",
                .comment = null,
                .engine = null,
                .columns = &.{
                    .{
                        .name = "id",
                        .sql_type = .int,
                        .flags = .{ .primary_key = true },
                        .default = null,
                        .check = null,
                        .comment = null,
                        .enum_values = &.{},
                        .line_no = 5,
                    },
                },
                .fks = &.{},
                .indexes = &.{},
                .line_no = 4,
            },
        },
        .views = &.{},
        .sql_comments = &.{},
    };
    const symbols = getDocumentSymbols(std.testing.allocator, ast);
    // Should have symbols for both tables and their columns
    try std.testing.expect(symbols.len >= 4);
}
