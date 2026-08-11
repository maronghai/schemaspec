const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const dialect_enum = @import("../dialect/enum.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const columns_mod = @import("columns.zig");
const indexes_mod = @import("indexes.zig");
const interleave = @import("interleave.zig");
const version = @import("../version.zig");
const Writer = std.Io.Writer;

pub const Dialect = dialect_enum.Dialect;

/// Pool of reusable `Writer.Allocating` buffers for batch codegen.
/// Avoids repeated allocation/deallocation when generating SQL for multiple schemas.
/// Thread-safe: acquire/release are protected by a mutex for parallel codegen use.
pub const BufferPool = struct {
    alloc: std.mem.Allocator,
    buffers: std.ArrayList(std.Io.Writer.Allocating),
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(alloc: std.mem.Allocator) BufferPool {
        return .{
            .alloc = alloc,
            .buffers = .empty,
        };
    }

    /// Initialize a pool with pre-allocated capacity for the expected number of buffers.
    pub fn initWithCapacity(alloc: std.mem.Allocator, capacity: usize) BufferPool {
        var pool = BufferPool{
            .alloc = alloc,
            .buffers = .empty,
        };
        pool.buffers.ensureTotalCapacity(alloc, capacity) catch {};
        return pool;
    }

    pub fn deinit(self: *BufferPool) void {
        for (self.buffers.items) |*buf| {
            buf.deinit();
        }
        self.buffers.deinit(self.alloc);
    }

    /// Acquire a buffer from the pool (or create a new one).
    /// Thread-safe: protected by mutex for parallel codegen use.
    pub fn acquire(self: *BufferPool) !std.Io.Writer.Allocating {
        while (!self.mutex.tryLock()) std.Thread.yield() catch {};
        defer self.mutex.unlock();
        if (self.buffers.items.len > 0) {
            return self.buffers.pop() orelse return std.Io.Writer.Allocating.init(self.alloc);
        }
        return std.Io.Writer.Allocating.init(self.alloc);
    }

    /// Release a buffer back to the pool for reuse.
    /// Thread-safe: protected by mutex for parallel codegen use.
    pub fn release(self: *BufferPool, buf: std.Io.Writer.Allocating) !void {
        while (!self.mutex.tryLock()) std.Thread.yield() catch {};
        defer self.mutex.unlock();
        var mutable = buf;
        mutable.clearRetainingCapacity();
        try self.buffers.append(self.alloc, mutable);
    }
};

pub const Codegen = struct {
    alloc: std.mem.Allocator,
    dialect: Dialect,
    backend: *const dialect_mod.DialectBackend,

    pub fn init(alloc: std.mem.Allocator, dialect: Dialect) Codegen {
        return .{
            .alloc = alloc,
            .dialect = dialect,
            .backend = dialect_mod.getBackend(dialect),
        };
    }

    // ─── TypedAst API (sole codegen path) ───────────────────────

    /// Generate SQL DDL from a TypedAst. Returns the complete SQL string.
    /// Uses a fresh buffer each call; for batch use, prefer `generateFromTypedAstPooled`.
    pub fn generateFromTypedAst(self: *Codegen, typed: typed_ast_mod.TypedAst) ![]const u8 {
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        try self.fillWriter(&aw.writer, typed);
        return try aw.toOwnedSlice();
    }

    /// Generate SQL DDL using a pooled buffer. Caller must release the buffer back
    /// to the pool after consuming the returned slice.
    pub fn generateFromTypedAstPooled(self: *Codegen, pool: *BufferPool, typed: typed_ast_mod.TypedAst) !struct { sql: []const u8, buf: std.Io.Writer.Allocating } {
        var aw = try pool.acquire();
        try self.fillWriter(&aw.writer, typed);
        const sql = try aw.toOwnedSlice();
        return .{ .sql = sql, .buf = aw };
    }

    fn fillWriter(self: *Codegen, w: *Writer, typed: typed_ast_mod.TypedAst) !void {
        try dialect_enum.writeHeader(w, self.dialect);

        // Emit schema version as SQL comment if present
        if (typed.schema_version) |ver| {
            try w.print("-- Schema version: {s}\n\n", .{ver});
        }

        if (typed.schema_name) |name| {
            try self.backend.emitCreateDatabase(w, name, typed.schema_charset);
        }

        // Interleave tables, views, and sql_comments by line number
        var lm = interleave.LineMerger.init(typed.tables, typed.views, typed.sql_comments);
        while (lm.next()) |kind| {
            switch (kind) {
                .comment => {
                    try w.writeAll(typed.sql_comments[lm.ci - 1].text);
                    try w.writeAll("\n");
                    lm.advanceComment(typed.sql_comments);
                },
                .view => {
                    try self.generateTypedView(w, typed.views[lm.vi - 1]);
                    lm.advanceView(typed.views);
                    if (lm.ti < typed.tables.len or lm.vi < typed.views.len or lm.ci < typed.sql_comments.len) {
                        try w.writeAll("\n");
                    }
                },
                .table => {
                    try self.generateTypedTable(w, typed.tables[lm.ti - 1]);
                    lm.advanceTable(typed.tables);
                    if (lm.ti < typed.tables.len or lm.vi < typed.views.len or lm.ci < typed.sql_comments.len) {
                        try w.writeAll("\n");
                    }
                },
            }
        }
    }

    /// Emit a full CREATE TABLE statement for one table to the given writer.
    /// Used by both forward codegen (generateFromTypedAst) and migration generation.
    pub fn generateTypedTable(self: *Codegen, w: *Writer, table: typed_ast_mod.TypedTable) !void {
        try w.writeAll("CREATE TABLE ");
        try self.backend.quoteIdent(w, table.name);
        try w.writeAll(" (\n");

        var needs_comma = false;

        try emitColumnDefs(self, w, table, &needs_comma);
        try indexes_mod.emitInlineIndexes(self.backend, w, table, &needs_comma);
        for (table.indexes) |idx| {
            try self.backend.emitIndex(w, idx, &needs_comma);
        }
        try emitConstraints(self, w, table, &needs_comma);

        if (needs_comma) try w.writeAll("\n");

        try self.backend.emitTableFooter(w, table.engine, null, table.comment);
        try emitTableMetadata(self, w, table);
        try indexes_mod.emitStandaloneIndexes(self.backend, w, table);
        try indexes_mod.emitInlineColumnStandaloneIndexes(self.backend, w, table);
    }

    fn emitColumnDefs(self: *Codegen, w: *Writer, table: typed_ast_mod.TypedTable, needs_comma: *bool) !void {
        for (table.columns) |col| {
            if (needs_comma.*) try w.writeAll(",\n");
            needs_comma.* = true;
            try w.writeAll("  ");
            try columns_mod.emitColumnDef(self.backend, w, col);
        }
    }

    fn emitConstraints(self: *Codegen, w: *Writer, table: typed_ast_mod.TypedTable, needs_comma: *bool) !void {
        for (table.fks) |fk| {
            if (needs_comma.*) try w.writeAll(",\n");
            needs_comma.* = true;
            try w.writeAll("  ");
            try self.backend.emitForeignKey(w, fk);
        }
    }

    fn emitTableMetadata(self: *Codegen, w: *Writer, table: typed_ast_mod.TypedTable) !void {
        if (table.comment) |c| {
            try self.backend.emitTableComment(w, table.name, c);
        }
        for (table.columns) |col| {
            if (col.comment) |c| {
                try self.backend.emitColumnComment(w, table.name, col.name, c);
            }
        }
        for (table.columns) |col| {
            if (col.ss_symbol) |sym| {
                try self.backend.emitTypeMetadata(w, col.name, sym);
            }
        }
    }

    /// Emit a CREATE VIEW statement.
    pub fn generateTypedView(self: *Codegen, w: *Writer, view: typed_ast_mod.TypedView) !void {
        // Build the full query, combining UNION/INTERSECT/EXCEPT parts
        if (view.union_op) |op| {
            const second = view.second_query orelse "";
            const op_str: []const u8 = switch (op) {
                .union_all => " UNION ALL ",
                .union_distinct => " UNION ",
                .intersect => " INTERSECT ",
                .except => " EXCEPT ",
            };
            var buf = std.Io.Writer.Allocating.init(self.alloc);
            defer buf.deinit();
            try buf.writer.writeAll(view.query);
            try buf.writer.writeAll(op_str);
            try buf.writer.writeAll(second);
            const full_query = try buf.toOwnedSlice();
            try self.backend.emitCreateView(w, view.name, full_query);
        } else {
            try self.backend.emitCreateView(w, view.name, view.query);
        }
        if (view.comment) |c| {
            try self.backend.emitTableComment(w, view.name, c);
        }
    }

    /// Render a single column definition (shared by CREATE TABLE and ALTER TABLE paths).
    /// When skip_name is true, the column name is not emitted (used by PG ALTER COLUMN TYPE).
    pub fn emitColumnDef(self: *Codegen, w: *Writer, col: typed_ast_mod.TypedColumn) !void {
        return columns_mod.emitColumnDef(self.backend, w, col);
    }

    pub fn emitColumnDefEx(self: *Codegen, w: *Writer, col: typed_ast_mod.TypedColumn, skip_name: bool) !void {
        return columns_mod.emitColumnDefEx(self.backend, w, col, skip_name);
    }
};

// ─── Diagnostic ──────────────────────────────────────────────

pub fn diagnosticTrace(typed: typed_ast_mod.TypedAst) void {
    std.debug.print("=== [Stage 4: Codegen] ===\n\n", .{});

    var column_count: usize = 0;
    var fk_count: usize = 0;
    var index_count: usize = 0;

    for (typed.tables) |table| {
        column_count += table.columns.len;
        fk_count += table.fks.len;
        index_count += table.indexes.len;
    }

    std.debug.print("Tables:    {d}\n", .{typed.tables.len});
    std.debug.print("Columns:   {d}\n", .{column_count});
    std.debug.print("Views:     {d}\n", .{typed.views.len});
    std.debug.print("FKs:       {d}\n", .{fk_count});
    std.debug.print("Indexes:   {d}\n\n", .{index_count});
}

// ─── Shared helpers (dialect-independent) ──────────────────────

/// Render a CHECK constraint expression from a field name and CheckConstraint.
/// Handles range, in_list, and comparison expressions.
pub const emitCheckExpr = columns_mod.emitCheckExpr;
