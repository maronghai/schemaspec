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

// ─── Db2 Backend ──────────────────────────────────────────────
// IBM Db2 LUW (Linux, Unix, Windows) backend.
// Key characteristics:
//   - Double-quote identifier quoting (like PG/Oracle)
//   - GENERATED ALWAYS AS IDENTITY for auto-increment
//   - BOOLEAN type (Db2 9.7+)
//   - COMMENT ON for table/column comments
//   - GENERATED ALWAYS AS (expr) STORED for generated columns (Db2 11.1+)
//   - RENAME COLUMN support (Db2 10.5+)
//   - Schema-qualified names (like PG)

fn db2QuoteIdent(w: *Writer, name: []const u8) anyerror!void {
    try w.print("\"{s}\"", .{name});
}

fn db2EmitForeignKey(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try common.emitForeignKeyShared(w, fk, db2QuoteIdent);
}

fn db2EmitCreateView(w: *Writer, name: []const u8, query: []const u8) anyerror!void {
    try common.emitCreateViewShared(w, name, query, db2QuoteIdent);
}

// ─── Forward Methods ─────────────────────────────────────────

fn db2EmitIndex(w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void {
    try common.emitIndexWithQuote(w, idx, db2QuoteIdent, needs_comma, "");
}

fn db2EmitTimestampModifier(w: *Writer, _: bool) anyerror!void {
    // Db2: DEFAULT CURRENT_TIMESTAMP (no ON UPDATE equivalent)
    try w.writeAll(" DEFAULT CURRENT_TIMESTAMP");
}

fn db2EmitTableFooter(w: *Writer, _: ?[]const u8, _: ?[]const u8, _: ?[]const u8) anyerror!void {
    try w.writeAll(");\n");
}

fn db2EmitTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitTableCommentStandalone(w, table_name, comment);
}

fn db2EmitColumnComment(w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitColumnCommentStandalone(w, table_name, col_name, comment);
}

fn db2EmitPrimaryKey(w: *Writer, auto_increment: bool) anyerror!void {
    if (auto_increment) {
        // Db2: PRIMARY KEY with GENERATED ALWAYS AS IDENTITY
        try w.writeAll(" PRIMARY KEY GENERATED ALWAYS AS IDENTITY");
    } else {
        try w.writeAll(" PRIMARY KEY");
    }
}

fn db2EmitInlineIndex(w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool) anyerror!void {
    try common.emitInlineIndexWithQuote(w, col_name, is_unique, needs_comma, '"', '"');
}

fn db2EmitStandaloneIndex(_: *Writer, _: []const u8, _: IndexDecl) anyerror!void {
    // Db2: regular indexes are emitted as standalone CREATE INDEX by common helper
}

fn db2EmitInlineColumnComment(w: *Writer, comment: []const u8) anyerror!void {
    const ct = common.stripCommentPrefix(comment);
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print(" /* {s} */", .{tr});
}

fn db2EmitInlineColumnStandaloneIndex(_: *Writer, _: []const u8, _: []const u8) anyerror!void {
    // Db2 handles inline indexes via db2EmitInlineIndex — no standalone needed
}

// ─── ALTER TABLE Methods ─────────────────────────────────────

fn db2EmitAlterDropColumn(w: *Writer, col_name: []const u8) anyerror!void {
    try w.writeAll("DROP COLUMN ");
    try db2QuoteIdent(w, col_name);
}

fn db2EmitAlterModifyColumn(w: *Writer, col_name: []const u8) anyerror!void {
    // Db2: ALTER TABLE ... ALTER COLUMN col_name SET DATA TYPE ...
    try w.print("ALTER COLUMN \"{s}\" SET DATA TYPE ", .{col_name});
}

fn db2EmitAlterRenameColumn(w: *Writer, old_name: []const u8, new_name: []const u8) anyerror!void {
    // Db2 10.5+: RENAME COLUMN old TO new
    try w.print("RENAME COLUMN \"{s}\" TO \"{s}\"", .{ old_name, new_name });
}

fn db2EmitAlterAddIndex(w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void {
    // Db2: CREATE INDEX is standalone, not part of ALTER TABLE
    try common.emitAlterAddIndexStandalone(w, table_name, idx, db2QuoteIdent);
}

fn db2EmitAlterDropFk(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    // Db2 uses DROP FOREIGN KEY (like MySQL), not DROP CONSTRAINT
    try w.writeAll("DROP FOREIGN KEY \"fk_");
    for (fk.fields, 0..) |f, i| {
        if (i > 0) try w.writeAll("_");
        try w.writeAll(f);
    }
    try w.writeAll("\"");
}

fn db2CommentResult() CommentResult {
    return .standalone_emitted;
}

fn db2EmitAlterTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitAlterTableCommentShared(w, table_name, comment);
}

// ─── Type Rendering ────────────────────────────────────────

const DB2_RENDER_TABLE = [_]dialect.RenderEntry{
    .{ .comptime_str = "INTEGER" }, // int → INTEGER
    .{ .comptime_str = "BIGINT" }, // bigint → BIGINT
    .{ .comptime_str = "SMALLINT" }, // smallint → SMALLINT
    .{ .comptime_str = "" }, // decimal — handled by db2RenderType switch
    .{ .comptime_str = "" }, // varchar — handled by db2RenderType switch
    .{ .comptime_str = "CLOB" }, // text → CLOB
    .{ .comptime_str = "BLOB" }, // blob → BLOB
    .{ .comptime_str = "CLOB" }, // json → CLOB
    .{ .comptime_str = "CLOB" }, // jsonb → CLOB
    .{ .comptime_str = "TIMESTAMP" }, // datetime → TIMESTAMP
    .{ .comptime_str = "DATE" }, // date → DATE
    .{ .comptime_str = "TIMESTAMP WITH TIME ZONE" }, // timestamptz
    .{ .comptime_str = "BOOLEAN" }, // boolean → BOOLEAN (Db2 9.7+)
    .{ .comptime_str = "CHAR(16) FOR BIT DATA" }, // uuid → CHAR(16) FOR BIT DATA
    .{ .comptime_str = "VARCHAR(45)" }, // inet → VARCHAR(45)
    .{ .comptime_str = "INTEGER" }, // serial → INTEGER (identity handled by emitPrimaryKey)
    .{ .comptime_str = "" }, // enum_values — handled by db2RenderType switch
    .{ .comptime_str = "" }, // raw_sql — handled by passthrough fallback
    .{ .comptime_str = "" }, // passthrough — written from variant
};

fn db2RenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .decimal => |d| try common.emitDecimal(w, "DECIMAL", d.precision, d.scale),
        .varchar => |n| try common.emitVarchar(w, "VARCHAR", n, 255),
        .enum_values => try common.emitEnumFixedType(w, "VARCHAR(255)"),
        else => try common.renderTypeFromTable(w, sql_type, &DB2_RENDER_TABLE),
    }
}

// ─── Forward Type Mapping (SS symbol → SqlType) ─────────────

fn db2LookupSym(sym: []const u8) ?SqlType {
    return common.lookupSymDefault(&.{}, sym);
}

// ─── Generated Columns ──────────────────────────────────────

fn db2EmitGeneratedColumn(w: *Writer, expr: []const u8, is_stored: bool) anyerror!void {
    // Db2 11.1+: GENERATED ALWAYS AS (expr) [STORED|VIRTUAL]
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

pub const db2_backend = DialectBackend{
    .quoteIdent = db2QuoteIdent,
    .emitIndex = db2EmitIndex,
    .emitTimestampModifier = db2EmitTimestampModifier,
    .emitTableFooter = db2EmitTableFooter,
    .emitTableComment = db2EmitTableComment,
    .emitColumnComment = db2EmitColumnComment,
    .emitPrimaryKey = db2EmitPrimaryKey,
    .emitInlineIndex = db2EmitInlineIndex,
    .emitStandaloneIndex = db2EmitStandaloneIndex,
    .emitInlineColumnComment = db2EmitInlineColumnComment,
    .emitEnumTypeCheck = common.emitEnumTypeCheck,
    .emitInlineColumnStandaloneIndex = db2EmitInlineColumnStandaloneIndex,
    .emitAlterDropColumn = db2EmitAlterDropColumn,
    .emitAlterModifyColumn = db2EmitAlterModifyColumn,
    .emitAlterRenameColumn = db2EmitAlterRenameColumn,
    .emitAlterAddIndex = db2EmitAlterAddIndex,
    .emitAlterDropIndex = common.emitAlterDropIndexNoQuote,
    .emitAlterDropFk = db2EmitAlterDropFk,
    .commentResult = db2CommentResult,
    .emitAlterTableComment = db2EmitAlterTableComment,
    .emitAlterEngine = common.emitAlterEngineWarning,
    .emitCreateView = db2EmitCreateView,
    .renderType = db2RenderType,
    .emitForeignKey = db2EmitForeignKey,
    .emitGeneratedColumn = db2EmitGeneratedColumn,
    .lookupSym = db2LookupSym,
    .quoteChar = '"',
    .rename_needs_column_def = false,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = false,
};
