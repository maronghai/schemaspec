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

fn pgEmitAlterAddIndex(w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void {
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
            // PG doesn't support adding regular indexes via ALTER TABLE.
            // Close the current ALTER TABLE and emit a standalone CREATE INDEX.
            try common.emitAlterAddIndexStandalone(w, table_name, idx, common.quoteIdentDoubleQuote);
        },
    }
}

fn pgEmitAlterDropFk(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try common.emitAlterDropFkShared(w, fk, "fk_", "", "_");
}

fn pgEmitAlterTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitAlterTableCommentShared(w, table_name, comment);
}

fn pgCommentResult() CommentResult {
    return .standalone_emitted;
}

// ─── PG-specific helpers ──────────────────────────────────────

fn pgEmitTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitTableCommentStandalone(w, table_name, comment);
}

fn pgEmitColumnComment(w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void {
    try common.emitColumnCommentStandalone(w, table_name, col_name, comment);
}

fn pgEmitAutoIncrement(w: *Writer) anyerror!void {
    try w.writeAll(" GENERATED ALWAYS AS IDENTITY");
}

// ─── Type Rendering ────────────────────────────────────────

const PG_RENDER_TABLE = [_]dialect.RenderEntry{
    .{ .comptime_str = "integer" }, // int → integer
    .{ .comptime_str = "bigint" }, // bigint
    .{ .comptime_str = "smallint" }, // smallint
    .{ .comptime_str = "" }, // decimal — handled by pgRenderType switch
    .{ .comptime_str = "" }, // varchar — handled by pgRenderType switch
    .{ .comptime_str = "text" }, // text
    .{ .comptime_str = "bytea" }, // blob → bytea
    .{ .comptime_str = "json" }, // json
    .{ .comptime_str = "jsonb" }, // jsonb
    .{ .comptime_str = "timestamp" }, // datetime → timestamp
    .{ .comptime_str = "date" }, // date
    .{ .comptime_str = "timestamptz" }, // timestamptz
    .{ .comptime_str = "boolean" }, // boolean
    .{ .comptime_str = "uuid" }, // uuid
    .{ .comptime_str = "inet" }, // inet
    .{ .comptime_str = "serial" }, // serial
    .{ .comptime_str = "" }, // enum_values — handled by pgRenderType switch
    .{ .comptime_str = "" }, // raw_sql
    .{ .comptime_str = "" }, // passthrough
};

fn pgRenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .decimal => |d| try common.emitDecimal(w, "numeric", d.precision, d.scale),
        .varchar => |n| try common.emitVarchar(w, "varchar", n, 255),
        .enum_values => try common.emitEnumFixedType(w, "TEXT"),
        else => try common.renderTypeFromTable(w, sql_type, &PG_RENDER_TABLE),
    }
}

// ─── View ──────────────────────────────────────────────────

fn pgEmitCreateView(w: *Writer, name: []const u8, query: []const u8) anyerror!void {
    try common.emitCreateViewShared(w, name, query, common.quoteIdentDoubleQuote);
}

// ─── Forward Type Mapping (SS symbol → SqlType) ─────────────

fn pgLookupSym(sym: []const u8) ?SqlType {
    return common.lookupSymDefault(&.{}, sym);
}

// ─── Generated Columns ──────────────────────────────────────

fn pgEmitGeneratedColumn(w: *Writer, expr: []const u8, is_stored: bool) anyerror!void {
    try w.writeAll("GENERATED ALWAYS AS (");
    try w.writeAll(expr);
    try w.writeAll(") ");
    // PG only supports STORED, not VIRTUAL — always emit STORED regardless of is_stored
    _ = is_stored;
    try w.writeAll("STORED");
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
    .emitInlineColumnComment = common.noopInlineColumnComment,
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
    .emitGeneratedColumn = pgEmitGeneratedColumn,
    // emitUnsigned, emitTypeMetadata, emitConfidenceComment use noop defaults
    .lookupSym = pgLookupSym,
    .quoteChar = '"',
    .rename_needs_column_def = false,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = true,
};
