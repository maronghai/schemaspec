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
const emitForeignKeyShared = common.emitForeignKeyShared;

// ─── PostgreSQL Backend ────────────────────────────────────────

fn pgEmitForeignKey(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try emitForeignKeyShared(w, fk, common.quoteIdentDoubleQuote);
}

fn pgEmitCreateDatabase(w: *Writer, name: []const u8, charset: ?[]const u8) anyerror!void {
    if (charset != null) {
        try w.print("CREATE DATABASE \"{s}\" ENCODING 'UTF8';\n\n", .{name});
    } else {
        try w.print("CREATE DATABASE \"{s}\";\n\n", .{name});
    }
}

fn pgEmitAlterModifyColumn(w: *Writer, col_name: []const u8) anyerror!void {
    try w.print("ALTER COLUMN \"{s}\" TYPE ", .{col_name});
}

fn pgEmitAlterAddIndex(w: *Writer, _: []const u8, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .unique => {
            try w.writeAll("ADD UNIQUE (");
            try common.emitIndexFields(w, idx);
            try w.writeAll(")");
        },
        .primary_key => {
            try w.writeAll("ADD PRIMARY KEY (");
            try common.emitIndexFields(w, idx);
            try w.writeAll(")");
        },
        else => {
            try w.print("-- NOTE: CREATE INDEX needed for '{s}' (not supported via ALTER TABLE in PG)\n", .{idx.name});
        },
    }
}

fn pgEmitAlterDropFk(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try w.writeAll("DROP CONSTRAINT \"fk_");
    for (fk.fields) |f| {
        try w.writeAll(f);
    }
    try w.writeAll("\"");
}

fn pgEmitAlterTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try w.print("COMMENT ON TABLE \"{s}\" IS '{s}';\n\n", .{ table_name, comment });
}

fn pgCommentResult() CommentResult {
    return .standalone_emitted;
}

// ─── PG-specific helpers ──────────────────────────────────────

fn pgEmitTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    const ct = if (comment.len >= 1 and comment[0] == ':') comment[1..] else comment;
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print("COMMENT ON TABLE \"{s}\" IS '{s}';\n", .{ table_name, tr });
}

fn pgEmitColumnComment(w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void {
    if (comment.len >= 1 and comment[0] == ':') {
        const ct = std.mem.trim(u8, comment[1..], " ");
        if (ct.len > 0) try w.print("COMMENT ON COLUMN \"{s}\".\"{s}\" IS '{s}';\n", .{ table_name, col_name, ct });
    }
}

fn pgEmitAutoIncrement(w: *Writer) anyerror!void {
    try w.writeAll(" GENERATED ALWAYS AS IDENTITY");
}

// ─── Type Rendering ────────────────────────────────────────

fn pgRenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .int => try w.writeAll("integer"),
        .bigint => try w.writeAll("bigint"),
        .smallint => try w.writeAll("smallint"),
        .decimal => |ds| try w.print("numeric({d}, {d})", .{ ds.precision, ds.scale }),
        .varchar => |n| {
            if (n > 0) {
                try w.print("varchar({d})", .{n});
            } else {
                try w.writeAll("varchar(255)");
            }
        },
        .text => try w.writeAll("text"),
        .blob => try w.writeAll("bytea"),
        .json => try w.writeAll("json"),
        .jsonb => try w.writeAll("jsonb"),
        .datetime => try w.writeAll("timestamp"),
        .date => try w.writeAll("date"),
        .timestamptz => try w.writeAll("timestamptz"),
        .boolean => try w.writeAll("boolean"),
        .uuid => try w.writeAll("uuid"),
        .inet => try w.writeAll("inet"),
        .serial => try w.writeAll("serial"),
        .enum_values => try w.writeAll("TEXT"),
        .raw_sql => |sql| try w.writeAll(sql),
        .passthrough => |t| try w.writeAll(t),
    }
}

// ─── View ──────────────────────────────────────────────────

fn pgEmitCreateView(w: *Writer, name: []const u8, query: []const u8) anyerror!void {
    try w.writeAll("CREATE OR REPLACE VIEW ");
    try common.quoteIdentDoubleQuote(w, name);
    try w.writeAll(" AS\n");
    try w.writeAll(query);
    try w.writeAll(";\n");
}

// ─── Forward Type Mapping (SS symbol → SqlType) ─────────────

fn pgLookupSym(sym: []const u8) ?SqlType {
    if (sym.len != 1) return null;
    return switch (sym[0]) {
        'n' => .int,
        'N' => .bigint,
        'i' => .smallint,
        'm' => .{ .decimal = .{ .precision = 16, .scale = 2 } },
        'M' => .{ .decimal = .{ .precision = 20, .scale = 6 } },
        'S' => .text,
        'b' => .boolean,
        'B' => .blob,
        'j' => .json,
        'd' => .date,
        't' => .datetime,
        'T' => .timestamptz,
        's' => .{ .varchar = 0 },
        'U' => .uuid,
        'p' => .serial,
        'J' => .jsonb,
        'I' => .inet,
        else => null,
    };
}

// ─── Backend Instance ──────────────────────────────────────

pub const pg_backend = DialectBackend{
    .quoteIdent = common.quoteIdentDoubleQuote,
    .emitIndex = common.emitIndex,
    .emitTimestampModifier = common.emitTimestampModifier,
    .emitTableFooter = common.emitTableFooter,
    .emitTableComment = pgEmitTableComment,
    .emitColumnComment = pgEmitColumnComment,
    .emitPrimaryKey = common.emitPrimaryKeyNormal,
    .emitInlineIndex = common.emitInlineIndexUnique,
    .emitStandaloneIndex = common.emitStandaloneIndex,
    .emitInlineColumnComment = common.noopInlineColumnCommentPG,
    .emitEnumTypeCheck = common.emitEnumTypeCheck,
    .emitInlineColumnStandaloneIndex = common.emitInlineColumnStandaloneIndex,
    .emitAlterDropColumn = common.emitAlterDropColumn,
    .emitAlterModifyColumn = pgEmitAlterModifyColumn,
    .emitAlterRenameColumn = common.emitAlterRenameColumn,
    .emitAlterAddIndex = pgEmitAlterAddIndex,
    .emitAlterDropIndex = common.emitAlterDropIndex,
    .emitAlterDropFk = pgEmitAlterDropFk,
    .commentResult = pgCommentResult,
    .emitAlterTableComment = pgEmitAlterTableComment,
    .emitAlterEngine = common.emitAlterEngineWarning,
    .emitCreateView = pgEmitCreateView,
    .renderType = pgRenderType,
    .emitForeignKey = pgEmitForeignKey,
    // Optional: PG implements emitCreateDatabase, emitAutoIncrement
    .emitCreateDatabase = pgEmitCreateDatabase,
    .emitAutoIncrement = pgEmitAutoIncrement,
    // emitUnsigned, emitTypeMetadata, emitConfidenceComment default to null (no-op)
    .lookupSym = pgLookupSym,
    .quoteChar = '"',
    .rename_needs_column_def = false,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = true,
};

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "pg: renderType maps common types" {
    const alloc = testing.allocator;
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try pgRenderType(w, .int);
    try w.flush();
    try testing.expectEqualStrings("integer", aw.getWritten());

    aw.deinit();
    var aw2 = std.Io.Writer.Allocating.init(alloc);
    const w2 = &aw2.writer;
    try pgRenderType(w2, .blob);
    try w2.flush();
    try testing.expectEqualStrings("bytea", aw2.getWritten());

    aw2.deinit();
    var aw3 = std.Io.Writer.Allocating.init(alloc);
    const w3 = &aw3.writer;
    try pgRenderType(w3, .{ .decimal = .{ .precision = 10, .scale = 2 } });
    try w3.flush();
    try testing.expectEqualStrings("numeric(10, 2)", aw3.getWritten());

    aw3.deinit();
    var aw4 = std.Io.Writer.Allocating.init(alloc);
    const w4 = &aw4.writer;
    try pgRenderType(w4, .boolean);
    try w4.flush();
    try testing.expectEqualStrings("boolean", aw4.getWritten());

    aw4.deinit();
    var aw5 = std.Io.Writer.Allocating.init(alloc);
    const w5 = &aw5.writer;
    try pgRenderType(w5, .timestamptz);
    try w5.flush();
    try testing.expectEqualStrings("timestamptz", aw5.getWritten());
}

test "pg: quoteChar is double-quote" {
    try testing.expectEqual(@as(u8, '"'), pg_backend.quoteChar);
}
