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

/// Generate completion items based on cursor position and document context.
pub fn getCompletions(alloc: std.mem.Allocator, ast: TypedAst, position: Position, doc_text: ?[]const u8) CompletionList {
    var items = std.ArrayList(CompletionItem).initCapacity(alloc, 64) catch return .{
        .is_incomplete = false,
        .items = &.{},
    };

    // Determine context from document text and cursor position
    const context = if (doc_text) |text| detectContext(text, position) else .top_level;

    switch (context) {
        .top_level => {
            // Offer keywords only
            for (KEYWORDS) |kw| {
                items.append(alloc, .{
                    .label = kw.label,
                    .kind = kw.kind,
                    .detail = null,
                }) catch {};
            }
        },
        .inside_table => {
            // Offer type symbols and modifiers
            for (TYPE_SYMBOLS) |ts| {
                items.append(alloc, .{
                    .label = ts.label,
                    .kind = ts.kind,
                    .detail = ts.detail,
                    .documentation = ts.detail,
                }) catch {};
            }
            for (MODIFIERS) |mod| {
                items.append(alloc, .{
                    .label = mod.label,
                    .kind = mod.kind,
                    .detail = mod.detail,
                }) catch {};
            }
            // Also offer table.column for FK references
            for (ast.tables) |table| {
                for (table.columns) |col| {
                    var law = std.Io.Writer.Allocating.init(alloc);
                    law.writer.print("{s}.{s}", .{ table.name, col.name }) catch continue;
                    const label = law.toOwnedSlice() catch continue;
                    items.append(alloc, .{
                        .label = label,
                        .kind = .field,
                        .detail = formatColumnDetail(alloc, col),
                    }) catch {};
                }
            }
        },
        .after_fk_keyword => {
            // Offer table names and table.column for FK references
            for (ast.tables) |table| {
                items.append(alloc, .{
                    .label = table.name,
                    .kind = .class,
                    .detail = table.comment,
                }) catch {};
                for (table.columns) |col| {
                    var law = std.Io.Writer.Allocating.init(alloc);
                    law.writer.print("{s}.{s}", .{ table.name, col.name }) catch continue;
                    const label = law.toOwnedSlice() catch continue;
                    items.append(alloc, .{
                        .label = label,
                        .kind = .field,
                        .detail = formatColumnDetail(alloc, col),
                    }) catch {};
                }
            }
        },
        .after_percent => {
            // Offer table/template names
            for (ast.tables) |table| {
                items.append(alloc, .{
                    .label = table.name,
                    .kind = .class,
                    .detail = table.comment,
                }) catch {};
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
};

/// Detect the completion context from document text and cursor position.
fn detectContext(text: []const u8, position: Position) CompletionContext {
    // Find the line at cursor position
    var line_start: usize = 0;
    var current_line: u32 = 0;

    for (text, 0..) |c, i| {
        if (current_line == position.line) {
            // Found the target line
            const line_text = text[line_start..@min(i + 1, text.len)];

            // Check for FK keyword context
            const trimmed = std.mem.trim(u8, line_text, " \t\r\n");
            if (trimmed.len >= 2 and std.mem.eql(u8, trimmed[trimmed.len - 2 ..], "FK")) {
                return .after_fk_keyword;
            }

            // Check for template reference context (after %)
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '%') {
                return .after_percent;
            }

            // Check if we're inside a table body
            // Simple heuristic: count braces
            var brace_depth: u32 = 0;
            for (text, 0..) |tc, ti| {
                if (ti > i) break;
                if (tc == '{') brace_depth += 1;
                if (tc == '}') {
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
            aw.writer.print("\n\n- Columns: {d}", .{table.columns.len}) catch {};
            aw.writer.print("\n- Foreign Keys: {d}", .{table.fks.len}) catch {};
            aw.writer.print("\n- Indexes: {d}", .{table.indexes.len}) catch {};
            if (table.engine) |e| {
                aw.writer.print("\n- Engine: {s}", .{e}) catch {};
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

                aw.writer.writeAll("\n\n") catch return null;

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
                    aw.writer.print("Target: `{s}.{s}`", .{ fk.ref_table, if (fk.ref_fields.len > 0) fk.ref_fields[0] else "" }) catch {};
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
                            .new_text = " # TODO: add description",
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
