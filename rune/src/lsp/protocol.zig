const std = @import("std");

// ─── LSP Protocol Types ────────────────────────────────────────
// JSON-RPC 2.0 message types and LSP-specific structures.
// Uses std.json.Value for dynamic parsing of incoming messages.

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

// ─── Server Capabilities (expanded) ─────────────────────────

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
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
};

pub const ErrorCode = struct {
    pub const parse_error: i32 = -32700;
    pub const invalid_request: i32 = -32600;
    pub const method_not_found: i32 = -32601;
    pub const invalid_params: i32 = -32602;
    pub const internal_error: i32 = -32603;
};

// ─── JSON Helpers ──────────────────────────────────────────────

/// Write a JSON string value, escaping special characters.
pub fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}

/// Write a JSON integer field.
pub fn writeJsonInt(w: anytype, key: []const u8, value: anytype) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try w.print("{d}", .{value});
}

/// Write a JSON string field.
pub fn writeJsonField(w: anytype, key: []const u8, value: []const u8) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try writeJsonString(w, value);
}

/// Write a JSON bool field.
pub fn writeJsonBool(w: anytype, key: []const u8, value: bool) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try w.writeAll(if (value) "true" else "false");
}

/// Write a JSON null field.
pub fn writeJsonNull(w: anytype, key: []const u8) !void {
    try writeJsonString(w, key);
    try w.writeAll(":null");
}

// ─── Message Parsing ───────────────────────────────────────────

pub const ParsedMessage = struct {
    id: ?i64,
    method: ?[]const u8,
    params: ?std.json.Value,
    result: ?std.json.Value,
    error_obj: ?JsonRpcError,
    is_response: bool,

    pub const JsonRpcError = struct {
        code: i32,
        message: []const u8,
    };
};

/// Parse a JSON-RPC message from a JSON string.
/// Caller must free the returned ParsedMessage's allocations.
pub fn parseMessage(alloc: std.mem.Allocator, json_str: []const u8) !ParsedMessage {
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_str, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidMessage;

    const obj = root.object;

    const id: ?i64 = if (obj.get("id")) |v| switch (v) {
        .integer => |n| @intCast(n),
        .float => @intFromFloat(v.float),
        else => null,
    } else null;

    const method: ?[]const u8 = if (obj.get("method")) |v| switch (v) {
        .string => |s| try alloc.dupe(u8, s),
        else => null,
    } else null;

    const params: ?std.json.Value = if (obj.get("params")) |v| try cloneValue(alloc, v) else null;

    const result: ?std.json.Value = if (obj.get("result")) |v| try cloneValue(alloc, v) else null;

    const error_obj: ?ParsedMessage.JsonRpcError = if (obj.get("error")) |err_val| switch (err_val) {
        .object => |err_obj| .{
            .code = if (err_obj.get("code")) |c| switch (c) {
                .integer => @intCast(c.integer),
                else => ErrorCode.internal_error,
            } else ErrorCode.internal_error,
            .message = if (err_obj.get("message")) |m| switch (m) {
                .string => |s| try alloc.dupe(u8, s),
                else => "Unknown error",
            } else "Unknown error",
        },
        else => null,
    } else null;

    return .{
        .id = id,
        .method = method,
        .params = params,
        .result = result,
        .error_obj = error_obj,
        .is_response = obj.get("method") == null,
    };
}

/// Clone a JSON value into a new allocation.
fn cloneValue(alloc: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    return switch (val) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |n| .{ .integer = n },
        .float => |f| .{ .float = f },
        .string => |s| .{ .string = try alloc.dupe(u8, s) },
        .number_string => |s| .{ .number_string = try alloc.dupe(u8, s) },
        .array => |arr| {
            var new_arr = std.json.Array.init(alloc);
            for (arr.items) |item| {
                try new_arr.append(try cloneValue(alloc, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj: std.json.ObjectMap = .empty;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key = try alloc.dupe(u8, entry.key_ptr.*);
                const val_copy = try cloneValue(alloc, entry.value_ptr.*);
                try new_obj.put(alloc, key, val_copy);
            }
            return .{ .object = new_obj };
        },
    };
}

/// Extract a string field from a JSON object value.
pub fn getStringField(obj: std.json.Value, key: []const u8) ?[]const u8 {
    if (obj != .object) return null;
    if (obj.object.get(key)) |v| {
        if (v == .string) return v.string;
    }
    return null;
}

/// Extract an integer field from a JSON object value.
pub fn getIntField(obj: std.json.Value, key: []const u8) ?i64 {
    if (obj != .object) return null;
    if (obj.object.get(key)) |v| {
        if (v == .integer) return v.integer;
    }
    return null;
}

/// Get a nested object field.
pub fn getObjectField(obj: std.json.Value, key: []const u8) ?std.json.Value {
    if (obj != .object) return null;
    return obj.object.get(key);
}

// ─── Response Writing ──────────────────────────────────────────

/// Write a JSON-RPC success response.
pub fn writeResponse(w: anytype, id: i64, result: anytype) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try w.print("{d}", .{id});
    try w.writeAll(",\"result\":");
    try writeJsonValue(w, result);
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
    try writeJsonString(w, message);
    try w.writeAll("}}\n");
}

/// Write a JSON-RPC notification (no id).
pub fn writeNotification(w: anytype, method: []const u8, params: anytype) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"method\":");
    try writeJsonString(w, method);
    try w.writeAll(",\"params\":");
    try writeJsonValue(w, params);
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
    try writeJsonString(w, params.uri);
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
        try writeJsonString(w, diag.source);
        try w.writeAll(",\"message\":");
        try writeJsonString(w, diag.message);
        try w.writeAll("}");
    }
    try w.writeAll("]}");
}

// ─── LSP Response Writers ───────────────────────────────────

/// Write a DocumentSymbol as JSON.
pub fn writeDocumentSymbol(w: anytype, sym: DocumentSymbol) !void {
    try w.writeByte('{');
    try writeJsonField(w, "name", sym.name);
    if (sym.detail) |d| {
        try w.writeByte(',');
        try writeJsonField(w, "detail", d);
    }
    try w.writeByte(',');
    try writeJsonInt(w, "kind", @intFromEnum(sym.kind));
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
fn writeRange(w: anytype, key: []const u8, r: Range) !void {
    try writeJsonString(w, key);
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
    try writeJsonField(w, "label", item.label);
    try w.writeByte(',');
    try writeJsonInt(w, "kind", @intFromEnum(item.kind));
    if (item.detail) |d| {
        try w.writeAll(",\"detail\":");
        try writeJsonString(w, d);
    }
    if (item.documentation) |doc| {
        try w.writeAll(",\"documentation\":");
        try writeJsonString(w, doc);
    }
    if (item.insert_text) |it| {
        try w.writeAll(",\"insertText\":");
        try writeJsonString(w, it);
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
    try writeJsonString(w, switch (hover.contents.kind) {
        .markdown => "markdown",
        .plaintext => "plaintext",
    });
    try w.writeAll(",\"value\":");
    try writeJsonString(w, hover.contents.value);
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
    try writeJsonField(w, "uri", loc.uri);
    try w.writeByte(',');
    try writeRange(w, "range", loc.range);
    try w.writeByte('}');
}

/// Write a TextEdit as JSON.
pub fn writeTextEdit(w: anytype, edit: TextEdit) !void {
    try w.writeByte('{');
    try writeRange(w, "range", edit.range);
    try w.writeByte(',');
    try writeJsonField(w, "newText", edit.new_text);
    try w.writeByte('}');
}

/// Write a CodeAction as JSON.
pub fn writeCodeAction(w: anytype, action: CodeAction) !void {
    try w.writeByte('{');
    try writeJsonField(w, "title", action.title);
    try w.writeByte(',');
    try writeJsonField(w, "kind", switch (action.kind) {
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
            try writeJsonString(w, diag.source);
            try w.writeAll(",\"message\":");
            try writeJsonString(w, diag.message);
            try w.writeAll("}");
        }
        try w.writeByte(']');
    }
    if (action.edit) |edit| {
        try w.writeAll(",\"edit\":{\"changes\":{");
        if (edit.changes) |changes| {
            for (changes, 0..) |tc, i| {
                if (i > 0) try w.writeByte(',');
                try w.writeAll("\"file:///\":[");
                try writeTextEdit(w, tc);
                try w.writeByte(']');
            }
        }
        try w.writeAll("}}");
    }
    try w.writeByte('}');
}

/// Generic JSON value writer.
fn writeJsonValue(w: anytype, val: anytype) !void {
    const T = @TypeOf(val);
    if (T == std.json.Value) {
        switch (val) {
            .null => try w.writeAll("null"),
            .bool => |b| try w.writeAll(if (b) "true" else "false"),
            .integer => |n| try w.print("{d}", .{n}),
            .float => |f| try w.print("{d}", .{f}),
            .number_string => |s| try w.writeAll(s),
            .string => |s| try writeJsonString(w, s),
            .array => |arr| {
                try w.writeByte('[');
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try w.writeByte(',');
                    try writeJsonValue(w, item);
                }
                try w.writeByte(']');
            },
            .object => |obj| {
                try w.writeByte('{');
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try w.writeByte(',');
                    first = false;
                    try writeJsonString(w, entry.key_ptr.*);
                    try w.writeByte(':');
                    try writeJsonValue(w, entry.value_ptr.*);
                }
                try w.writeByte('}');
            },
        }
    } else if (T == []const u8) {
        try writeJsonString(w, val);
    } else if (T == bool) {
        try w.writeAll(if (val) "true" else "false");
    } else if (T == comptime_int or T == i64 or T == u64 or T == i32 or T == u32) {
        try w.print("{d}", .{val});
    } else {
        @compileError("Unsupported JSON value type: " ++ @typeName(T));
    }
}

// ─── Tests ─────────────────────────────────────────────────────

test "writeJsonString" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonString(&aw.writer, "hello");
    try std.testing.expectEqualStrings("\"hello\"", aw.written());

    aw.pos = 0;
    try writeJsonString(&aw.writer, "say \"hi\"");
    try std.testing.expectEqualStrings("\"say \\\"hi\\\"\"", aw.written());
}

test "writeJsonField" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonField(&aw.writer, "method", "initialize");
    try std.testing.expectEqualStrings("\"method\":\"initialize\"", aw.written());
}

test "writeJsonBool" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonBool(&aw.writer, "ok", true);
    try std.testing.expectEqualStrings("\"ok\":true", aw.written());
}

test "writeJsonNull" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonNull(&aw.writer, "val");
    try std.testing.expectEqualStrings("\"val\":null", aw.written());
}

test "parseMessage request" {
    const msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    );
    defer {
        if (msg.method) |m| std.testing.allocator.free(m);
        if (msg.params) |p| {
            _ = p;
        }
    }

    try std.testing.expectEqual(@as(?i64, 1), msg.id);
    try std.testing.expect(msg.method != null);
    try std.testing.expectEqualStrings("initialize", msg.method.?);
    try std.testing.expect(!msg.is_response);
}

test "parseMessage response" {
    const msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}
    );
    defer {
        if (msg.method) |m| std.testing.allocator.free(m);
        if (msg.params) |p| {
            _ = p;
        }
    }

    try std.testing.expectEqual(@as(?i64, 1), msg.id);
    try std.testing.expect(msg.is_response);
    try std.testing.expect(msg.result != null);
}

test "parseMessage notification" {
    const msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{}}
    );
    defer {
        if (msg.method) |m| std.testing.allocator.free(m);
        if (msg.params) |p| {
            _ = p;
        }
    }

    try std.testing.expect(msg.id == null);
    try std.testing.expect(msg.method != null);
    try std.testing.expectEqualStrings("textDocument/didOpen", msg.method.?);
    try std.testing.expect(!msg.is_response);
}

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
