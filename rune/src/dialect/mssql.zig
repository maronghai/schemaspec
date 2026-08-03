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

// ─── MSSQL Backend ───────────────────────────────────────────

fn mssqlQuoteIdent(w: *Writer, name: []const u8) anyerror!void {
    try w.print("[{s}]", .{name});
}

fn mssqlEmitForeignKey(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try common.emitForeignKeyShared(w, fk, mssqlQuoteIdent);
}

fn mssqlEmitCreateView(w: *Writer, name: []const u8, query: []const u8) anyerror!void {
    try w.writeAll("CREATE VIEW ");
    try mssqlQuoteIdent(w, name);
    try w.writeAll(" AS\n");
    try w.writeAll(query);
    try w.writeAll(";\n");
}

// ─── Forward Methods ─────────────────────────────────────────

fn mssqlEmitIndex(w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void {
    try common.emitIndexWithQuote(w, idx, mssqlQuoteIdent, needs_comma, "FULLTEXT ");
}

fn mssqlEmitTimestampModifier(w: *Writer, _: bool) anyerror!void {
    // MSSQL: DEFAULT CURRENT_TIMESTAMP (no ON UPDATE equivalent)
    try w.writeAll(" DEFAULT CURRENT_TIMESTAMP");
}

fn mssqlEmitTableFooter(w: *Writer, _: ?[]const u8, _: ?[]const u8, _: ?[]const u8) anyerror!void {
    try w.writeAll(");\n");
}

fn mssqlEmitTableComment(_: *Writer, _: []const u8, _: []const u8) anyerror!void {
    // MSSQL: comments via sp_addextendedproperty, emitted as standalone
}

fn mssqlEmitColumnComment(_: *Writer, _: []const u8, _: []const u8, _: []const u8) anyerror!void {
    // MSSQL: comments via sp_addextendedproperty, emitted as standalone
}

fn mssqlEmitPrimaryKey(w: *Writer, _: bool) anyerror!void {
    // MSSQL: PRIMARY KEY (no AUTO_INCREMENT; uses IDENTITY separately)
    try w.writeAll(" PRIMARY KEY");
}

fn mssqlEmitInlineIndex(w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    if (is_unique) {
        try w.print("  UNIQUE INDEX [uk_{s}] ([{s}])", .{ col_name, col_name });
    } else {
        try w.print("  INDEX [idx_{s}] ([{s}])", .{ col_name, col_name });
    }
}

fn mssqlEmitStandaloneIndex(_: *Writer, _: []const u8, _: IndexDecl) anyerror!void {
    // MSSQL: regular indexes are emitted as standalone CREATE INDEX by common helper
}

fn mssqlEmitInlineColumnComment(w: *Writer, comment: []const u8) anyerror!void {
    const ct = common.stripCommentPrefix(comment);
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print(" /* {s} */", .{tr});
}

fn mssqlEmitEnumTypeCheck(w: *Writer, col_name: []const u8, enum_values: []const []const u8) anyerror!void {
    // MSSQL: no native ENUM, use CHECK constraint
    try w.writeAll(" CHECK (");
    try w.print("[{s}] IN (", .{col_name});
    for (enum_values, 0..) |v, vi| {
        if (vi > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{v});
    }
    try w.writeAll("))");
}

fn mssqlEmitInlineColumnStandaloneIndex(w: *Writer, table_name: []const u8, col_name: []const u8) anyerror!void {
    try w.writeAll("CREATE INDEX ");
    try w.print("[idx_{s}_{s}]", .{ table_name, col_name });
    try w.writeAll(" ON ");
    try mssqlQuoteIdent(w, table_name);
    try w.writeAll(" (");
    try mssqlQuoteIdent(w, col_name);
    try w.writeAll(");\n");
}

// ─── ALTER TABLE Methods ─────────────────────────────────────

fn mssqlEmitAlterDropColumn(w: *Writer, col_name: []const u8) anyerror!void {
    try w.writeAll("DROP COLUMN ");
    try mssqlQuoteIdent(w, col_name);
}

fn mssqlEmitAlterModifyColumn(w: *Writer, col_name: []const u8) anyerror!void {
    // MSSQL: ALTER COLUMN [name] TYPE
    try w.print("ALTER COLUMN [{s}] ", .{col_name});
}

fn mssqlEmitAlterRenameColumn(w: *Writer, old_name: []const u8, new_name: []const u8) anyerror!void {
    // MSSQL: sp_rename, but for DDL we use ALTER TABLE ... ALTER COLUMN pattern
    try w.print("sp_rename '[{s}]', '[{s}]'", .{ old_name, new_name });
}

fn mssqlEmitAlterAddIndex(w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void {
    // MSSQL: CREATE INDEX is standalone, not part of ALTER TABLE
    try common.emitAlterAddIndexStandalone(w, table_name, idx, mssqlQuoteIdent);
}

fn mssqlEmitAlterDropFk(w: *Writer, fk: ast_mod.FkDecl) anyerror!void {
    try common.emitAlterDropFkMssql(w, fk, "fk_", "", "_");
}

fn mssqlCommentResult() CommentResult {
    return .standalone_emitted;
}

fn mssqlEmitAlterTableComment(w: *Writer, _: []const u8, _: []const u8) anyerror!void {
    // MSSQL: comments via sp_addextendedproperty — emit as warning comment
    try w.writeAll("-- NOTE: Table comments require sp_addextendedproperty in MSSQL\n");
}

// ─── Type Rendering ────────────────────────────────────────

const MSSQL_RENDER_TABLE = [_]dialect.RenderEntry{
    .{ .comptime_str = "INT" }, // int
    .{ .comptime_str = "BIGINT" }, // bigint
    .{ .comptime_str = "SMALLINT" }, // smallint
    .{ .comptime_str = "" }, // decimal — handled by mssqlRenderType switch
    .{ .comptime_str = "" }, // varchar — handled by mssqlRenderType switch
    .{ .comptime_str = "NVARCHAR(MAX)" }, // text → NVARCHAR(MAX)
    .{ .comptime_str = "VARBINARY(MAX)" }, // blob → VARBINARY(MAX)
    .{ .comptime_str = "NVARCHAR(MAX)" }, // json → NVARCHAR(MAX)
    .{ .comptime_str = "NVARCHAR(MAX)" }, // jsonb → NVARCHAR(MAX)
    .{ .comptime_str = "DATETIME2" }, // datetime → DATETIME2
    .{ .comptime_str = "DATE" }, // date
    .{ .comptime_str = "DATETIMEOFFSET" }, // timestamptz → DATETIMEOFFSET
    .{ .comptime_str = "BIT" }, // boolean → BIT
    .{ .comptime_str = "UNIQUEIDENTIFIER" }, // uuid → UNIQUEIDENTIFIER
    .{ .comptime_str = "NVARCHAR(45)" }, // inet → NVARCHAR(45)
    .{ .comptime_str = "INT" }, // serial → INT (IDENTITY handled separately)
    .{ .comptime_str = "" }, // enum_values — handled by mssqlRenderType switch
    .{ .comptime_str = "" }, // raw_sql — handled by passthrough fallback
    .{ .comptime_str = "" }, // passthrough — written from variant
};

fn mssqlRenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .decimal => |d| try common.emitDecimal(w, "NUMERIC", d.precision, d.scale),
        .varchar => |n| try common.emitVarchar(w, "NVARCHAR", n, 255),
        .enum_values => try common.emitEnumFixedType(w, "NVARCHAR(255)"),
        else => try common.renderTypeFromTable(w, sql_type, &MSSQL_RENDER_TABLE),
    }
}

// ─── View ──────────────────────────────────────────────────

// ─── Forward Type Mapping (SS symbol → SqlType) ─────────────

fn mssqlLookupSym(sym: []const u8) ?SqlType {
    return common.lookupSymDefault(&.{}, sym);
}

// ─── Generated Columns ──────────────────────────────────────

fn mssqlEmitGeneratedColumn(w: *Writer, expr: []const u8, is_stored: bool) anyerror!void {
    // MSSQL: GENERATED ALWAYS AS (expr) [PERSISTED] (SQL Server 2016+)
    try w.writeAll("AS (");
    try w.writeAll(expr);
    try w.writeAll(")");
    if (is_stored) {
        try w.writeAll(" PERSISTED");
    }
}

// ─── Backend Instance ──────────────────────────────────────

pub const mssql_backend = DialectBackend{
    .quoteIdent = mssqlQuoteIdent,
    .emitIndex = mssqlEmitIndex,
    .emitTimestampModifier = mssqlEmitTimestampModifier,
    .emitTableFooter = mssqlEmitTableFooter,
    .emitTableComment = mssqlEmitTableComment,
    .emitColumnComment = mssqlEmitColumnComment,
    .emitPrimaryKey = mssqlEmitPrimaryKey,
    .emitInlineIndex = mssqlEmitInlineIndex,
    .emitStandaloneIndex = mssqlEmitStandaloneIndex,
    .emitInlineColumnComment = mssqlEmitInlineColumnComment,
    .emitEnumTypeCheck = mssqlEmitEnumTypeCheck,
    .emitInlineColumnStandaloneIndex = mssqlEmitInlineColumnStandaloneIndex,
    .emitAlterDropColumn = mssqlEmitAlterDropColumn,
    .emitAlterModifyColumn = mssqlEmitAlterModifyColumn,
    .emitAlterRenameColumn = mssqlEmitAlterRenameColumn,
    .emitAlterAddIndex = mssqlEmitAlterAddIndex,
    .emitAlterDropIndex = common.emitAlterDropIndexNoQuote,
    .emitAlterDropFk = mssqlEmitAlterDropFk,
    .commentResult = mssqlCommentResult,
    .emitAlterTableComment = mssqlEmitAlterTableComment,
    .emitAlterEngine = common.emitAlterEngineWarning,
    .emitCreateView = mssqlEmitCreateView,
    .renderType = mssqlRenderType,
    .emitForeignKey = mssqlEmitForeignKey,
    .emitGeneratedColumn = mssqlEmitGeneratedColumn,
    .lookupSym = mssqlLookupSym,
    .quoteChar = '[',
    .rename_needs_column_def = true,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = false,
};
