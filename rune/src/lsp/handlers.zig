const std = @import("std");
const lsp_protocol = @import("protocol.zig");
const features_mod = @import("features.zig");
const dialect_enum = @import("../dialect/enum.zig");

// ─── LSP Request Handlers ─────────────────────────────────────
// Extracted from server.zig for maintainability.
// Each handler receives the Server pointer, stdout file, request id, and params.

pub const Server = @import("server.zig").Server;

/// Safely cast an i64 LSP position value to u32.
/// Returns 0 if the value is out of range (negative or > max u32).
/// LSP protocol uses i64 for positions, but practical positions fit in u32.
fn safePositionCast(val: i64) u32 {
    if (val < 0) return 0;
    if (val > std.math.maxInt(u32)) return std.math.maxInt(u32);
    return @intCast(val);
}

/// Parsed LSP position (line and character, zero-based).
/// Re-exported from protocol.zig for backward compatibility.
const Position = lsp_protocol.Position;

/// Extract line and character from LSP position params.
/// Returns null if position is missing from params.
fn parsePosition(params: std.json.Value) ?Position {
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return null;
    return .{
        .line = safePositionCast(lsp_protocol.getIntField(pos_val, "line") orelse 0),
        .character = safePositionCast(lsp_protocol.getIntField(pos_val, "character") orelse 0),
    };
}

/// Extract document URI from LSP params (textDocument.uri pattern).
/// Returns null if textDocument or uri is missing.
fn parseDocumentUri(params: std.json.Value) ?[]const u8 {
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return null;
    return lsp_protocol.getStringField(text_doc, "uri");
}

pub fn handleInitialize(self: *Server, stdout_file: anytype, id: ?i64, params: ?std.json.Value) !void {
    const rid = id orelse return;

    // Read dialect from initializationOptions
    if (params) |p| {
        if (lsp_protocol.getObjectField(p, "initializationOptions")) |opts| {
            if (lsp_protocol.getStringField(opts, "dialect")) |dialect_str| {
                self.dialect = dialect_enum.parseDialect(dialect_str) catch .mysql;
            }
        }
    }

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try lsp_protocol.writeInitializeResult(&body_alloc.writer, .{
        .text_document_sync = .full,
        .hover_provider = true,
        .completion_provider = true,
        .definition_provider = true,
        .document_symbol_provider = true,
        .code_action_provider = true,
        .formatting_provider = true,
        .rename_provider = true,
        .prepare_rename_provider = true,
        .references_provider = true,
        .document_highlight_provider = true,
        .folding_range_provider = true,
        .type_definition_provider = true,
        .workspace_symbol_provider = true,
        .signature_help_provider = true,
        .inlay_hint_provider = true,
        .code_lens_provider = true,
    });
    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleShutdown(self: *Server, stdout_file: anytype, id: ?i64) !void {
    const rid = id orelse return;
    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeAll("null");
    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleDidOpen(self: *Server, params: std.json.Value) !void {
    const uri = parseDocumentUri(params) orelse return;
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const version: u32 = @intCast(lsp_protocol.getIntField(text_doc, "version") orelse 1);
    const text = lsp_protocol.getStringField(text_doc, "text") orelse return;
    const language_id = lsp_protocol.getStringField(text_doc, "languageId") orelse "rune";

    try self.documents.open(uri, version, text, language_id);
    try self.compileAndPublishDiagnostics(uri);
}

pub fn handleDidChange(self: *Server, params: std.json.Value) !void {
    const uri = parseDocumentUri(params) orelse return;
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const version: u32 = @intCast(lsp_protocol.getIntField(text_doc, "version") orelse 1);

    // Full sync: contentChanges contains the full document text
    const content_changes = lsp_protocol.getObjectField(params, "contentChanges") orelse return;
    if (content_changes != .array) return;
    if (content_changes.array.items.len == 0) return;
    const first_change = content_changes.array.items[0];
    const text = lsp_protocol.getStringField(first_change, "text") orelse return;

    try self.documents.change(uri, version, text);

    // Recompile on change
    try self.compileAndPublishDiagnostics(uri);
}

pub fn handleDidClose(self: *Server, params: std.json.Value) !void {
    const uri = parseDocumentUri(params) orelse return;

    self.documents.close(uri);

    // Clear cached compile result
    if (self.compile_results.fetchRemove(uri)) |kv| {
        self.arena.free(kv.value.diagnostics);
        self.arena.free(kv.key);
    }

    // Publish empty diagnostics to clear errors
    try self.publishDiagnostics(uri, &.{});
}

pub fn handleDidSave(self: *Server, params: std.json.Value) !void {
    const uri = parseDocumentUri(params) orelse return;

    // Recompile on save
    try self.compileAndPublishDiagnostics(uri);
}

// ─── Feature Handlers ────────────────────────────────────────

pub fn handleDocumentSymbol(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;

    const typed = self.getTypedAst(uri);

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeByte('[');
    if (typed) |t| {
        const symbols = features_mod.getDocumentSymbols(self.arena, t);
        for (symbols, 0..) |sym, i| {
            if (i > 0) try body_alloc.writer.writeByte(',');
            try lsp_protocol.writeDocumentSymbol(&body_alloc.writer, sym);
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleCompletion(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const typed = self.getTypedAst(uri);

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        const doc = self.documents.get(uri);
        const doc_text = if (doc) |d| d.text else null;
        const list = features_mod.getCompletions(self.arena, t, .{ .line = pos.line, .character = pos.character }, doc_text);
        try lsp_protocol.writeCompletionList(&body_alloc.writer, list);
    } else {
        try body_alloc.writer.writeAll("{\"isIncomplete\":false,\"items\":[]}");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleHover(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getHover(self.arena, t, .{ .line = pos.line, .character = pos.character }, self.dialect)) |hover| {
            try lsp_protocol.writeHover(&body_alloc.writer, hover);
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleDefinition(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getDefinition(self.arena, t, uri, .{ .line = pos.line, .character = pos.character })) |loc| {
            try lsp_protocol.writeLocation(&body_alloc.writer, loc);
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleCodeAction(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const range_val = lsp_protocol.getObjectField(params, "range") orelse return;
    const start_val = lsp_protocol.getObjectField(range_val, "start") orelse return;
    const end_val = lsp_protocol.getObjectField(range_val, "end") orelse return;
    const start_line: u32 = safePositionCast(lsp_protocol.getIntField(start_val, "line") orelse 0);
    const start_char: u32 = safePositionCast(lsp_protocol.getIntField(start_val, "character") orelse 0);
    const end_line: u32 = safePositionCast(lsp_protocol.getIntField(end_val, "line") orelse 0);
    const end_char: u32 = safePositionCast(lsp_protocol.getIntField(end_val, "character") orelse 0);

    // Get diagnostics from context
    var diagnostics = std.ArrayList(lsp_protocol.Diagnostic).initCapacity(self.arena, 8) catch return;
    if (lsp_protocol.getObjectField(params, "context")) |ctx| {
        if (lsp_protocol.getObjectField(ctx, "diagnostics")) |diags_val| {
            if (diags_val == .array) {
                for (diags_val.array.items) |d| {
                    const msg = lsp_protocol.getStringField(d, "message") orelse "";
                    const sev_val = lsp_protocol.getIntField(d, "severity") orelse 1;
                    const range = if (lsp_protocol.getObjectField(d, "range")) |r| blk: {
                        const s = lsp_protocol.getObjectField(r, "start") orelse break :blk lsp_protocol.Range{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 0 } };
                        const e = lsp_protocol.getObjectField(r, "end") orelse break :blk lsp_protocol.Range{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 0 } };
                        break :blk lsp_protocol.Range{
                            .start = .{ .line = safePositionCast(lsp_protocol.getIntField(s, "line") orelse 0), .character = safePositionCast(lsp_protocol.getIntField(s, "character") orelse 0) },
                            .end = .{ .line = safePositionCast(lsp_protocol.getIntField(e, "line") orelse 0), .character = safePositionCast(lsp_protocol.getIntField(e, "character") orelse 0) },
                        };
                    } else lsp_protocol.Range{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 0 } };
                    diagnostics.append(self.arena, .{
                        .range = range,
                        .severity = switch (sev_val) {
                            1 => .error_sev,
                            2 => .warning,
                            3 => .information,
                            else => .hint,
                        },
                        .message = msg,
                    }) catch {};
                }
            }
        }
    }

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeByte('[');
    if (typed) |t| {
        const range = lsp_protocol.Range{
            .start = .{ .line = start_line, .character = start_char },
            .end = .{ .line = end_line, .character = end_char },
        };
        const actions = features_mod.getCodeActions(self.arena, t, diagnostics.items, range);
        for (actions, 0..) |action, i| {
            if (i > 0) try body_alloc.writer.writeByte(',');
            try lsp_protocol.writeCodeAction(&body_alloc.writer, action, uri);
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleFormatting(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;

    const doc = self.documents.get(uri) orelse {
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try body_alloc.writer.writeAll("[]");
        try self.sendResponse(stdout_file, rid, &body_alloc);
        return;
    };

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (features_mod.getFormattingDialect(self.arena, doc.text, self.dialect)) |new_text| {
        defer self.arena.free(new_text);
        const line_count: u32 = @intCast(std.mem.count(u8, doc.text, "\n") + 1);
        try body_alloc.writer.writeByte('[');
        try lsp_protocol.writeTextEdit(&body_alloc.writer, .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = line_count, .character = 0 },
            },
            .new_text = new_text,
        });
        try body_alloc.writer.writeByte(']');
    } else {
        try body_alloc.writer.writeAll("[]");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleRename(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;
    const new_name = lsp_protocol.getStringField(params, "newName") orelse return;

    const doc = self.documents.get(uri) orelse return;
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getRenameLinks(self.arena, t, .{ .line = pos.line, .character = pos.character }, doc.text, new_name)) |rename_result| {
            // Build WorkspaceEdit with changes
            try body_alloc.writer.writeAll("{\"changes\":{\"");
            try body_alloc.writer.writeAll(uri);
            try body_alloc.writer.writeAll("\":[");
            for (rename_result.changes, 0..) |edit, i| {
                if (i > 0) try body_alloc.writer.writeByte(',');
                try lsp_protocol.writeTextEdit(&body_alloc.writer, edit);
            }
            try body_alloc.writer.writeAll("]}}");
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handlePrepareRename(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const doc = self.documents.get(uri) orelse return;
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.prepareRename(t, .{ .line = pos.line, .character = pos.character }, doc.text)) |symbol_name| {
            // Return prepare rename result with placeholder
            try body_alloc.writer.writeAll("{\"placeholder\":\"");
            try body_alloc.writer.writeAll(symbol_name);
            try body_alloc.writer.writeAll("\"}");
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleReferences(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const doc = self.documents.get(uri);
    const doc_text = if (doc) |d| d.text else "";
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeByte('[');
    if (typed) |t| {
        const refs = features_mod.getReferences(self.arena, t, pos.line, pos.character, uri, doc_text);
        for (refs, 0..) |ref, i| {
            if (i > 0) try body_alloc.writer.writeByte(',');
            try body_alloc.writer.writeByte('{');
            try lsp_protocol.writeRange(&body_alloc.writer, "range", ref.range);
            try body_alloc.writer.writeAll(",\"uri\":\"");
            try body_alloc.writer.writeAll(uri);
            try body_alloc.writer.writeByte('"');
            if (ref.is_definition) {
                try body_alloc.writer.writeAll(",\"context\":{\"includeDeclaration\":true}");
            }
            try body_alloc.writer.writeByte('}');
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleDocumentHighlight(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos = parsePosition(params) orelse return;

    const doc = self.documents.get(uri);
    const doc_text = if (doc) |d| d.text else "";
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeByte('[');
    if (typed) |t| {
        const highlights = features_mod.getDocumentHighlights(self.arena, t, pos.line, pos.character, doc_text);
        for (highlights, 0..) |hl, i| {
            if (i > 0) try body_alloc.writer.writeByte(',');
            try body_alloc.writer.writeByte('{');
            try lsp_protocol.writeRange(&body_alloc.writer, "range", hl.range);
            try body_alloc.writer.writeAll(",\"kind\":");
            try body_alloc.writer.print("{d}", .{@intFromEnum(hl.kind)});
            try body_alloc.writer.writeByte('}');
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleFoldingRange(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;

    const doc = self.documents.get(uri);
    const doc_text = if (doc) |d| d.text else "";

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeByte('[');
    if (doc_text.len > 0) {
        const folding_range = @import("folding_range.zig");
        const ranges = folding_range.getFoldingRanges(self.arena, doc_text) catch &[_]lsp_protocol.FoldingRange{};
        for (ranges, 0..) |fr, i| {
            if (i > 0) try body_alloc.writer.writeByte(',');
            try body_alloc.writer.writeByte('{');
            try body_alloc.writer.print("\"startLine\":{d}", .{fr.start_line});
            if (fr.start_character) |sc| {
                try body_alloc.writer.print(",\"startCharacter\":{d}", .{sc});
            }
            try body_alloc.writer.print(",\"endLine\":{d}", .{fr.end_line});
            if (fr.end_character) |ec| {
                try body_alloc.writer.print(",\"endCharacter\":{d}", .{ec});
            }
            if (fr.kind) |kind| {
                try body_alloc.writer.writeAll(",\"kind\":\"");
                try body_alloc.writer.writeAll(@tagName(kind));
                try body_alloc.writer.writeByte('"');
            }
            try body_alloc.writer.writeByte('}');
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleTypeDefinition(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = safePositionCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = safePositionCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        const type_def = @import("type_definition.zig");
        const position = lsp_protocol.Position{ .line = line, .character = character };
        if (type_def.getTypeDefinition(self.arena, t, uri, position)) |loc| {
            try body_alloc.writer.writeByte('[');
            try body_alloc.writer.writeByte('{');
            try body_alloc.writer.writeAll("\"uri\":\"");
            try body_alloc.writer.writeAll(loc.uri);
            try body_alloc.writer.writeByte('"');
            try body_alloc.writer.writeByte(',');
            try lsp_protocol.writeRange(&body_alloc.writer, "range", loc.range);
            try body_alloc.writer.writeByte('}');
            try body_alloc.writer.writeByte(']');
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleWorkspaceSymbol(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const query = lsp_protocol.getStringField(params, "query") orelse "";

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);

    // Search all open documents
    try body_alloc.writer.writeByte('[');
    var first = true;
    var doc_iter = self.documents.documents.iterator();
    while (doc_iter.next()) |entry| {
        const uri = entry.key_ptr.*;
        const result = self.compile_results.get(uri);
        const typed = if (result) |r| r.typed_ast else null;
        if (typed) |t| {
            const ws = @import("workspace_symbol.zig");
            const symbols = ws.getWorkspaceSymbols(self.arena, t, uri, query);
            for (symbols) |sym| {
                if (!first) try body_alloc.writer.writeByte(',');
                first = false;
                try body_alloc.writer.writeByte('{');
                try lsp_protocol.writeJsonField(&body_alloc.writer, "name", sym.name);
                try body_alloc.writer.writeByte(',');
                try lsp_protocol.writeJsonInt(&body_alloc.writer, "kind", @intFromEnum(sym.kind));
                try body_alloc.writer.writeAll(",\"location\":{");
                try lsp_protocol.writeJsonField(&body_alloc.writer, "uri", sym.location.uri);
                try body_alloc.writer.writeByte(',');
                try lsp_protocol.writeRange(&body_alloc.writer, "range", sym.location.range);
                try body_alloc.writer.writeByte('}');
                if (sym.container_name) |cn| {
                    try body_alloc.writer.writeByte(',');
                    try lsp_protocol.writeJsonField(&body_alloc.writer, "containerName", cn);
                }
                try body_alloc.writer.writeByte('}');
            }
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleSignatureHelp(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = safePositionCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = safePositionCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const doc = self.documents.get(uri);
    const doc_text = if (doc) |d| d.text else "";
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        const sig_help = @import("signature_help.zig");
        const position = lsp_protocol.Position{ .line = line, .character = character };
        if (sig_help.getSignatureHelp(self.arena, t, doc_text, position)) |help| {
            try sig_help.writeSignatureHelp(&body_alloc.writer, help);
        } else {
            try body_alloc.writer.writeAll("null");
        }
    } else {
        try body_alloc.writer.writeAll("null");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleInlayHint(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        const inlay_hints = @import("inlay_hints.zig");
        const hints = inlay_hints.getInlayHints(self.arena, t, self.dialect) catch {
            try body_alloc.writer.writeAll("[]");
            try self.sendResponse(stdout_file, rid, &body_alloc);
            return;
        };
        try lsp_protocol.writeInlayHintArray(&body_alloc.writer, hints);
        // Note: hints are arena-allocated, no need to free individually
    } else {
        try body_alloc.writer.writeAll("[]");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleCodeLens(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const uri = parseDocumentUri(params) orelse return;

    const doc = self.documents.get(uri) orelse {
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try body_alloc.writer.writeAll("[]");
        try self.sendResponse(stdout_file, rid, &body_alloc);
        return;
    };

    const compile_result = self.compile_results.get(uri);
    const code_lens = @import("code_lens.zig");
    const lenses = code_lens.getCodeLens(self.arena, doc.text, compile_result) catch {
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try body_alloc.writer.writeAll("[]");
        try self.sendResponse(stdout_file, rid, &body_alloc);
        return;
    };

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    try body_alloc.writer.writeAll("[");
    for (lenses, 0..) |lens, i| {
        if (i > 0) try body_alloc.writer.writeByte(',');
        try body_alloc.writer.writeAll("{\"range\":{\"start\":{\"line\":");
        try body_alloc.writer.print("{d}", .{lens.line});
        try body_alloc.writer.writeAll(",\"character\":0},\"end\":{\"line\":");
        try body_alloc.writer.print("{d}", .{lens.line});
        try body_alloc.writer.writeAll(",\"character\":0}},\"command\":{\"title\":");
        try lsp_protocol.writeJsonString(&body_alloc.writer, lens.title);
        try body_alloc.writer.writeAll(",\"command\":");
        try lsp_protocol.writeJsonString(&body_alloc.writer, lens.command);
        try body_alloc.writer.writeAll("}}");
    }
    try body_alloc.writer.writeAll("]");

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

// ─── Unit Tests ────────────────────────────────────────────────

const testing = std.testing;

test "safePositionCast: zero" {
    try testing.expectEqual(@as(u32, 0), safePositionCast(0));
}

test "safePositionCast: positive value" {
    try testing.expectEqual(@as(u32, 42), safePositionCast(42));
}

test "safePositionCast: max u32" {
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), safePositionCast(std.math.maxInt(u32)));
}

test "safePositionCast: negative value clamps to 0" {
    try testing.expectEqual(@as(u32, 0), safePositionCast(-1));
    try testing.expectEqual(@as(u32, 0), safePositionCast(-100));
}

test "safePositionCast: overflow clamps to max u32" {
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), safePositionCast(std.math.maxInt(u32) + 1));
}

test "parsePosition: valid position" {
    var obj: std.json.ObjectMap = .empty;
    var pos_obj: std.json.ObjectMap = .empty;
    try pos_obj.put(testing.allocator, "line", .{ .integer = 5 });
    try pos_obj.put(testing.allocator, "character", .{ .integer = 10 });
    try obj.put(testing.allocator, "position", .{ .object = pos_obj });
    const params = std.json.Value{ .object = obj };
    const pos = parsePosition(params);
    try testing.expect(pos != null);
    try testing.expectEqual(@as(u32, 5), pos.?.line);
    try testing.expectEqual(@as(u32, 10), pos.?.character);
    pos_obj.deinit(testing.allocator);
    obj.deinit(testing.allocator);
}

test "parsePosition: missing position" {
    const params = std.json.Value{ .object = .{} };
    try testing.expect(parsePosition(params) == null);
}

test "parseDocumentUri: valid URI" {
    var obj: std.json.ObjectMap = .empty;
    var doc_obj: std.json.ObjectMap = .empty;
    try doc_obj.put(testing.allocator, "uri", .{ .string = "file:///tmp/schema.ss" });
    try obj.put(testing.allocator, "textDocument", .{ .object = doc_obj });
    const params = std.json.Value{ .object = obj };
    const uri = parseDocumentUri(params);
    try testing.expect(uri != null);
    try testing.expectEqualStrings("file:///tmp/schema.ss", uri.?);
    doc_obj.deinit(testing.allocator);
    obj.deinit(testing.allocator);
}

test "parseDocumentUri: missing textDocument" {
    const obj: std.json.ObjectMap = .empty;
    const params = std.json.Value{ .object = obj };
    try testing.expect(parseDocumentUri(params) == null);
}

test "parseDocumentUri: missing uri" {
    var obj: std.json.ObjectMap = .empty;
    const doc_obj: std.json.ObjectMap = .empty;
    try obj.put(testing.allocator, "textDocument", .{ .object = doc_obj });
    const params = std.json.Value{ .object = obj };
    try testing.expect(parseDocumentUri(params) == null);
    obj.deinit(testing.allocator);
}
