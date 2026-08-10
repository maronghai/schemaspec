const std = @import("std");
const lsp_protocol = @import("protocol.zig");
const compile_svc = @import("compile_service.zig");
const doc_mod = @import("documents.zig");
const handlers = @import("handlers.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── LSP Server ────────────────────────────────────────────────
// JSON-RPC 2.0 server over stdio for the Language Server Protocol.
// Handles textDocument/didOpen, didChange, didClose, didSave notifications
// and publishes diagnostics after each compilation.
//
// Request handlers are extracted to handlers.zig for maintainability.

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

    /// Handler function signature for table-driven dispatch.
    /// Takes server, optional stdout_file, optional id, and optional params.
    const HandlerFn = *const fn (self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) anyerror!void;

    /// Dispatch table entry: method name → handler function.
    const DispatchEntry = struct {
        method: []const u8,
        handler: HandlerFn,
    };

    /// Table-driven method dispatch — eliminates the 22-branch if-else chain.
    /// Adding a new LSP method = one entry here + one handler in handlers.zig.
    const DISPATCH_TABLE = [_]DispatchEntry{
        .{ .method = "initialize", .handler = handleInitializeDispatch },
        .{ .method = "shutdown", .handler = handleShutdownDispatch },
        .{ .method = "textDocument/didOpen", .handler = handleDidOpenDispatch },
        .{ .method = "textDocument/didChange", .handler = handleDidChangeDispatch },
        .{ .method = "textDocument/didClose", .handler = handleDidCloseDispatch },
        .{ .method = "textDocument/didSave", .handler = handleDidSaveDispatch },
        .{ .method = "textDocument/documentSymbol", .handler = handleDocumentSymbolDispatch },
        .{ .method = "textDocument/completion", .handler = handleCompletionDispatch },
        .{ .method = "textDocument/hover", .handler = handleHoverDispatch },
        .{ .method = "textDocument/definition", .handler = handleDefinitionDispatch },
        .{ .method = "textDocument/codeAction", .handler = handleCodeActionDispatch },
        .{ .method = "textDocument/formatting", .handler = handleFormattingDispatch },
        .{ .method = "textDocument/rename", .handler = handleRenameDispatch },
        .{ .method = "textDocument/prepareRename", .handler = handlePrepareRenameDispatch },
        .{ .method = "textDocument/references", .handler = handleReferencesDispatch },
        .{ .method = "textDocument/documentHighlight", .handler = handleDocumentHighlightDispatch },
        .{ .method = "textDocument/foldingRange", .handler = handleFoldingRangeDispatch },
        .{ .method = "textDocument/typeDefinition", .handler = handleTypeDefinitionDispatch },
    };

    /// Run the LSP server main loop.
    /// Reads JSON-RPC messages from stdin, dispatches to handlers,
    /// and writes responses to stdout.
    pub fn run(self: *Server) !void {
        const stdin_file = std.Io.File.stdin();
        const stdout_file = std.Io.File.stdout();
        var buf: [16384]u8 = undefined;
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

            // Handle non-request methods outside the dispatch table
            if (std.mem.eql(u8, method, "initialized")) {
                self.initialized = true;
                continue;
            } else if (std.mem.eql(u8, method, "exit")) {
                return;
            }

            // Table-driven dispatch for request handlers
            var handled = false;
            for (DISPATCH_TABLE) |entry| {
                if (std.mem.eql(u8, method, entry.method)) {
                    try entry.handler(self, stdout_file, id, msg.params);
                    // Shutdown handler signals the server to stop
                    if (std.mem.eql(u8, method, "shutdown")) return;
                    handled = true;
                    break;
                }
            }

            if (!handled and id != null) {
                // Unknown method with id → respond with method_not_found
                var w = stdout_file.writerStreaming(self.io, &buf);
                try lsp_protocol.writeErrorResponse(&w.interface, id, lsp_protocol.ErrorCode.method_not_found, "Method not found");
            }
        }
    }

    // ─── Dispatch Adapters ──────────────────────────────────────
    // Adapters normalize handler signatures to match HandlerFn.
    // Each wraps the corresponding handler from handlers.zig.

    fn handleInitializeDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        try handlers.handleInitialize(self, stdout.?, id, params);
    }

    fn handleShutdownDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, _: ?std.json.Value) !void {
        try handlers.handleShutdown(self, stdout.?, id);
    }

    fn handleDidOpenDispatch(self: *Server, _: ?std.Io.File, _: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDidOpen(self, p);
    }

    fn handleDidChangeDispatch(self: *Server, _: ?std.Io.File, _: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDidChange(self, p);
    }

    fn handleDidCloseDispatch(self: *Server, _: ?std.Io.File, _: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDidClose(self, p);
    }

    fn handleDidSaveDispatch(self: *Server, _: ?std.Io.File, _: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDidSave(self, p);
    }

    fn handleDocumentSymbolDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDocumentSymbol(self, stdout.?, id, p);
    }

    fn handleCompletionDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleCompletion(self, stdout.?, id, p);
    }

    fn handleHoverDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleHover(self, stdout.?, id, p);
    }

    fn handleDefinitionDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDefinition(self, stdout.?, id, p);
    }

    fn handleCodeActionDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleCodeAction(self, stdout.?, id, p);
    }

    fn handleFormattingDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleFormatting(self, stdout.?, id, p);
    }

    fn handleRenameDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleRename(self, stdout.?, id, p);
    }

    fn handlePrepareRenameDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handlePrepareRename(self, stdout.?, id, p);
    }

    fn handleReferencesDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleReferences(self, stdout.?, id, p);
    }

    fn handleDocumentHighlightDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleDocumentHighlight(self, stdout.?, id, p);
    }

    fn handleFoldingRangeDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleFoldingRange(self, stdout.?, id, p);
    }

    fn handleTypeDefinitionDispatch(self: *Server, stdout: ?std.Io.File, id: ?i64, params: ?std.json.Value) !void {
        if (params) |p| try handlers.handleTypeDefinition(self, stdout.?, id, p);
    }

    /// Send a JSON-RPC response to stdout.
    pub fn sendResponse(self: *Server, stdout_file: anytype, rid: i64, body_alloc: *std.Io.Writer.Allocating) !void {
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

    pub fn compileAndPublishDiagnostics(self: *Server, uri: []const u8) !void {
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

    pub fn publishDiagnostics(self: *Server, uri: []const u8, diagnostics: []const lsp_protocol.Diagnostic) !void {
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
