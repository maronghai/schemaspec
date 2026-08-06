const std = @import("std");
const lsp_protocol = @import("protocol.zig");
const compile_svc = @import("compile_service.zig");
const doc_mod = @import("documents.zig");
const features_mod = @import("features.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── LSP Server ────────────────────────────────────────────────
// JSON-RPC 2.0 server over stdio for the Language Server Protocol.
// Handles textDocument/didOpen, didChange, didClose, didSave notifications
// and publishes diagnostics after each compilation.

pub const Server = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    documents: doc_mod.DocumentManager,
    compile_results: std.StringHashMap(compile_svc.CompileResult),
    initialized: bool,
    dialect: Dialect,

    pub fn init(arena: std.mem.Allocator, io: std.Io) Server {
        return .{
            .arena = arena,
            .io = io,
            .documents = doc_mod.DocumentManager.init(arena),
            .compile_results = std.StringHashMap(compile_svc.CompileResult).init(arena),
            .initialized = false,
            .dialect = .mysql,
        };
    }

    pub fn deinit(self: *Server) void {
        var iter = self.compile_results.iterator();
        while (iter.next()) |entry| {
            self.arena.free(entry.value_ptr.*.diagnostics);
        }
        self.compile_results.deinit();
        self.documents.deinit();
    }

    /// Run the LSP server main loop.
    /// Reads JSON-RPC messages from stdin, dispatches to handlers,
    /// and writes responses to stdout.
    pub fn run(self: *Server) !void {
        const stdin_file = std.Io.File.stdin();
        const stdout_file = std.Io.File.stdout();
        var buf: [4096]u8 = undefined;
        var r = stdin_file.readerStreaming(self.io, &buf);

        while (true) {
            const msg = try readMessage(self.arena, &r.interface);
            defer {
                if (msg.method) |m| self.arena.free(m);
                if (msg.params) |p| {
                    _ = p;
                }
                if (msg.error_obj) |e| {
                    self.arena.free(e.message);
                }
            }

            // Handle responses (id present, method absent)
            if (msg.is_response) continue;

            const method = msg.method orelse continue;
            const id = msg.id;

            if (std.mem.eql(u8, method, "initialize")) {
                try self.handleInitialize(stdout_file, id, msg.params);
            } else if (std.mem.eql(u8, method, "initialized")) {
                self.initialized = true;
            } else if (std.mem.eql(u8, method, "shutdown")) {
                try self.handleShutdown(stdout_file, id);
                return;
            } else if (std.mem.eql(u8, method, "exit")) {
                return;
            } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
                if (msg.params) |params| {
                    try self.handleDidOpen(params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
                if (msg.params) |params| {
                    try self.handleDidChange(params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
                if (msg.params) |params| {
                    try self.handleDidClose(params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
                if (msg.params) |params| {
                    try self.handleDidSave(params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
                if (msg.params) |params| {
                    try self.handleDocumentSymbol(stdout_file, id, params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/completion")) {
                if (msg.params) |params| {
                    try self.handleCompletion(stdout_file, id, params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/hover")) {
                if (msg.params) |params| {
                    try self.handleHover(stdout_file, id, params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/definition")) {
                if (msg.params) |params| {
                    try self.handleDefinition(stdout_file, id, params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/codeAction")) {
                if (msg.params) |params| {
                    try self.handleCodeAction(stdout_file, id, params);
                }
            } else if (std.mem.eql(u8, method, "textDocument/formatting")) {
                if (msg.params) |params| {
                    try self.handleFormatting(stdout_file, id, params);
                }
            } else if (id != null) {
                // Unknown method with id → respond with method_not_found
                var w = stdout_file.writerStreaming(self.io, &buf);
                try lsp_protocol.writeErrorResponse(&w.interface, id, lsp_protocol.ErrorCode.method_not_found, "Method not found");
            }
        }
    }

    // ─── Handlers ──────────────────────────────────────────────

    fn handleInitialize(self: *Server, stdout_file: anytype, id: ?i64, params: ?std.json.Value) !void {
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
        });
        try self.sendResponse(stdout_file, rid, &body_alloc);
    }

    fn handleShutdown(self: *Server, stdout_file: anytype, id: ?i64) !void {
        const rid = id orelse return;
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try body_alloc.writer.writeAll("null");
        try self.sendResponse(stdout_file, rid, &body_alloc);
    }

    fn handleDidOpen(self: *Server, params: std.json.Value) !void {
        const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
        const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;
        const version: u32 = @intCast(lsp_protocol.getIntField(text_doc, "version") orelse 1);
        const text = lsp_protocol.getStringField(text_doc, "text") orelse return;
        const language_id = lsp_protocol.getStringField(text_doc, "languageId") orelse "rune";

        try self.documents.open(uri, version, text, language_id);
        try self.compileAndPublishDiagnostics(uri);
    }

    fn handleDidChange(self: *Server, params: std.json.Value) !void {
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

    fn handleDidClose(self: *Server, params: std.json.Value) !void {
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

    fn handleDidSave(self: *Server, params: std.json.Value) !void {
        const text_doc = lsp_protocol.getObjectField(params, "textDocument") orelse return;
        const uri = lsp_protocol.getStringField(text_doc, "uri") orelse return;

        // Recompile on save
        try self.compileAndPublishDiagnostics(uri);
    }

    // ─── Feature Handlers ────────────────────────────────────────

    fn handleDocumentSymbol(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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

    fn handleCompletion(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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

    fn handleHover(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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

    fn handleDefinition(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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

    fn handleCodeAction(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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
        var diagnostics = [_]lsp_protocol.Diagnostic{};
        if (lsp_protocol.getObjectField(params, "context")) |ctx| {
            if (lsp_protocol.getObjectField(ctx, "diagnostics")) |diags_val| {
                if (diags_val == .array) {
                    for (diags_val.array.items, 0..) |d, i| {
                        if (i >= diagnostics.len) break;
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
                        diagnostics[i] = .{
                            .range = range,
                            .severity = switch (sev_val) {
                                1 => .error_sev,
                                2 => .warning,
                                3 => .information,
                                else => .hint,
                            },
                            .message = msg,
                        };
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
            const actions = features_mod.getCodeActions(self.arena, t, &diagnostics, range);
            for (actions, 0..) |action, i| {
                if (i > 0) try body_alloc.writer.writeByte(',');
                try lsp_protocol.writeCodeAction(&body_alloc.writer, action);
            }
        }
        try body_alloc.writer.writeByte(']');

        try self.sendResponse(stdout_file, rid, &body_alloc);
    }

    fn handleFormatting(self: *Server, stdout_file: anytype, id: ?i64, params: std.json.Value) !void {
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

    fn sendResponse(self: *Server, stdout_file: anytype, rid: i64, body_alloc: *std.Io.Writer.Allocating) !void {
        const inner = try body_alloc.toOwnedSlice();
        defer self.arena.free(inner);

        // Wrap in JSON-RPC response
        var response_alloc = std.Io.Writer.Allocating.init(self.arena);
        try response_alloc.writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":", .{rid});
        try response_alloc.writer.writeAll(inner);
        try response_alloc.writer.writeByte('}');
        const body = try response_alloc.toOwnedSlice();
        defer self.arena.free(body);

        var w_buf: [8192]u8 = undefined;
        var w = stdout_file.writerStreaming(self.io, &w_buf);
        try w.interface.print("Content-Length: {d}\r\n\r\n", .{body.len});
        try w.interface.writeAll(body);
    }

    // ─── Compilation & Diagnostics ─────────────────────────────

    fn compileAndPublishDiagnostics(self: *Server, uri: []const u8) !void {
        const doc = self.documents.get(uri) orelse return;
        const path = try self.documents.uriToPath(uri);
        defer self.arena.free(path);

        const result = try compile_svc.compile(self.arena, doc.text, path, self.dialect);

        // Free old diagnostics if present
        if (self.compile_results.getEntry(uri)) |entry| {
            self.arena.free(entry.value_ptr.*.diagnostics);
            entry.value_ptr.* = result;
        } else {
            const owned_uri = try self.arena.dupe(u8, uri);
            try self.compile_results.put(owned_uri, result);
        }

        try self.publishDiagnostics(uri, result.diagnostics);
    }

    fn publishDiagnostics(self: *Server, uri: []const u8, diagnostics: []const lsp_protocol.Diagnostic) !void {
        const stdout_file = std.Io.File.stdout();
        var buf2: [8192]u8 = undefined;
        var w = stdout_file.writerStreaming(self.io, &buf2);

        // Write Content-Length header
        var body_alloc = std.Io.Writer.Allocating.init(self.arena);
        try lsp_protocol.writePublishDiagnostics(&body_alloc.writer, .{
            .uri = uri,
            .diagnostics = diagnostics,
        });
        const body = try body_alloc.toOwnedSlice();
        defer self.arena.free(body);

        try w.interface.print("Content-Length: {d}\r\n\r\n", .{body.len});
        try w.interface.writeAll(body);
    }
};

// ─── Message Reading ───────────────────────────────────────────

/// Read a single LSP message from the streaming reader.
/// Handles Content-Length framing.
fn readMessage(alloc: std.mem.Allocator, reader: *std.Io.Reader) !lsp_protocol.ParsedMessage {
    // Read header
    const header = try readHeader(alloc, reader);
    defer alloc.free(header);

    // Parse Content-Length from header
    const content_length = parseContentLength(header) orelse return error.MissingContentLength;

    // Read body
    var body_list = try std.ArrayList(u8).initCapacity(alloc, content_length);
    try reader.appendExact(alloc, &body_list, content_length);
    const body = try body_list.toOwnedSlice(alloc);
    defer alloc.free(body);

    return lsp_protocol.parseMessage(alloc, body);
}

/// Read the LSP message header (until \r\n\r\n).
fn readHeader(alloc: std.mem.Allocator, reader: *std.Io.Reader) ![]const u8 {
    var header_buf = try std.ArrayList(u8).initCapacity(alloc, 256);
    var found_delimiter = false;

    while (!found_delimiter) {
        // Peek at available data
        const available = reader.peek(1) catch {
            // No data available yet, try reading one byte
            var temp_buf: [1]u8 = undefined;
            var slices = [_][]u8{&temp_buf};
            const n = reader.readVec(&slices) catch return error.ReadError;
            if (n == 0) return error.UnexpectedEof;
            try header_buf.append(alloc, temp_buf[0]);
            continue;
        };

        // Scan for \r\n\r\n in available data
        for (available, 0..) |byte, i| {
            try header_buf.append(alloc, byte);
            if (byte == '\n' and header_buf.items.len >= 4) {
                const len = header_buf.items.len;
                if (header_buf.items[len - 4] == '\r' and
                    header_buf.items[len - 3] == '\n' and
                    header_buf.items[len - 2] == '\r' and
                    header_buf.items[len - 1] == '\n')
                {
                    found_delimiter = true;
                    // Consume the bytes we peeked + any we read
                    reader.toss(i + 1);
                    break;
                }
            }
        }

        if (!found_delimiter and available.len == 0) {
            // No more data available
            return error.UnexpectedEof;
        }
    }

    return try header_buf.toOwnedSlice(alloc);
}

/// Parse Content-Length from an LSP header string.
fn parseContentLength(header: []const u8) ?usize {
    var lines = std.mem.splitScalar(u8, header, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r ");
        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
            const value = std.mem.trim(u8, trimmed["Content-Length:".len..], " ");
            return std.fmt.parseInt(usize, value, 10) catch null;
        }
    }
    return null;
}

// ─── Tests ─────────────────────────────────────────────────────

test "parseContentLength" {
    try std.testing.expectEqual(@as(?usize, 123), parseContentLength("Content-Length: 123\r\n\r\n"));
    try std.testing.expectEqual(@as(?usize, 0), parseContentLength("Content-Length: 0\r\n\r\n"));
    try std.testing.expect(parseContentLength("Other: 123\r\n\r\n") == null);
    try std.testing.expect(parseContentLength("") == null);
}

test "Server init" {
    var server = Server.init(std.testing.allocator, undefined);
    defer server.deinit();
    try std.testing.expect(!server.initialized);
    try std.testing.expectEqual(@as(usize, 0), server.documents.count());
}
