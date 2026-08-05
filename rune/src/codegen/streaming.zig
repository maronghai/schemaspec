const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const interleave = @import("interleave.zig");
const version = @import("../version.zig");

// ─── Streaming Compilation ─────────────────────────────────────

/// Result from streaming compilation — holds per-item SQL output.
pub const StreamingResult = struct {
    /// SQL for each table, in order of generation.
    tables: []TableOutput,
    /// SQL for each view, in order of generation.
    views: []ViewOutput,
    /// SQL comments, in order of appearance.
    comments: []CommentOutput,
    /// Total SQL size in bytes.
    total_size: usize,
    /// Number of tables processed.
    table_count: usize,

    pub const TableOutput = struct {
        name: []const u8,
        sql: []const u8,
        line_no: usize,
    };

    pub const ViewOutput = struct {
        name: []const u8,
        sql: []const u8,
        line_no: usize,
    };

    pub const CommentOutput = struct {
        text: []const u8,
        line_no: usize,
    };
};

/// Streaming codegen that emits each table's SQL immediately.
/// Useful for large schemas where you want to start processing output
/// before the entire schema is compiled.
pub const StreamingCodegen = struct {
    alloc: std.mem.Allocator,
    dialect: codegen.Dialect,
    cg: *codegen.Codegen,
    pool: ?*codegen.BufferPool = null,

    pub fn init(alloc: std.mem.Allocator, dialect: codegen.Dialect) !StreamingCodegen {
        const cg = try alloc.create(codegen.Codegen);
        cg.* = codegen.Codegen.init(alloc, dialect);
        return .{
            .alloc = alloc,
            .dialect = dialect,
            .cg = cg,
        };
    }

    pub fn initWithPool(alloc: std.mem.Allocator, dialect: codegen.Dialect, pool: *codegen.BufferPool) !StreamingCodegen {
        const cg = try alloc.create(codegen.Codegen);
        cg.* = codegen.Codegen.init(alloc, dialect);
        return .{
            .alloc = alloc,
            .dialect = dialect,
            .cg = cg,
            .pool = pool,
        };
    }

    /// Generate SQL for a single table and return it.
    /// This allows incremental processing of large schemas.
    pub fn generateTable(self: *StreamingCodegen, table: typed_ast_mod.TypedTable) ![]const u8 {
        if (self.pool) |pool| {
            var aw = try pool.acquire();
            try self.cg.generateTypedTable(&aw.writer, table);
            try aw.writer.flush();
            const sql = try aw.toOwnedSlice();
            try pool.release(aw);
            return sql;
        }
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        try self.cg.generateTypedTable(&aw.writer, table);
        try aw.writer.flush();
        return try aw.toOwnedSlice();
    }

    /// Generate SQL for a single view and return it.
    pub fn generateView(self: *StreamingCodegen, view: typed_ast_mod.TypedView) ![]const u8 {
        if (self.pool) |pool| {
            var aw = try pool.acquire();
            try self.cg.generateTypedView(&aw.writer, view);
            try aw.writer.flush();
            const sql = try aw.toOwnedSlice();
            try pool.release(aw);
            return sql;
        }
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        try self.cg.generateTypedView(&aw.writer, view);
        try aw.writer.flush();
        return try aw.toOwnedSlice();
    }

    /// Generate complete SQL with streaming output.
    /// Each table, view, and comment is returned separately, enabling incremental processing.
    pub fn generateStreaming(self: *StreamingCodegen, typed: typed_ast_mod.TypedAst) !StreamingResult {
        var total_size: usize = 0;
        var tables = try std.ArrayList(StreamingResult.TableOutput).initCapacity(self.alloc, typed.tables.len);
        var views = try std.ArrayList(StreamingResult.ViewOutput).initCapacity(self.alloc, typed.views.len);
        var comments = try std.ArrayList(StreamingResult.CommentOutput).initCapacity(self.alloc, typed.sql_comments.len);

        // Emit header
        const header = try dialect_enum.allocHeader(self.alloc, self.dialect);
        total_size += header.len;

        // Interleave tables, views, and sql_comments by line number
        var lm = interleave.LineMerger.init(typed.tables, typed.views, typed.sql_comments);

        while (lm.next()) |kind| {
            switch (kind) {
                .comment => {
                    try comments.append(self.alloc, .{
                        .text = typed.sql_comments[lm.ci - 1].text,
                        .line_no = typed.sql_comments[lm.ci - 1].line_no,
                    });
                    total_size += typed.sql_comments[lm.ci - 1].text.len + 1; // +1 for newline
                    lm.advanceComment(typed.sql_comments);
                },
                .view => {
                    const sql = try self.generateView(typed.views[lm.vi - 1]);
                    try views.append(self.alloc, .{
                        .name = typed.views[lm.vi - 1].name,
                        .sql = sql,
                        .line_no = typed.views[lm.vi - 1].line_no,
                    });
                    total_size += sql.len;
                    lm.advanceView(typed.views);
                },
                .table => {
                    const sql = try self.generateTable(typed.tables[lm.ti - 1]);
                    try tables.append(self.alloc, .{
                        .name = typed.tables[lm.ti - 1].name,
                        .sql = sql,
                        .line_no = typed.tables[lm.ti - 1].line_no,
                    });
                    total_size += sql.len;
                    lm.advanceTable(typed.tables);
                },
            }
        }

        return .{
            .tables = try tables.toOwnedSlice(self.alloc),
            .views = try views.toOwnedSlice(self.alloc),
            .comments = try comments.toOwnedSlice(self.alloc),
            .total_size = total_size,
            .table_count = typed.tables.len,
        };
    }
};

/// Format streaming result as complete SQL.
/// Data is already in line-number order from generateStreaming,
/// so we iterate linearly through the interleaved results.
pub fn formatStreamingResult(alloc: std.mem.Allocator, result: *const StreamingResult, dialect: codegen.Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try dialect_enum.writeHeader(w, dialect);

    var lm = interleave.LineMerger.init(result.tables, result.views, result.comments);
    const total = result.tables.len + result.views.len + result.comments.len;
    var emitted: usize = 0;

    while (lm.next()) |kind| {
        switch (kind) {
            .comment => {
                try w.writeAll(result.comments[lm.ci - 1].text);
                try w.writeAll("\n");
                lm.advanceComment(result.comments);
            },
            .view => {
                try w.writeAll(result.views[lm.vi - 1].sql);
                lm.advanceView(result.views);
            },
            .table => {
                try w.writeAll(result.tables[lm.ti - 1].sql);
                lm.advanceTable(result.tables);
            },
        }
        emitted += 1;
        if (emitted < total) try w.writeAll("\n");
    }

    try w.flush();
    return try aw.toOwnedSlice();
}
