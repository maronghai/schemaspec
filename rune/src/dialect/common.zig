const std = @import("std");
const dialect_mod = @import("../dialect/dialect.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const SqlType = sql_type_mod.SqlType;
const Writer = std.Io.Writer;
const IndexDecl = ast_mod.IndexDecl;

// ─── Shared Symbol Lookup ────────────────────────────────────
//
// All three dialect backends (MySQL, PG, SQLite) map 18 single-char
// SS symbols to SqlType values. The default map covers MySQL/PG;
// SQLite overrides 3 entries ('N'→int, 'U'→passthrough TEXT, 'p'→passthrough INTEGER).

pub const SymEntry = struct { char: u8, sql_type: SqlType };

/// Default symbol map shared by MySQL and PostgreSQL.
pub const DEFAULT_SYM_MAP = [_]SymEntry{
    .{ .char = 'n', .sql_type = .int },
    .{ .char = 'N', .sql_type = .bigint },
    .{ .char = 'i', .sql_type = .smallint },
    .{ .char = 'm', .sql_type = .{ .decimal = .{ .precision = 16, .scale = 2 } } },
    .{ .char = 'M', .sql_type = .{ .decimal = .{ .precision = 20, .scale = 6 } } },
    .{ .char = 'S', .sql_type = .text },
    .{ .char = 'b', .sql_type = .boolean },
    .{ .char = 'B', .sql_type = .blob },
    .{ .char = 'j', .sql_type = .json },
    .{ .char = 'd', .sql_type = .date },
    .{ .char = 't', .sql_type = .datetime },
    .{ .char = 'T', .sql_type = .timestamptz },
    .{ .char = 's', .sql_type = .{ .varchar = 0 } },
    .{ .char = 'U', .sql_type = .uuid },
    .{ .char = 'p', .sql_type = .serial },
    .{ .char = 'J', .sql_type = .jsonb },
    .{ .char = 'I', .sql_type = .inet },
};

/// SQLite overrides: 'N'→int (no bigint), 'U'→TEXT, 'p'→INTEGER.
pub const SQLITE_SYM_MAP = [_]SymEntry{
    .{ .char = 'N', .sql_type = .int },
    .{ .char = 'U', .sql_type = .{ .passthrough = "TEXT" } },
    .{ .char = 'p', .sql_type = .{ .passthrough = "INTEGER" } },
};

/// Look up a SS symbol using a primary map with fallback to defaults.
/// SQLite passes SQLITE_SYM_MAP as overrides; MySQL/PG pass empty overrides.
pub fn lookupSymDefault(overrides: []const SymEntry, sym: []const u8) ?SqlType {
    if (sym.len != 1) return null;
    const ch = sym[0];
    for (overrides) |entry| {
        if (entry.char == ch) return entry.sql_type;
    }
    for (DEFAULT_SYM_MAP) |entry| {
        if (entry.char == ch) return entry.sql_type;
    }
    return null;
}

// ─── Shared Type Rendering ──────────────────────────────────

/// Shared renderType implementation for all dialect backends.
/// Handles raw_sql/passthrough passthrough, delegates to dialect-specific render table.
pub fn renderTypeFromTable(w: *Writer, sql_type: SqlType, comptime table: []const dialect_mod.RenderEntry) anyerror!void {
    switch (sql_type) {
        .raw_sql => |sql| try w.writeAll(sql),
        .passthrough => |t| try w.writeAll(t),
        else => try dialect_mod.renderFromTable(w, sql_type, table),
    }
}

// ─── Shared Type Rendering Helpers ────────────────────────────

/// Generic varchar rendering — shared by all 6 dialects.
/// `type_name` is the dialect-specific name (e.g. "varchar", "NVARCHAR", "VARCHAR2").
/// `n` is the varchar length; `default_size` is used when n == 0.
pub fn emitVarchar(w: *Writer, type_name: []const u8, n: usize, default_size: usize) anyerror!void {
    if (n > 0) {
        try w.print("{s}({d})", .{ type_name, n });
    } else {
        try w.print("{s}({d})", .{ type_name, default_size });
    }
}

/// Generic varchar rendering with a string default — used when the default is not a number.
/// `default` is emitted when n == 0 (e.g. SQLite's "TEXT" for varchar).
pub fn emitVarcharDefault(w: *Writer, type_name: []const u8, n: usize, default: []const u8) anyerror!void {
    if (n > 0) {
        try w.print("{s}({d})", .{ type_name, n });
    } else {
        try w.writeAll(default);
    }
}

/// Generic decimal rendering — shared by all 6 dialects.
/// `type_name` is the dialect-specific name (e.g. "decimal", "numeric", "NUMBER", "DECIMAL").
pub fn emitDecimal(w: *Writer, type_name: []const u8, precision: usize, scale: usize) anyerror!void {
    try w.print("{s}({d}, {d})", .{ type_name, precision, scale });
}

/// Generic enum values rendering for dialects without native ENUM.
/// Emits a fixed-size type string. Used by PG (TEXT), SQLite (TEXT), MSSQL (NVARCHAR(255)),
/// Oracle (VARCHAR2(255)), Db2 (VARCHAR(255)).
pub fn emitEnumFixedType(w: *Writer, fixed_type: []const u8) anyerror!void {
    try w.writeAll(fixed_type);
}

/// Shared ENUM values rendering for MySQL (native ENUM).
pub fn emitEnumValues(w: *Writer, values: []const []const u8) anyerror!void {
    try w.writeAll("ENUM(");
    for (values, 0..) |v, vi| {
        if (vi > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{v});
    }
    try w.writeAll(")");
}

// ─── Shared Comment Emission ────────────────────────────────

/// Write `s` with every single quote doubled ('') so the text survives
/// inside a SQL single-quoted string literal (apostrophes in comments or
/// defaults otherwise terminate the literal and corrupt the statement).
pub fn writeSqlSingleQuoted(w: *Writer, s: []const u8) anyerror!void {
    try w.writeByte('\'');
    for (s) |c| {
        if (c == '\'') try w.writeByte('\'');
        try w.writeByte(c);
    }
    try w.writeByte('\'');
}

/// Shared standalone COMMENT ON TABLE implementation (PG, Oracle, Db2, MSSQL).
pub fn emitTableCommentStandalone(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    const ct = stripCommentPrefix(comment);
    const tr = std.mem.trim(u8, ct, " ");
    if (tr.len > 0) {
        try w.print("COMMENT ON TABLE \"{s}\" IS ", .{table_name});
        try writeSqlSingleQuoted(w, tr);
        try w.writeAll(";\n");
    }
}

/// Shared standalone COMMENT ON COLUMN implementation (PG, Oracle, Db2).
pub fn emitColumnCommentStandalone(w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void {
    if (comment.len >= 1 and comment[0] == ':') {
        const ct = std.mem.trim(u8, stripCommentPrefix(comment), " ");
        if (ct.len > 0) {
            try w.print("COMMENT ON COLUMN \"{s}\".\"{s}\" IS ", .{ table_name, col_name });
            try writeSqlSingleQuoted(w, ct);
            try w.writeAll(";\n");
        }
    }
}

// ─── Shared View Rendering ──────────────────────────────────

/// Shared CREATE OR REPLACE VIEW implementation (MySQL, PG, Oracle, Db2).
pub fn emitCreateViewShared(w: *Writer, name: []const u8, query: []const u8, quoteIdent: QuoteIdentFn) anyerror!void {
    try w.writeAll("CREATE OR REPLACE VIEW ");
    try quoteIdent(w, name);
    try w.writeAll(" AS\n");
    try w.writeAll(query);
    try w.writeAll(";\n");
}

// ─── Shared PG/SQLite Dialect Logic ──────────────────────────
//
// Functions shared between PostgreSQL and SQLite backends.
// Extracted from dialect.zig for single-responsibility.
//
// MySQL uses backtick quoting and inline comments;
// PG/SQLite both use double-quote quoting and standalone comments.
// These functions capture the common PG/SQLite behavior.

// ─── Comment Stripping ───────────────────────────────────────
// SS comments prefixed with `:` are metadata comments (not user comments).
// Both PG and SQLite strip this prefix before emitting SQL comments.

pub fn stripCommentPrefix(comment: []const u8) []const u8 {
    if (comment.len >= 1 and comment[0] == ':') return comment[1..];
    return comment;
}

// ─── Identifier Quoting ──────────────────────────────────────

pub fn quoteIdentDoubleQuote(w: *Writer, name: []const u8) anyerror!void {
    try w.print("\"{s}\"", .{name});
}

// ─── Inline Index Emission ───────────────────────────────────

/// Parameterized inline index emission — shared by MySQL, MSSQL, Oracle, Db2.
/// Eliminates 4 near-identical implementations that differ only in identifier quoting.
/// `open`/`close` are the identifier quote characters (e.g. '`' for MySQL, '['/']' for MSSQL, '"' for Oracle/Db2).
pub fn emitInlineIndexWithQuote(w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool, comptime open: u8, comptime close: u8) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    if (is_unique) {
        try w.writeAll("  UNIQUE INDEX ");
        try w.print("{c}uk_{s}{c} ({c}{s}{c})", .{ open, col_name, close, open, col_name, close });
    } else {
        try w.writeAll("  INDEX ");
        try w.print("{c}idx_{s}{c} ({c}{s}{c})", .{ open, col_name, close, open, col_name, close });
    }
}

/// Parameterized standalone CREATE INDEX for column-level inline indexes.
/// Used by MSSQL and Db2 (MySQL handles inline indexes in CREATE TABLE, Oracle uses no-op).
pub fn emitStandaloneCreateIndexWithQuote(w: *Writer, table_name: []const u8, col_name: []const u8, comptime open: u8, comptime close: u8) anyerror!void {
    try w.writeAll("CREATE INDEX ");
    try w.print("{c}idx_{s}_{s}{c}", .{ open, col_name, table_name, close });
    try w.writeAll(" ON ");
    try w.print("{c}{s}{c} ({c}{s}{c})", .{ open, table_name, close, open, col_name, close });
    try w.writeAll(";\n");
}

pub fn emitIndex(w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void {
    switch (idx.kind) {
        .regular => return,
        .fulltext => return,
        .unique => {
            if (needs_comma.*) try w.writeAll(",\n");
            needs_comma.* = true;
            try w.writeAll("  UNIQUE (");
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("\"{s}\"", .{f});
            }
            try w.writeAll(")");
        },
        .primary_key => {
            if (needs_comma.*) try w.writeAll(",\n");
            needs_comma.* = true;
            try w.writeAll("  PRIMARY KEY (");
            for (idx.fields, 0..) |f, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("\"{s}\"", .{f});
            }
            try w.writeAll(")");
        },
    }
}

pub fn emitInlineIndexUnique(w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool) anyerror!void {
    if (is_unique) {
        if (needs_comma.*) try w.writeAll(",\n");
        needs_comma.* = true;
        try w.print("  UNIQUE (\"{s}\")", .{col_name});
    }
    // Regular inline index: no-op for PG/SQLite
}

// ─── Standalone Index Emission ───────────────────────────────

pub fn emitStandaloneIndex(w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void {
    if (idx.kind == .primary_key or idx.kind == .unique or idx.kind == .fulltext) return;
    try w.writeAll("CREATE INDEX ");
    if (idx.name.len > 0) {
        try w.print("\"{s}\"", .{idx.name});
    } else {
        try w.print("\"idx_{s}_{s}\"", .{ table_name, idx.fields[0] });
    }
    try w.print(" ON \"{s}\" (", .{table_name});
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try w.print("\"{s}\"", .{f});
    }
    try w.writeAll(");\n");
}

pub fn emitInlineColumnStandaloneIndex(w: *Writer, table_name: []const u8, col_name: []const u8) anyerror!void {
    try w.writeAll("CREATE INDEX ");
    try w.print("\"idx_{s}_{s}\"", .{ table_name, col_name });
    try w.writeAll(" ON ");
    try quoteIdentDoubleQuote(w, table_name);
    try w.writeAll(" (");
    try quoteIdentDoubleQuote(w, col_name);
    try w.writeAll(");\n");
}

// ─── Type Modifiers ──────────────────────────────────────────

pub fn emitUnsigned(_: *Writer) anyerror!void {}

pub fn emitTimestampModifier(w: *Writer, _: bool) anyerror!void {
    try w.writeAll(" DEFAULT CURRENT_TIMESTAMP");
}

// ─── Table Structure ─────────────────────────────────────────

pub fn emitTableFooter(w: *Writer, _: ?[]const u8, _: ?[]const u8, _: ?[]const u8) anyerror!void {
    try w.writeAll(");\n");
}

pub fn emitPrimaryKeyNormal(w: *Writer, _: bool) anyerror!void {
    try w.writeAll(" PRIMARY KEY");
}

// ─── Enum Type Check ─────────────────────────────────────────

pub fn emitEnumTypeCheck(w: *Writer, col_name: []const u8, enum_values: []const []const u8) anyerror!void {
    try w.writeAll(" CHECK (");
    try w.print("\"{s}\" IN (", .{col_name});
    for (enum_values, 0..) |v, vi| {
        if (vi > 0) try w.writeAll(", ");
        try w.print("'{s}'", .{v});
    }
    try w.writeAll("))");
}

// ─── ALTER TABLE Methods ─────────────────────────────────────

pub fn emitAlterDropColumn(w: *Writer, col_name: []const u8) anyerror!void {
    try w.writeAll("DROP COLUMN \"");
    try w.writeAll(col_name);
    try w.writeAll("\"");
}

pub fn emitAlterRenameColumn(w: *Writer, old_name: []const u8, new_name: []const u8) anyerror!void {
    try w.print("RENAME COLUMN \"{s}\" TO \"{s}\"", .{ old_name, new_name });
}

pub fn emitAlterDropIndex(w: *Writer, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .primary_key => try w.writeAll("DROP PRIMARY KEY"),
        else => try w.print("DROP INDEX IF EXISTS \"{s}\"", .{idx.name}),
    }
}

/// Shared DROP INDEX without IF EXISTS or quoting (Oracle, MSSQL, Db2).
pub fn emitAlterDropIndexNoQuote(w: *Writer, idx: IndexDecl) anyerror!void {
    switch (idx.kind) {
        .primary_key => try w.writeAll("DROP PRIMARY KEY"),
        else => try w.print("DROP INDEX {s}", .{idx.name}),
    }
}

pub fn emitAlterEngineWarning(w: *Writer, _: ?[]const u8) anyerror!void {
    try w.writeAll("-- NOTE: ENGINE change is MySQL-only, ignored for this dialect\n");
}

/// Shared emitAlterTableComment for dialects using COMMENT ON TABLE syntax (PG, Oracle, Db2).
pub fn emitAlterTableCommentShared(w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void {
    try w.print("COMMENT ON TABLE \"{s}\" IS ", .{table_name});
    try writeSqlSingleQuoted(w, comment);
    try w.writeAll(";\n\n");
}

/// Shared emitIndex for non-MySQL dialects.
/// `fulltext_prefix` is the keyword before "INDEX" for fulltext indexes.
/// MSSQL passes "FULLTEXT ", Oracle/Db2 pass "" (no special fulltext syntax).
pub fn emitIndexWithQuote(w: *Writer, idx: IndexDecl, quoteIdent: QuoteIdentFn, needs_comma: *bool, fulltext_prefix: []const u8) anyerror!void {
    if (needs_comma.*) try w.writeAll(",\n");
    needs_comma.* = true;
    try w.writeAll("  ");
    switch (idx.kind) {
        .regular => {
            try w.writeAll("INDEX ");
            try quoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .unique => {
            try w.writeAll("UNIQUE ");
            try quoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .fulltext => {
            try w.writeAll(fulltext_prefix);
            try w.writeAll("INDEX ");
            try quoteIdent(w, idx.name);
            try w.writeAll(" (");
        },
        .primary_key => {
            try w.writeAll("PRIMARY KEY (");
        },
    }
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try quoteIdent(w, f);
    }
    try w.writeAll(")");
}

// ─── Shared ALTER TABLE Helpers ──────────────────────────────
// Consolidated from per-dialect implementations to eliminate duplication.
// Each dialect passes its own quote function and naming convention.

/// Emit DROP CONSTRAINT with FK name derived from field names.
/// Eliminates identical ~6-line implementations across PG, MSSQL, Oracle, Db2.
/// Constructs: DROP CONSTRAINT "prefix_field1_field2_suffix" (double-quoted).
/// For MSSQL (square brackets), dialects should call with their own quoting.
pub fn emitAlterDropFkShared(w: *Writer, fk: ast_mod.FkDecl, prefix: []const u8, suffix: []const u8, sep: []const u8) anyerror!void {
    try w.writeAll("DROP CONSTRAINT \"");
    try w.writeAll(prefix);
    for (fk.fields, 0..) |f, i| {
        if (i > 0) try w.writeAll(sep);
        try w.writeAll(f);
    }
    try w.writeAll(suffix);
    try w.writeAll("\"");
}

/// Emit DROP CONSTRAINT with FK name using square bracket quoting (MSSQL).
pub fn emitAlterDropFkMssql(w: *Writer, fk: ast_mod.FkDecl, prefix: []const u8, suffix: []const u8, sep: []const u8) anyerror!void {
    try w.writeAll("DROP CONSTRAINT [");
    try w.writeAll(prefix);
    for (fk.fields, 0..) |f, i| {
        if (i > 0) try w.writeAll(sep);
        try w.writeAll(f);
    }
    try w.writeAll(suffix);
    try w.writeAll("]");
}

/// Emit standalone CREATE INDEX then reopen ALTER TABLE for next operation.
/// Used by PG, Oracle, Db2, MSSQL (MySQL handles indexes inline).
pub fn emitAlterAddIndexStandalone(w: *Writer, table_name: []const u8, idx: IndexDecl, quoteIdent: QuoteIdentFn) anyerror!void {
    try w.writeAll(";\n\nCREATE ");
    if (idx.kind == .unique) try w.writeAll("UNIQUE ");
    try w.writeAll("INDEX ");
    try quoteIdent(w, idx.name);
    try w.writeAll(" ON ");
    try quoteIdent(w, table_name);
    try w.writeAll(" (");
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try quoteIdent(w, f);
    }
    try w.writeAll(");\n\nALTER TABLE ");
    try quoteIdent(w, table_name);
    try w.writeAll("\n");
}

// ─── Index Field Helper ──────────────────────────────────────

pub fn emitIndexFields(w: *Writer, idx: IndexDecl) !void {
    for (idx.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try w.print("\"{s}\"", .{f});
    }
}

// ─── Shared FK Rendering ────────────────────────────────────
// Single source of truth for FOREIGN KEY constraint rendering.
// Each dialect backend passes its own quoteIdent function pointer.

pub const QuoteIdentFn = *const fn (w: *Writer, name: []const u8) anyerror!void;

pub fn emitForeignKeyShared(w: *Writer, fk: ast_mod.FkDecl, quoteIdent: QuoteIdentFn) anyerror!void {
    try w.writeAll("FOREIGN KEY (");
    for (fk.fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try quoteIdent(w, f);
    }
    try w.writeAll(") REFERENCES ");
    try quoteIdent(w, fk.ref_table);
    try w.writeAll("(");
    for (fk.ref_fields, 0..) |f, fi| {
        if (fi > 0) try w.writeAll(", ");
        try quoteIdent(w, f);
    }
    try w.writeAll(")");
    for (fk.actions) |action| {
        try w.writeAll(" ");
        switch (action.trigger) {
            .on_delete => try w.writeAll("ON DELETE"),
            .on_update => try w.writeAll("ON UPDATE"),
        }
        try w.writeAll(" ");
        switch (action.action) {
            .cascade => try w.writeAll("CASCADE"),
            .set_null => try w.writeAll("SET NULL"),
            .set_default => try w.writeAll("SET DEFAULT"),
            .restrict => try w.writeAll("RESTRICT"),
            .no_action => try w.writeAll("NO ACTION"),
        }
    }
}

// ─── Inline Column Comment No-op ────────────────────────────
// PG and SQLite handle column comments via standalone statements,
// not inline in column definitions. Both share this no-op implementation.

pub fn noopInlineColumnComment(_: *Writer, _: []const u8) anyerror!void {}
