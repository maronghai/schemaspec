const std = @import("std");
const json_utils = @import("json.zig");
const msg = @import("message.zig");

// ─── LSP Protocol Types ────────────────────────────────────────
// JSON-RPC 2.0 message types and LSP-specific structures.
// Uses std.json.Value for dynamic parsing of incoming messages.
//
// JSON utilities live in json.zig; message parsing in message.zig.
// This file re-exports everything for backward compatibility.

// ─── Re-exports from json.zig ──────────────────────────────────
pub const writeJsonString = json_utils.writeJsonString;
pub const writeJsonInt = json_utils.writeJsonInt;
pub const writeJsonField = json_utils.writeJsonField;
pub const writeJsonBool = json_utils.writeJsonBool;
pub const writeJsonNull = json_utils.writeJsonNull;
pub const writeJsonValue = json_utils.writeJsonValue;

// ─── Re-exports from message.zig ───────────────────────────────
pub const ParsedMessage = msg.ParsedMessage;
pub const parseMessage = msg.parseMessage;
pub const freeJsonValue = msg.freeJsonValue;
pub const getStringField = msg.getStringField;
pub const getIntField = msg.getIntField;
pub const getObjectField = msg.getObjectField;
pub const ErrorCode = msg.ErrorCode;

// ─── LSP Type Definitions ──────────────────────────────────────

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const DiagnosticSeverity = enum(u32) {
    error_sev = 1,
    warning = 2,
    information = 3,
    hint = 4,
};

pub const Diagnostic = struct {
    range: Range,
    severity: DiagnosticSeverity,
    source: []const u8 = "rune",
    message: []const u8,
};

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    diagnostics: []const Diagnostic,
};

pub const TextDocumentSyncKind = enum(u32) {
    none = 0,
    full = 1,
    incremental = 2,
};

// ─── Document Symbols ────────────────────────────────────────

pub const SymbolKind = enum(u32) {
    file = 1,
    module = 2,
    namespace = 3,
    package = 4,
    class = 5,
    method = 6,
    property = 7,
    field = 8,
    constructor = 9,
    enum_kind = 10,
    interface = 11,
    function = 12,
    variable = 13,
    constant = 14,
    string = 15,
    number = 16,
    boolean = 17,
    array = 18,
    object = 19,
    key = 20,
    null_kind = 21,
    enum_member = 22,
    struct_kind = 23,
    event = 24,
    operator = 25,
    type_parameter = 26,
};

pub const SymbolTag = enum(u32) {
    deprecated = 1,
};

pub const DocumentSymbol = struct {
    name: []const u8,
    detail: ?[]const u8 = null,
    kind: SymbolKind,
    range: Range,
    selection_range: Range,
    children: ?[]const DocumentSymbol = null,
    tags: ?[]const SymbolTag = null,
};

pub const DocumentSymbolParams = struct {
    text_document: TextDocumentIdentifier,
};

pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

// ─── Completion ──────────────────────────────────────────────

pub const CompletionItemKind = enum(u32) {
    text = 1,
    method = 2,
    function = 3,
    constructor = 4,
    field = 5,
    variable = 6,
    class = 7,
    interface = 8,
    module = 9,
    property = 10,
    unit = 11,
    value = 12,
    enum_kind = 13,
    keyword = 14,
    snippet = 15,
    color = 16,
    file = 17,
    reference = 18,
    folder = 19,
    enum_member = 20,
    constant = 21,
    struct_kind = 22,
    event = 23,
    operator = 24,
    type_parameter = 25,
};

pub const InsertTextFormat = enum(u32) {
    plain_text = 1,
    snippet = 2,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
    detail: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    insert_text: ?[]const u8 = null,
    insert_text_format: ?InsertTextFormat = null,
};

pub const CompletionList = struct {
    is_incomplete: bool,
    items: []const CompletionItem,
};

pub const CompletionParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
};

// ─── Hover ───────────────────────────────────────────────────

pub const MarkupKind = enum {
    markdown,
    plaintext,
};

pub const MarkupContent = struct {
    kind: MarkupKind,
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const HoverParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
};

// ─── Go-to-Definition ────────────────────────────────────────

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const DefinitionParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
};

// ─── Code Actions ──────────────────────────────────────────

pub const CodeActionKind = enum {
    quick_fix,
};

pub const TextEdit = struct {
    range: Range,
    new_text: []const u8,
};

pub const WorkspaceEdit = struct {
    changes: ?[]const TextEdit = null,
};

pub const CodeAction = struct {
    title: []const u8,
    kind: CodeActionKind,
    diagnostics: ?[]const Diagnostic = null,
    edit: ?WorkspaceEdit = null,
};

pub const CodeActionParams = struct {
    text_document: TextDocumentIdentifier,
    range: Range,
    context: CodeActionContext,
};

pub const CodeActionContext = struct {
    diagnostics: []const Diagnostic,
};

// ─── Document Formatting ──────────────────────────────────

pub const DocumentFormattingParams = struct {
    text_document: TextDocumentIdentifier,
};

pub const DocumentRangeFormattingParams = struct {
    text_document: TextDocumentIdentifier,
    range: Range,
};

// ─── Server Capabilities ────────────────────────────────────

pub const ServerCapabilities = struct {
    text_document_sync: ?TextDocumentSyncKind = .full,
    hover_provider: ?bool = null,
    completion_provider: ?bool = null,
    definition_provider: ?bool = null,
    document_symbol_provider: ?bool = null,
    code_action_provider: ?bool = null,
    formatting_provider: ?bool = null,
    rename_provider: ?bool = null,
    prepare_rename_provider: ?bool = null,
    references_provider: ?bool = null,
    document_highlight_provider: ?bool = null,
    folding_range_provider: ?bool = null,
    type_definition_provider: ?bool = null,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
};

// ─── Document Highlight ──────────────────────────────────────

pub const DocumentHighlightKind = enum(u32) {
    text = 1,
    read = 2,
    write = 3,
};

pub const DocumentHighlight = struct {
    range: Range,
    kind: DocumentHighlightKind,
};

// ─── Reference ───────────────────────────────────────────────

pub const Reference = struct {
    range: Range,
    is_definition: bool,
};

// ─── Folding Range ───────────────────────────────────────────

pub const FoldingRangeKind = enum {
    comment,
    imports,
    region,
};

pub const FoldingRange = struct {
    start_line: u32,
    start_character: ?u32 = null,
    end_line: u32,
    end_character: ?u32 = null,
    kind: ?FoldingRangeKind = null,
};

pub const FoldingRangeParams = struct {
    text_document: TextDocumentIdentifier,
};

// ─── Type Definition ─────────────────────────────────────────

pub const TypeDefinitionParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
};

// ─── Response Writers ──────────────────────────────────────────

/// Write a JSON-RPC success response.
pub fn writeResponse(w: anytype, id: i64, result: anytype) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try w.print("{d}", .{id});
    try w.writeAll(",\"result\":");
    try json_utils.writeJsonValue(w, result);
    try w.writeAll("}\n");
}

/// Write a JSON-RPC error response.
pub fn writeErrorResponse(w: anytype, id: ?i64, code: i32, message: []const u8) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |i| {
        try w.print("{d}", .{i});
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\"error\":{\"code\":");
    try w.print("{d}", .{code});
    try w.writeAll(",\"message\":");
    try json_utils.writeJsonString(w, message);
    try w.writeAll("}}\n");
}

/// Write a JSON-RPC notification (no id).
pub fn writeNotification(w: anytype, method: []const u8, params: anytype) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"method\":");
    try json_utils.writeJsonString(w, method);
    try w.writeAll(",\"params\":");
    try json_utils.writeJsonValue(w, params);
    try w.writeAll("}\n");
}

/// Write an InitializeResult as JSON.
pub fn writeInitializeResult(w: anytype, caps: ServerCapabilities) !void {
    try w.writeAll("{\"textDocumentSync\":");
    if (caps.text_document_sync) |sync| {
        try w.print("{d}", .{@intFromEnum(sync)});
    } else {
        try w.writeAll("0");
    }
    if (caps.hover_provider) |hp| {
        try w.writeAll(",\"hoverProvider\":");
        try w.writeAll(if (hp) "true" else "false");
    }
    if (caps.completion_provider) |cp| {
        try w.writeAll(",\"completionProvider\":");
        try w.writeAll(if (cp) "true" else "false");
    }
    if (caps.definition_provider) |dp| {
        try w.writeAll(",\"definitionProvider\":");
        try w.writeAll(if (dp) "true" else "false");
    }
    if (caps.document_symbol_provider) |dsp| {
        try w.writeAll(",\"documentSymbolProvider\":");
        try w.writeAll(if (dsp) "true" else "false");
    }
    if (caps.code_action_provider) |cap| {
        try w.writeAll(",\"codeActionProvider\":");
        try w.writeAll(if (cap) "true" else "false");
    }
    if (caps.formatting_provider) |fp| {
        try w.writeAll(",\"documentFormattingProvider\":");
        try w.writeAll(if (fp) "true" else "false");
    }
    if (caps.rename_provider) |rp| {
        try w.writeAll(",\"renameProvider\":");
        try w.writeAll(if (rp) "true" else "false");
    }
    if (caps.prepare_rename_provider) |prp| {
        try w.writeAll(",\"prepareRenameProvider\":");
        try w.writeAll(if (prp) "true" else "false");
    }
    try w.writeAll("}");
}

/// Write PublishDiagnosticsParams as JSON.
pub fn writePublishDiagnostics(w: anytype, params: PublishDiagnosticsParams) !void {
    try w.writeAll("{\"uri\":");
    try json_utils.writeJsonString(w, params.uri);
    try w.writeAll(",\"diagnostics\":[");
    for (params.diagnostics, 0..) |diag, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"range\":{\"start\":{\"line\":");
        try w.print("{d}", .{diag.range.start.line});
        try w.writeAll(",\"character\":");
        try w.print("{d}", .{diag.range.start.character});
        try w.writeAll("},\"end\":{\"line\":");
        try w.print("{d}", .{diag.range.end.line});
        try w.writeAll(",\"character\":");
        try w.print("{d}", .{diag.range.end.character});
        try w.writeAll("}},\"severity\":");
        try w.print("{d}", .{@intFromEnum(diag.severity)});
        try w.writeAll(",\"source\":");
        try json_utils.writeJsonString(w, diag.source);
        try w.writeAll(",\"message\":");
        try json_utils.writeJsonString(w, diag.message);
        try w.writeAll("}");
    }
    try w.writeAll("]}");
}

// ─── LSP Type Serializers ────────────────────────────────────

/// Write a DocumentSymbol as JSON.
pub fn writeDocumentSymbol(w: anytype, sym: DocumentSymbol) !void {
    try w.writeByte('{');
    try json_utils.writeJsonField(w, "name", sym.name);
    if (sym.detail) |d| {
        try w.writeByte(',');
        try json_utils.writeJsonField(w, "detail", d);
    }
    try w.writeByte(',');
    try json_utils.writeJsonInt(w, "kind", @intFromEnum(sym.kind));
    try w.writeByte(',');
    try writeRange(w, "range", sym.range);
    try w.writeByte(',');
    try writeRange(w, "selectionRange", sym.selection_range);
    if (sym.children) |children| {
        try w.writeAll(",\"children\":[");
        for (children, 0..) |child, i| {
            if (i > 0) try w.writeByte(',');
            try writeDocumentSymbol(w, child);
        }
        try w.writeByte(']');
    }
    try w.writeByte('}');
}

/// Write a Range as a named JSON field.
pub fn writeRange(w: anytype, key: []const u8, r: Range) !void {
    try json_utils.writeJsonString(w, key);
    try w.writeAll(":{\"start\":{\"line\":");
    try w.print("{d}", .{r.start.line});
    try w.writeAll(",\"character\":");
    try w.print("{d}", .{r.start.character});
    try w.writeAll("},\"end\":{\"line\":");
    try w.print("{d}", .{r.end.line});
    try w.writeAll(",\"character\":");
    try w.print("{d}", .{r.end.character});
    try w.writeAll("}}");
}

/// Write a CompletionList as JSON.
pub fn writeCompletionList(w: anytype, list: CompletionList) !void {
    try w.writeAll("{\"isIncomplete\":");
    try w.writeAll(if (list.is_incomplete) "true" else "false");
    try w.writeAll(",\"items\":[");
    for (list.items, 0..) |item, i| {
        if (i > 0) try w.writeByte(',');
        try writeCompletionItem(w, item);
    }
    try w.writeAll("]}");
}

/// Write a CompletionItem as JSON.
pub fn writeCompletionItem(w: anytype, item: CompletionItem) !void {
    try w.writeByte('{');
    try json_utils.writeJsonField(w, "label", item.label);
    try w.writeByte(',');
    try json_utils.writeJsonInt(w, "kind", @intFromEnum(item.kind));
    if (item.detail) |d| {
        try w.writeAll(",\"detail\":");
        try json_utils.writeJsonString(w, d);
    }
    if (item.documentation) |doc| {
        try w.writeAll(",\"documentation\":");
        try json_utils.writeJsonString(w, doc);
    }
    if (item.insert_text) |it| {
        try w.writeAll(",\"insertText\":");
        try json_utils.writeJsonString(w, it);
    }
    if (item.insert_text_format) |fmt| {
        try w.writeAll(",\"insertTextFormat\":");
        try w.print("{d}", .{@intFromEnum(fmt)});
    }
    try w.writeByte('}');
}

/// Write a Hover result as JSON.
pub fn writeHover(w: anytype, hover: Hover) !void {
    try w.writeByte('{');
    try w.writeAll("\"contents\":{\"kind\":");
    try json_utils.writeJsonString(w, switch (hover.contents.kind) {
        .markdown => "markdown",
        .plaintext => "plaintext",
    });
    try w.writeAll(",\"value\":");
    try json_utils.writeJsonString(w, hover.contents.value);
    try w.writeAll("}");
    if (hover.range) |r| {
        try w.writeByte(',');
        try writeRange(w, "range", r);
    }
    try w.writeByte('}');
}

/// Write a Location as JSON.
pub fn writeLocation(w: anytype, loc: Location) !void {
    try w.writeByte('{');
    try json_utils.writeJsonField(w, "uri", loc.uri);
    try w.writeByte(',');
    try writeRange(w, "range", loc.range);
    try w.writeByte('}');
}

/// Write a TextEdit as JSON.
pub fn writeTextEdit(w: anytype, edit: TextEdit) !void {
    try w.writeByte('{');
    try writeRange(w, "range", edit.range);
    try w.writeByte(',');
    try json_utils.writeJsonField(w, "newText", edit.new_text);
    try w.writeByte('}');
}

/// Write a CodeAction as JSON.
pub fn writeCodeAction(w: anytype, action: CodeAction, doc_uri: []const u8) !void {
    try w.writeByte('{');
    try json_utils.writeJsonField(w, "title", action.title);
    try w.writeByte(',');
    try json_utils.writeJsonField(w, "kind", switch (action.kind) {
        .quick_fix => "quickfix",
    });
    if (action.diagnostics) |diags| {
        try w.writeAll(",\"diagnostics\":[");
        for (diags, 0..) |diag, i| {
            if (i > 0) try w.writeByte(',');
            try w.writeAll("{\"range\":{\"start\":{\"line\":");
            try w.print("{d}", .{diag.range.start.line});
            try w.writeAll(",\"character\":");
            try w.print("{d}", .{diag.range.start.character});
            try w.writeAll("},\"end\":{\"line\":");
            try w.print("{d}", .{diag.range.end.line});
            try w.writeAll(",\"character\":");
            try w.print("{d}", .{diag.range.end.character});
            try w.writeAll("}},\"severity\":");
            try w.print("{d}", .{@intFromEnum(diag.severity)});
            try w.writeAll(",\"source\":");
            try json_utils.writeJsonString(w, diag.source);
            try w.writeAll(",\"message\":");
            try json_utils.writeJsonString(w, diag.message);
            try w.writeAll("}");
        }
        try w.writeByte(']');
    }
    if (action.edit) |edit| {
        try w.writeAll(",\"edit\":{\"changes\":{");
        if (edit.changes) |changes| {
            for (changes, 0..) |tc, i| {
                if (i > 0) try w.writeByte(',');
                try w.writeByte('"');
                try json_utils.writeJsonString(w, doc_uri);
                try w.writeAll("\":[");
                try writeTextEdit(w, tc);
                try w.writeByte(']');
            }
        }
        try w.writeAll("}}");
    }
    try w.writeByte('}');
}

/// Write a DocumentHighlight as JSON.
pub fn writeDocumentHighlight(w: anytype, highlight: DocumentHighlight) !void {
    try w.writeByte('{');
    try writeRange(w, "range", highlight.range);
    try w.writeAll(",\"kind\":");
    try w.print("{d}", .{@intFromEnum(highlight.kind)});
    try w.writeByte('}');
}

/// Write a Reference (Location with optional context) as JSON.
pub fn writeReference(w: anytype, ref: Reference) !void {
    try w.writeByte('{');
    try writeRange(w, "range", ref.range);
    if (ref.is_definition) {
        try w.writeAll(",\"context\":{\"includeDeclaration\":true}");
    }
    try w.writeByte('}');
}

// ─── Tests ─────────────────────────────────────────────────────

test "writeResponse" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeResponse(&aw.writer, 1, .{});
    try std.testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n", aw.written());
}

test "writeErrorResponse" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeErrorResponse(&aw.writer, 1, ErrorCode.method_not_found, "Method not found");
    try std.testing.expect(
        std.mem.indexOf(u8, aw.written(), "\"code\":-32601") != null,
    );
}

test "writeInitializeResult" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeInitializeResult(&aw.writer, .{ .text_document_sync = .full });
    const output = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"textDocumentSync\":1") != null);
}

test "writePublishDiagnostics" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const diagnostics = [_]Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 5 },
            },
            .severity = .error_sev,
            .message = "Syntax error",
        },
    };

    try writePublishDiagnostics(&aw.writer, .{
        .uri = "file:///test.ss",
        .diagnostics = &diagnostics,
    });

    const output = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"severity\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"message\":\"Syntax error\"") != null);
}
