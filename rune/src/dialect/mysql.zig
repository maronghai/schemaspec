const std = @import("std");
const dialect = @import("../dialect/dialect.zig");
const common = @import("common.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const DialectBackend = dialect.DialectBackend;
const CommentResult = dialect.CommentResult;
const IndexDecl = ast_mod.IndexDecl;
const Writer = std.Io.Writer;
const SqlType = sql_type_mod.SqlType;

// ─── MySQL Backend ─────────────────────────────────────────────

fn mysqlEmitForeignKey(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try common.emitForeignKeyShared(w, fk, mysqlQuoteIdent);
}

fn mysqlQuoteIdent(w: *Writer, name: []const u8) anyerror!void {
    try w.print("`{s}`", .{name});
}

fn mysqlEmitIndex(w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    try w.writeAll("  ");
    switch (idx.kind) {
        .regular => try w.writeAll("INDEX"),
        .unique => try w.writeAll("UNIQUE INDEX"),
        .fulltext => try w.writeAll("FULLTEXT INDEX"),
        .primary_key => try w.writeAll("PRIMARY KEY"),
    }
    if (idx.kind == .primary_key) {
        try w.writeAll(" (");
    } else {
        try w.print(" `{s}` (", .{idx.name});
    }
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try w.print("`{s}`", .{f});
    }
    try w.writeAll(")");
}

fn mysqlEmitCreateDatabase(w: *Writer, name: []const u8, charset: ?[]const u8) anyerror!void {
    if (charset) |cs| {
        try w.print("CREATE DATABASE `{s}` CHARACTER SET {s};\n\n", .{ name, cs });
    } else {
        try w.print("CREATE DATABASE `{s}`;\n\n", .{name});
    }
}

fn mysqlEmitUnsigned(w: *Writer) anyerror!void {
    try w.writeAll(" UNSIGNED");
}

fn mysqlEmitTimestampModifier(w: *Writer, with_on_update: bool) anyerror!void {
    try w.writeAll(" DEFAULT CURRENT_TIMESTAMP");
    if (with_on_update) {
        try w.writeAll(" ON UPDATE CURRENT_TIMESTAMP");
    }
}

fn mysqlEmitTableFooter(w: *Writer, engine: ?[]const u8, _: ?[]const u8, comment: ?[]const u8) anyerror!void {
    const eng = engine orelse "InnoDB";
    const cs = "utf8mb4";
    if (comment) |c| {
        const ct = if (c.len >= 1 and c[0] == ':') c[1..] else c;
        const tr = std.mem.trim(u8, ct, " ");
        try w.print(") ENGINE={s} DEFAULT CHARSET={s} COMMENT='{s}';\n", .{ eng, cs, tr });
    } else {
        try w.print(") ENGINE={s} DEFAULT CHARSET={s};\n", .{ eng, cs });
    }
}

fn mysqlEmitTableComment(_: *Writer, _: []const u8, _: []const u8) anyerror!void {
    // MySQL: comment is in table footer (COMMENT='...'), no standalone statement
}

fn mysqlEmitColumnComment(_: *Writer, _: []const u8, _: []const u8, _: []const u8) anyerror!void {
    // MySQL: column comments are inline in emitColumnDef (COMMENT '...'), not standalone
}

fn mysqlEmitAutoIncrement(w: *Writer) anyerror!void {
    try w.writeAll(" AUTO_INCREMENT");
}

fn mysqlEmitPrimaryKey(w: *Writer, _: bool) anyerror!void {
    try w.writeAll(" PRIMARY KEY");
}

fn mysqlEmitInlineIndex(w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    if (is_unique) {
        try w.print("  UNIQUE INDEX `uk_{s}` (`{s}`)", .{ col_name, col_name });
    } else {
        try w.print("  INDEX `idx_{s}` (`{s}`)", .{ col_name, col_name });
    }
}

fn mysqlEmitStandaloneIndex(_: *Writer, _: []const u8, _: IndexDecl) anyerror!void {
    // MySQL: indexes are inline in CREATE TABLE, no standalone CREATE INDEX
}

fn mysqlEmitInlineColumnComment(w: *Writer, comment: []const u8) anyerror!void {
    const ct = if (comment.len >= 1 and comment[0] == ':') comment[1..] else comment;
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print(" COMMENT '{s}'", .{tr});
}

fn mysqlEmitEnumTypeCheck(_: *Writer, _: []const u8, _: []const []const u8) anyerror!void {
    // MySQL: native ENUM type, no CHECK constraint needed
}

fn mysqlNoopInlineColumnIndex(_: *Writer, _: []const u8, _: []const u8) anyerror!void {
    // MySQL handles inline indexes via emitInlineIndex — no standalone needed
}

// ─── MySQL ALTER TABLE migration methods ────────────────────

fn mysqlEmitAlterDropColumn(w: *Writer, col_name: []const u8) anyerror!void {
    try w.writeAll("DROP COLUMN ");
    try w.print("`{s}`", .{col_name});
}

fn mysqlEmitAlterModifyColumn(w: *Writer, _: []const u8) anyerror!void {
    try w.writeAll("MODIFY COLUMN ");
}

fn mysqlEmitAlterRenameColumn(w: *Writer, old_name: []const u8, _: []const u8) anyerror!void {
    try w.writeAll("CHANGE COLUMN ");
    try w.print("`{s}`", .{old_name});
}

fn mysqlEmitAlterAddIndex(w: *Writer, _: []const u8, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .regular => {
            try w.print("ADD INDEX `{s}` (", .{idx.name});
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("`{s}`", .{f});
            }
            try w.writeAll(")");
        },
        .unique => {
            try w.print("ADD UNIQUE INDEX `{s}` (", .{idx.name});
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("`{s}`", .{f});
            }
            try w.writeAll(")");
        },
        .fulltext => {
            try w.print("ADD FULLTEXT INDEX `{s}` (", .{idx.name});
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("`{s}`", .{f});
            }
            try w.writeAll(")");
        },
        .primary_key => {
            try w.writeAll("ADD PRIMARY KEY (");
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("`{s}`", .{f});
            }
            try w.writeAll(")");
        },
    }
}

fn mysqlEmitAlterDropIndex(w: *Writer, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .primary_key => try w.writeAll("DROP PRIMARY KEY"),
        else => try w.print("DROP INDEX `{s}`", .{idx.name}),
    }
}

fn mysqlEmitAlterDropFk(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try w.writeAll("DROP FOREIGN KEY fk_");
    for (fk.fields) |f| {
        try w.writeAll(f);
    }
}

fn mysqlEmitAlterTableComment(w: *Writer, _: []const u8, comment: []const u8) anyerror!void {
    try w.print("COMMENT='{s}'", .{comment});
}

fn mysqlCommentResult() CommentResult {
    return .added_to_alter;
}

fn mysqlEmitAlterEngine(w: *Writer, engine: ?[]const u8) anyerror!void {
    try w.print("ENGINE={s}", .{engine orelse "InnoDB"});
}

// ─── Type Rendering ────────────────────────────────────────

fn mysqlRenderDecimal(w: *Writer, sql_type: SqlType) anyerror!void {
    try w.print("decimal({d}, {d})", .{ sql_type.decimal.precision, sql_type.decimal.scale });
}

fn mysqlRenderVarchar(w: *Writer, sql_type: SqlType) anyerror!void {
    if (sql_type.varchar > 0) {
        try w.print("varchar({d})", .{sql_type.varchar});
    } else {
        try w.writeAll("varchar(255)");
    }
}

fn mysqlRenderEnumValues(w: *Writer, sql_type: SqlType) anyerror!void {
    try w.writeAll("ENUM(");
    for (sql_type.enum_values, 0..) |v, vi| {
        if (vi > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{v});
    }
    try w.writeAll(")");
}

const MYSQL_RENDER_TABLE = [_]dialect.RenderEntry{
    .{ .comptime_str = "int" }, // int
    .{ .comptime_str = "bigint" }, // bigint
    .{ .comptime_str = "smallint" }, // smallint
    .{ .render_fn = mysqlRenderDecimal }, // decimal
    .{ .render_fn = mysqlRenderVarchar }, // varchar
    .{ .comptime_str = "text" }, // text
    .{ .comptime_str = "blob" }, // blob
    .{ .comptime_str = "json" }, // json
    .{ .comptime_str = "json" }, // jsonb → json
    .{ .comptime_str = "datetime" }, // datetime
    .{ .comptime_str = "date" }, // date
    .{ .comptime_str = "timestamp" }, // timestamptz → timestamp
    .{ .comptime_str = "boolean" }, // boolean
    .{ .comptime_str = "char(36)" }, // uuid
    .{ .comptime_str = "varchar(45)" }, // inet
    .{ .comptime_str = "int" }, // serial → int
    .{ .render_fn = mysqlRenderEnumValues }, // enum_values
    .{ .comptime_str = "" }, // raw_sql — handled by passthrough fallback
    .{ .comptime_str = "" }, // passthrough — written from variant
};

fn mysqlRenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .raw_sql => |sql| try w.writeAll(sql),
        .passthrough => |t| try w.writeAll(t),
        else => try dialect.renderFromTable(w, sql_type, &MYSQL_RENDER_TABLE),
    }
}

// ─── View ──────────────────────────────────────────────────

fn mysqlEmitCreateView(w: *Writer, name: []const u8, query: []const u8) anyerror!void {
    try w.writeAll("CREATE OR REPLACE VIEW ");
    try mysqlQuoteIdent(w, name);
    try w.writeAll(" AS\n");
    try w.writeAll(query);
    try w.writeAll(";\n");
}

// ─── Forward Type Mapping (SS symbol → SqlType) ─────────────

fn mysqlLookupSym(sym: []const u8) ?SqlType {
    return common.lookupSymDefault(&.{}, sym);
}

// ─── Generated Columns ──────────────────────────────────────

fn mysqlEmitGeneratedColumn(w: *Writer, expr: []const u8, is_stored: bool) anyerror!void {
    try w.writeAll("GENERATED ALWAYS AS (");
    try w.writeAll(expr);
    try w.writeAll(") ");
    if (is_stored) {
        try w.writeAll("STORED");
    } else {
        try w.writeAll("VIRTUAL");
    }
}

// ─── Backend Instance ──────────────────────────────────────

pub const mysql_backend = DialectBackend{
    .quoteIdent = mysqlQuoteIdent,
    .emitIndex = mysqlEmitIndex,
    .emitTimestampModifier = mysqlEmitTimestampModifier,
    .emitTableFooter = mysqlEmitTableFooter,
    .emitTableComment = mysqlEmitTableComment,
    .emitColumnComment = mysqlEmitColumnComment,
    .emitPrimaryKey = mysqlEmitPrimaryKey,
    .emitInlineIndex = mysqlEmitInlineIndex,
    .emitStandaloneIndex = mysqlEmitStandaloneIndex,
    .emitInlineColumnComment = mysqlEmitInlineColumnComment,
    .emitEnumTypeCheck = mysqlEmitEnumTypeCheck,
    .emitInlineColumnStandaloneIndex = mysqlNoopInlineColumnIndex,
    .emitAlterDropColumn = mysqlEmitAlterDropColumn,
    .emitAlterModifyColumn = mysqlEmitAlterModifyColumn,
    .emitAlterRenameColumn = mysqlEmitAlterRenameColumn,
    .emitAlterAddIndex = mysqlEmitAlterAddIndex,
    .emitAlterDropIndex = mysqlEmitAlterDropIndex,
    .emitAlterDropFk = mysqlEmitAlterDropFk,
    .commentResult = mysqlCommentResult,
    .emitAlterTableComment = mysqlEmitAlterTableComment,
    .emitAlterEngine = mysqlEmitAlterEngine,
    .emitCreateView = mysqlEmitCreateView,
    .renderType = mysqlRenderType,
    .emitForeignKey = mysqlEmitForeignKey,
    // Optional: MySQL implements emitCreateDatabase, emitUnsigned, emitAutoIncrement
    .emitCreateDatabase = mysqlEmitCreateDatabase,
    .emitUnsigned = mysqlEmitUnsigned,
    .emitAutoIncrement = mysqlEmitAutoIncrement,
    .emitGeneratedColumn = mysqlEmitGeneratedColumn,
    // emitTypeMetadata and emitConfidenceComment use noop defaults
    .lookupSym = mysqlLookupSym,
    .quoteChar = '`',
    .rename_needs_column_def = true,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = false,
};

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "mysql: renderType maps common types" {
    const alloc = testing.allocator;

    // int
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysqlRenderType(w, .int);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("int", result);
    }
    // bigint
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysqlRenderType(w, .bigint);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("bigint", result);
    }
    // varchar(128)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysqlRenderType(w, .{ .varchar = 128 });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("varchar(128)", result);
    }
    // decimal(10, 2)
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysqlRenderType(w, .{ .decimal = .{ .precision = 10, .scale = 2 } });
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("decimal(10, 2)", result);
    }
    // boolean
    {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try mysqlRenderType(w, .boolean);
        try w.flush();
        const result = try aw.toOwnedSlice();
        defer alloc.free(result);
        try testing.expectEqualStrings("boolean", result);
    }
}

test "mysql: quoteChar is backtick" {
    try testing.expectEqual(@as(u8, '`'), mysql_backend.quoteChar);
}
