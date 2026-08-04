const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const version = @import("../version.zig");

// ─── Interleaving Iterator ─────────────────────────────────────

pub const InterleaveKind = enum { table, view, comment };

pub const InterleaveIterator = struct {
    tables: []const StreamingResult.TableOutput,
    views: []const StreamingResult.ViewOutput,
    comments: []const StreamingResult.CommentOutput,
    ti: usize = 0,
    vi: usize = 0,
    ci: usize = 0,

    pub fn next(self: *InterleaveIterator) ?InterleaveKind {
        const table_line = if (self.ti < self.tables.len) self.tables[self.ti].line_no else std.math.maxInt(usize);
        const view_line = if (self.vi < self.views.len) self.views[self.vi].line_no else std.math.maxInt(usize);
        const comment_line = if (self.ci < self.comments.len) self.comments[self.ci].line_no else std.math.maxInt(usize);

        const min_line = @min(table_line, view_line, comment_line);
        if (min_line == std.math.maxInt(usize)) return null;

        if (comment_line == min_line) {
            self.ci += 1;
            return .comment;
        } else if (view_line == min_line) {
            self.vi += 1;
            return .view;
        } else {
            self.ti += 1;
            return .table;
        }
    }

    pub fn currentTable(self: InterleaveIterator) StreamingResult.TableOutput {
        return self.tables[self.ti - 1];
    }

    pub fn currentView(self: InterleaveIterator) StreamingResult.ViewOutput {
        return self.views[self.vi - 1];
    }

    pub fn currentComment(self: InterleaveIterator) StreamingResult.CommentOutput {
        return self.comments[self.ci - 1];
    }
};

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
    cg: codegen.Codegen,

    pub fn init(alloc: std.mem.Allocator, dialect: codegen.Dialect) StreamingCodegen {
        return .{
            .alloc = alloc,
            .dialect = dialect,
            .cg = codegen.Codegen.init(alloc, dialect),
        };
    }

    /// Generate SQL for a single table and return it.
    /// This allows incremental processing of large schemas.
    pub fn generateTable(self: StreamingCodegen, table: typed_ast_mod.TypedTable) ![]const u8 {
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        const w = &aw.writer;

        try self.cg.generateTypedTable(w, table);

        try w.flush();
        return try aw.toOwnedSlice();
    }

    /// Generate SQL for a single view and return it.
    pub fn generateView(self: StreamingCodegen, view: typed_ast_mod.TypedView) ![]const u8 {
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        const w = &aw.writer;

        try self.cg.generateTypedView(w, view);

        try w.flush();
        return try aw.toOwnedSlice();
    }

    /// Generate complete SQL with streaming output.
    /// Each table, view, and comment is returned separately, enabling incremental processing.
    pub fn generateStreaming(self: StreamingCodegen, typed: typed_ast_mod.TypedAst) !StreamingResult {
        var total_size: usize = 0;
        var tables = try std.ArrayList(StreamingResult.TableOutput).initCapacity(self.alloc, typed.tables.len);
        var views = try std.ArrayList(StreamingResult.ViewOutput).initCapacity(self.alloc, typed.views.len);
        var comments = try std.ArrayList(StreamingResult.CommentOutput).initCapacity(self.alloc, typed.sql_comments.len);

        // Emit header
        const header = try dialect_enum.allocHeader(self.alloc, self.dialect);
        total_size += header.len;

        // Interleave tables, views, and sql_comments by line number
        var ti: usize = 0;
        var vi: usize = 0;
        var ci: usize = 0;

        while (ti < typed.tables.len or vi < typed.views.len or ci < typed.sql_comments.len) {
            const table_line = if (ti < typed.tables.len) typed.tables[ti].line_no else std.math.maxInt(usize);
            const view_line = if (vi < typed.views.len) typed.views[vi].line_no else std.math.maxInt(usize);
            const comment_line = if (ci < typed.sql_comments.len) typed.sql_comments[ci].line_no else std.math.maxInt(usize);

            const min_line = @min(table_line, view_line, comment_line);

            if (comment_line == min_line) {
                try comments.append(self.alloc, .{
                    .text = typed.sql_comments[ci].text,
                    .line_no = typed.sql_comments[ci].line_no,
                });
                total_size += typed.sql_comments[ci].text.len + 1; // +1 for newline
                ci += 1;
            } else if (view_line == min_line) {
                const sql = try self.generateView(typed.views[vi]);
                try views.append(self.alloc, .{
                    .name = typed.views[vi].name,
                    .sql = sql,
                    .line_no = typed.views[vi].line_no,
                });
                total_size += sql.len;
                vi += 1;
            } else if (table_line == min_line) {
                const sql = try self.generateTable(typed.tables[ti]);
                try tables.append(self.alloc, .{
                    .name = typed.tables[ti].name,
                    .sql = sql,
                    .line_no = typed.tables[ti].line_no,
                });
                total_size += sql.len;
                ti += 1;
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

    var iter = InterleaveIterator{
        .tables = result.tables,
        .views = result.views,
        .comments = result.comments,
    };

    const total = result.tables.len + result.views.len + result.comments.len;
    var emitted: usize = 0;

    while (iter.next()) |kind| {
        switch (kind) {
            .comment => {
                try w.writeAll(iter.currentComment().text);
                try w.writeAll("\n");
            },
            .view => try w.writeAll(iter.currentView().sql),
            .table => try w.writeAll(iter.currentTable().sql),
        }
        emitted += 1;
        if (emitted < total) try w.writeAll("\n");
    }

    try w.flush();
    return try aw.toOwnedSlice();
}
