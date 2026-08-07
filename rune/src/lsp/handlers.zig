const std = @import("std");
const lsp_protocol = @import("protocol.zig");
const features_mod = @import("features.zig");
const dialect_enum = @import("../dialect/enum.zig");

// ─── LSP Request Handlers ─────────────────────────────────────
// Extracted from server.zig for maintainability.
// Each handler receives the Server pointer, stdout file, request id, and params.

pub const Server = @import("server.zig").Server;

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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const version: u32 = @intCast(lsp_protocol.getIntField(text_doc, "version") orelse 1);
    const text = lsp_protocol.getStringField(text_doc, "text") orelse return;
    const language_id = lsp_protocol.getStringField(text_doc, "languageId") orelse "rune";

    try self.documents.open(uri, version, text, language_id);
    try self.compileAndPublishDiagnostics(uri);
}

pub fn handleDidChange(self: *Server, params: std.json.Value) !void {
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const version: u32 = @intCast(lsp_protocol.getIntField(text_doc, "version") orelse 1);

    // Full sync: contentChanges contains the full document text
    const content_changes = lsp_protocol.getObjectField(params, "contentChanges") orelse return;
    if (content_changes != .array) return;
    if (content_changes.array.items.len == 0) return;
    const first_change = content_changes.array.items[0];
    const text = lsp_protocol.getStringField(first_change, "text") orelse return;

    try self.documents.change(uri, version, text);
    try self.compileAndPublishDiagnostics(uri);
}

pub fn handleDidClose(self: *Server, params: std.json.Value) !void {
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;

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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;

    // Recompile on save
    try self.compileAndPublishDiagnostics(uri);
}

// ─── Feature Handlers ────────────────────────────────────────

pub fn handleDocumentSymbol(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = @intCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = @intCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        const doc = self.documents.get(uri);
        const doc_text = if (doc) |d| d.text else null;
        const list = features_mod.getCompletions(self.arena, t, .{ .line = line, .character = character }, doc_text);
        try lsp_protocol.writeCompletionList(&body_alloc.writer, list);
    } else {
        try body_alloc.writer.writeAll("{\"isIncomplete\":false,\"items\":[]}");
    }

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleHover(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = @intCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = @intCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getHover(self.arena, t, .{ .line = line, .character = character })) |hover| {
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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = @intCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = @intCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getDefinition(self.arena, t, uri, .{ .line = line, .character = character })) |loc| {
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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const range_val = lsp_protocol.getObjectField(params, "range") orelse return;
    const start_val = lsp_protocol.getObjectField(range_val, "start") orelse return;
    const end_val = lsp_protocol.getObjectField(range_val, "end") orelse return;
    const start_line: u32 = @intCast(lsp_protocol.getIntField(start_val, "line") orelse 0);
    const start_char: u32 = @intCast(lsp_protocol.getIntField(start_val, "character") orelse 0);
    const end_line: u32 = @intCast(lsp_protocol.getIntField(end_val, "line") orelse 0);
    const end_char: u32 = @intCast(lsp_protocol.getIntField(end_val, "character") orelse 0);

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
                            .start = .{ .line = @intCast(@max(0, lsp_protocol.getIntField(s, "line") orelse 0)), .character = @intCast(@max(0, lsp_protocol.getIntField(s, "character") orelse 0)) },
                            .end = .{ .line = @intCast(@max(0, lsp_protocol.getIntField(e, "line") orelse 0)), .character = @intCast(@max(0, lsp_protocol.getIntField(e, "character") orelse 0)) },
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
            try lsp_protocol.writeCodeAction(&body_alloc.writer, action);
        }
    }
    try body_alloc.writer.writeByte(']');

    try self.sendResponse(stdout_file, rid, &body_alloc);
}

pub fn handleFormatting(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
    const rid = id orelse return;
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;

    const doc = self.documents.get(uri) orelse {
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try body_alloc.writer.writeAll("[]");
        try self.sendResponse(stdout_file, rid, &body_alloc);
        return;
    };

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (features_mod.getFormatting(self.arena, doc.text)) |new_text| {
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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = @intCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = @intCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);
    const new_name = lsp_protocol.getStringField(params, "newName") orelse return;

    const doc = self.documents.get(uri) orelse return;
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.getRenameLinks(self.arena, t, .{ .line = line, .character = character }, doc.text, new_name)) |rename_result| {
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
    const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
    const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
    const pos_val = lsp_protocol.getObjectField(params, "position") orelse return;
    const line: u32 = @intCast(lsp_protocol.getIntField(pos_val, "line") orelse 0);
    const character: u32 = @intCast(lsp_protocol.getIntField(pos_val, "character") orelse 0);

    const doc = self.documents.get(uri) orelse return;
    const result = self.compile_results.get(uri);
    const typed = if (result) |r| r.typed_ast else null;

    var body_alloc = std.Io.Writer.Allocating.init(self.arena);
    if (typed) |t| {
        if (features_mod.prepareRename(t, .{ .line = line, .character = character }, doc.text)) |symbol_name| {
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
