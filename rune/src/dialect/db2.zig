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
    try w.writeAll("CREATE OR REPLACE VIEW ");
    try db2QuoteIdent(w, name);
    try w.writeAll(" AS\n");
    try w.writeAll(query);
    try w.writeAll(";\n");
}

// ─── Forward Methods ─────────────────────────────────────────

fn db2EmitIndex(w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    try w.writeAll("  ");
    switch (idx.kind) {
        .regular => {
            try w.writeAll("INDEX ");
            try db2QuoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .unique => {
            try w.writeAll("UNIQUE ");
            try db2QuoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .fulltext => {
            // Db2: no native FULLTEXT INDEX, emit as regular INDEX
            try w.writeAll("INDEX ");
            try db2QuoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .primary_key => {
            try w.writeAll("PRIMARY KEY (");
        },
    }
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try db2QuoteIdent(w, f);
    }
    try w.writeAll(")");
}

fn db2EmitTimestampModifier(w: *Writer, _: bool) anyerror!void {
    // Db2: DEFAULT CURRENT_TIMESTAMP (no ON UPDATE equivalent)
    try w.writeAll(" DEFAULT CURRENT_TIMESTAMP");
}

fn db2EmitTableFooter(w: *Writer, _: ?[]const u8, _: ?[]const u8, _: ?[]const u8) anyerror!void {
    try w.writeAll(");\n");
}

fn db2EmitTableComment(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    const ct = common.stripCommentPrefix(comment);
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print("COMMENT ON TABLE \"{s}\" IS '{s}';\n", .{ table_name, tr });
}

fn db2EmitColumnComment(w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void {
    if (comment.len >= 1 and comment[0] == ':') {
        const ct = std.mem.trim(u8, common.stripCommentPrefix(comment), " ");
        if (ct.len > 0) try w.print("COMMENT ON COLUMN \"{s}\".\"{s}\" IS '{s}';\n", .{ table_name, col_name, ct });
    }
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
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    if (is_unique) {
        try w.print("  UNIQUE INDEX \"uk_{s}\" (\"{s}\")", .{ col_name, col_name });
    } else {
        try w.print("  INDEX \"idx_{s}\" (\"{s}\")", .{ col_name, col_name });
    }
}

fn db2EmitStandaloneIndex(_: *Writer, _: []const u8, _: IndexDecl) anyerror!void {
    // Db2: regular indexes are emitted as standalone CREATE INDEX by common helper
}

fn db2EmitInlineColumnComment(w: *Writer, comment: []const u8) anyerror!void {
    const ct = common.stripCommentPrefix(comment);
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) try w.print(" /* {s} */", .{tr});
}

fn db2EmitEnumTypeCheck(w: *Writer, col_name: []const u8, enum_values: []const []const u8) anyerror!void {
    // Db2: no native ENUM, use CHECK constraint
    try w.writeAll(" CHECK (");
    try w.print("\"{s}\" IN (", .{col_name});
    for (enum_values, 0..) |v, vi| {
        if (vi > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{v});
    }
    try w.writeAll("))");
}

fn db2EmitInlineColumnStandaloneIndex(w: *Writer, table_name: []const u8, col_name: []const u8) anyerror!void {
    try w.writeAll("CREATE INDEX ");
    try w.print("\"idx_{s}_{s}\"", .{ table_name, col_name });
    try w.writeAll(" ON ");
    try db2QuoteIdent(w, table_name);
    try w.writeAll(" (");
    try db2QuoteIdent(w, col_name);
    try w.writeAll(");\n");
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

fn db2EmitAlterDropIndex(w: *Writer, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .primary_key => try w.writeAll("DROP PRIMARY KEY"),
        else => try w.print("DROP INDEX {s}", .{idx.name}),
    }
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
    try w.print("COMMENT ON TABLE \"{s}\" IS '{s}';\n\n", .{ table_name, comment });
}

fn db2EmitAlterEngine(w: *Writer, _: ?[]const u8) anyerror!void {
    try w.writeAll("-- NOTE: ENGINE change is MySQL-only, ignored for this dialect\n");
}

// ─── Type Rendering ────────────────────────────────────────

fn db2RenderDecimal(w: *Writer, sql_type: SqlType) anyerror!void {
    try w.print("DECIMAL({d}, {d})", .{ sql_type.decimal.precision, sql_type.decimal.scale });
}

fn db2RenderVarchar(w: *Writer, sql_type: SqlType) anyerror!void {
    if (sql_type.varchar > 0) {
        try w.print("VARCHAR({d})", .{sql_type.varchar});
    } else {
        try w.writeAll("VARCHAR(255)");
    }
}

fn db2RenderEnumValues(w: *Writer, sql_type: SqlType) anyerror!void {
    // Db2: no native ENUM, use VARCHAR with CHECK constraint
    try w.writeAll("VARCHAR(255)");
    _ = sql_type;
}

const DB2_RENDER_TABLE = [_]dialect.RenderEntry{
    .{ .comptime_str = "INTEGER" }, // int → INTEGER
    .{ .comptime_str = "BIGINT" }, // bigint → BIGINT
    .{ .comptime_str = "SMALLINT" }, // smallint → SMALLINT
    .{ .render_fn = db2RenderDecimal }, // decimal → DECIMAL(p, s)
    .{ .render_fn = db2RenderVarchar }, // varchar → VARCHAR
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
    .{ .render_fn = db2RenderEnumValues }, // enum_values → VARCHAR(255)
    .{ .comptime_str = "" }, // raw_sql — handled by passthrough fallback
    .{ .comptime_str = "" }, // passthrough — written from variant
};

fn db2RenderType(w: *Writer, sql_type: SqlType) anyerror!void {
    switch (sql_type) {
        .raw_sql => |sql| try w.writeAll(sql),
        .passthrough => |t| try w.writeAll(t),
        else => try dialect.renderFromTable(w, sql_type, &DB2_RENDER_TABLE),
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
    .emitEnumTypeCheck = db2EmitEnumTypeCheck,
    .emitInlineColumnStandaloneIndex = db2EmitInlineColumnStandaloneIndex,
    .emitAlterDropColumn = db2EmitAlterDropColumn,
    .emitAlterModifyColumn = db2EmitAlterModifyColumn,
    .emitAlterRenameColumn = db2EmitAlterRenameColumn,
    .emitAlterAddIndex = db2EmitAlterAddIndex,
    .emitAlterDropIndex = db2EmitAlterDropIndex,
    .emitAlterDropFk = db2EmitAlterDropFk,
    .commentResult = db2CommentResult,
    .emitAlterTableComment = db2EmitAlterTableComment,
    .emitAlterEngine = db2EmitAlterEngine,
    .emitCreateView = db2EmitCreateView,
    .renderType = db2RenderType,
    .emitForeignKey = db2EmitForeignKey,
    .emitGeneratedColumn = db2EmitGeneratedColumn,
    .lookupSym = db2LookupSym,
    .quoteChar = '"',
    .rename_needs_column_def = false,
    .modify_needs_column_def = true,
    .modify_column_def_skips_name = false,
    .capability = .{
        .standalone_comments = true,
        .schemas = true,
        .generated_columns = true,
        .alter_drop_column = true,
    },
};
