const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const Writer = std.Io.Writer;
const IndexDecl = ast_mod.IndexDecl;
const CheckConstraint = ast_mod.CheckConstraint;
const Dialect = dialect_enum.Dialect;
const SqlType = sql_type_mod.SqlType;

// ─── Reverse Result (shared by reverse_map.zig + dialect backends) ──

pub const ReverseResult = struct {
    sym: []const u8,
    omit: bool,
    /// Confidence score 0-100. Higher = more certain.
    score: u8 = 100,
};

// ─── canOmitType: shared helper for reverse lookup ────────────

pub fn canOmitType(col_name: []const u8, sym: []const u8, is_auto_inc: bool, is_default_ts: bool) bool {
    if (is_auto_inc or is_default_ts) return false;
    if (col_name.len > 3) {
        if (std.mem.endsWith(u8, col_name, "_id") and std.mem.eql(u8, sym, "n")) return true;
        if (std.mem.endsWith(u8, col_name, "_on") and std.mem.eql(u8, sym, "d")) return true;
        if (std.mem.endsWith(u8, col_name, "_at") and std.mem.eql(u8, sym, "t")) return true;
    }
    return std.mem.eql(u8, sym, "s");
}

// ─── DialectBackend: vtable for dialect-specific SQL generation ─
//
// Adding a new dialect requires only:
//   1. Add a new enum variant to Dialect (in dialect_enum.zig)
//   2. Create a new DialectBackend instance (in dialect_<name>.zig)
//   3. Register it in the getBackend() switch below
//
// All dialect-specific rendering goes through this vtable.
// codegen.zig is fully dialect-agnostic.

/// Result of emitAlterTableComment — tells the caller how to update state.
pub const CommentResult = enum {
    added_to_alter, // MySQL: comment emitted inline in ALTER TABLE
    standalone_emitted, // PG: standalone COMMENT ON TABLE emitted; caller should close ALTER
    unsupported, // SQLite: warning comment emitted; no state change needed
};

// ─── Noop defaults for optional vtable methods ──────────────

fn noopWriteEmpty(_: *Writer) anyerror!void {}
fn noopEmitCreateDatabase(_: *Writer, _: []const u8, _: ?[]const u8) anyerror!void {}
fn noopEmitTypeMetadata(_: *Writer, _: []const u8, _: []const u8) anyerror!void {}
fn noopEmitConfidenceComment(_: *Writer, _: []const u8) anyerror!void {}
fn noopReverseLookup(_: []const u8, _: []const u8, _: bool, _: bool) ?ReverseResult {
    return null;
}
fn noopEmitGeneratedColumn(_: *Writer, _: []const u8, _: bool) anyerror!void {}

pub const DialectBackend = struct {
    // ══════════════════════════════════════════════════════════════
    // SECTION 1: Shared Methods (used by multiple subsystems)
    // ══════════════════════════════════════════════════════════════

    /// Quote an identifier (e.g. column/table name) with the dialect's quote character.
    /// MySQL: `name`, PG/SQLite: "name".
    quoteIdent: *const fn (w: *Writer, name: []const u8) anyerror!void,

    /// Render a SqlType to dialect-specific SQL type string. Single source of truth for type rendering.
    renderType: *const fn (w: *Writer, sql_type: SqlType) anyerror!void,

    /// Render a FOREIGN KEY constraint (inline or standalone). Single source of truth for FK rendering.
    emitForeignKey: *const fn (w: *Writer, fk: ast_mod.FkDecl) anyerror!void,

    /// Emit CREATE VIEW statement.
    emitCreateView: *const fn (w: *Writer, name: []const u8, query: []const u8) anyerror!void,

    // ══════════════════════════════════════════════════════════════
    // SECTION 2: Forward Methods (CREATE TABLE codegen)
    // ══════════════════════════════════════════════════════════════

    /// Emit a standalone INDEX definition (after all column definitions).
    /// `needs_comma`: output param — set to true if a comma was emitted (caller manages comma state).
    emitIndex: *const fn (w: *Writer, idx: IndexDecl, needs_comma: *bool) anyerror!void,

    /// Emit timestamp modifier: DEFAULT CURRENT_TIMESTAMP [ON UPDATE CURRENT_TIMESTAMP].
    emitTimestampModifier: *const fn (w: *Writer, with_on_update: bool) anyerror!void,

    /// Emit the closing clause of CREATE TABLE (ENGINE, CHARSET, COMMENT, closing paren).
    /// All params may be null — dialect decides what to emit.
    emitTableFooter: *const fn (w: *Writer, engine: ?[]const u8, charset: ?[]const u8, comment: ?[]const u8) anyerror!void,

    /// Emit a standalone table comment (MySQL: inline, PG: COMMENT ON TABLE).
    emitTableComment: *const fn (w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void,

    /// Emit a column comment. MySQL: inline after column def, PG: standalone COMMENT ON COLUMN.
    emitColumnComment: *const fn (w: *Writer, table_name: []const u8, col_name: []const u8, comment: []const u8) anyerror!void,

    /// Emit PRIMARY KEY [AUTO_INCREMENT]. PG/SQLite omit AUTO_INCREMENT keyword.
    emitPrimaryKey: *const fn (w: *Writer, auto_increment: bool) anyerror!void,

    /// Emit an inline UNIQUE/INDEX after column definition. `needs_comma`: output param.
    emitInlineIndex: *const fn (w: *Writer, col_name: []const u8, is_unique: bool, needs_comma: *bool) anyerror!void,

    /// Emit a standalone (non-inline) INDEX definition.
    emitStandaloneIndex: *const fn (w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void,

    /// Emit an inline column comment (MySQL only — PG uses standalone).
    emitInlineColumnComment: *const fn (w: *Writer, comment: []const u8) anyerror!void,

    /// Emit a CHECK constraint for enum types (MySQL: ENUM literal, PG: CHECK(val IN (...))).
    emitEnumTypeCheck: *const fn (w: *Writer, col_name: []const u8, enum_values: []const []const u8) anyerror!void,

    /// Emit a standalone index for an inline-indexed column (after column definitions).
    emitInlineColumnStandaloneIndex: *const fn (w: *Writer, table_name: []const u8, col_name: []const u8) anyerror!void,

    // ══════════════════════════════════════════════════════════════
    // SECTION 3: Alter Methods (diff/migrate operations)
    // ══════════════════════════════════════════════════════════════

    /// Emit ALTER TABLE ... DROP COLUMN.
    emitAlterDropColumn: *const fn (w: *Writer, col_name: []const u8) anyerror!void,

    /// Emit ALTER TABLE ... MODIFY COLUMN (MySQL) / ALTER COLUMN (PG).
    emitAlterModifyColumn: *const fn (w: *Writer, col_name: []const u8) anyerror!void,

    /// Emit ALTER TABLE ... CHANGE COLUMN (MySQL) / RENAME COLUMN (PG/SQLite).
    emitAlterRenameColumn: *const fn (w: *Writer, old_name: []const u8, new_name: []const u8) anyerror!void,

    /// Emit ADD INDEX for ALTER TABLE.
    emitAlterAddIndex: *const fn (w: *Writer, table_name: []const u8, idx: IndexDecl) anyerror!void,

    /// Emit DROP INDEX for ALTER TABLE.
    emitAlterDropIndex: *const fn (w: *Writer, idx: IndexDecl) anyerror!void,

    /// Emit DROP FOREIGN KEY for ALTER TABLE.
    emitAlterDropFk: *const fn (w: *Writer, fk: ast_mod.FkDecl) anyerror!void,

    /// Returns how this dialect handles table comments in ALTER context.
    commentResult: *const fn () CommentResult,

    /// Emit table comment in ALTER TABLE context. See CommentResult for dialect behavior.
    emitAlterTableComment: *const fn (w: *Writer, table_name: []const u8, comment: []const u8) anyerror!void,

    /// Emit ENGINE change in ALTER TABLE (MySQL only).
    emitAlterEngine: *const fn (w: *Writer, engine: ?[]const u8) anyerror!void,

    // ══════════════════════════════════════════════════════════════
    // SECTION 4: Type Mapping (SS symbol → SqlType)
    // ══════════════════════════════════════════════════════════════

    /// Look up SqlType for a SS symbol (e.g. "n" → .int, "B" → .blob).
    /// Each dialect owns its own forward mapping — adding a new dialect is a local change.
    lookupSym: *const fn (sym: []const u8) ?SqlType,

    /// Quote character for identifiers in diff output (backtick for MySQL, double-quote for PG/SQLite).
    quoteChar: u8,

    // ══════════════════════════════════════════════════════════════
    // SECTION 5: Optional Methods (noop defaults — callers can call directly)
    // ══════════════════════════════════════════════════════════════

    /// CREATE DATABASE — only MySQL/PG implement; SQLite has no concept of databases.
    emitCreateDatabase: *const fn (w: *Writer, name: []const u8, charset: ?[]const u8) anyerror!void = noopEmitCreateDatabase,
    /// UNSIGNED modifier — only MySQL uses; PG/SQLite have no UNSIGNED.
    emitUnsigned: *const fn (w: *Writer) anyerror!void = noopWriteEmpty,
    /// AUTO_INCREMENT keyword — only MySQL uses; PG uses GENERATED AS IDENTITY, SQLite uses PRIMARY KEY AUTOINCREMENT.
    emitAutoIncrement: *const fn (w: *Writer) anyerror!void = noopWriteEmpty,
    /// SQLite-specific SS type metadata comment (e.g. `-- @sym col_type`).
    emitTypeMetadata: *const fn (w: *Writer, col_name: []const u8, sym_type: []const u8) anyerror!void = noopEmitTypeMetadata,
    /// SQLite-specific confidence comment (e.g. ` -- [score:42]`).
    emitConfidenceComment: *const fn (w: *Writer, confidence: []const u8) anyerror!void = noopEmitConfidenceComment,
    /// Dialect-specific reverse lookup. Returns null to fall back to general logic in reverse/map.zig.
    reverseLookup: *const fn (sql_type: []const u8, col_name: []const u8, is_auto_inc: bool, is_default_ts: bool) ?ReverseResult = noopReverseLookup,
    /// Emit GENERATED ALWAYS AS (expr) [VIRTUAL|STORED] for generated columns. noop = dialect doesn't support.
    emitGeneratedColumn: *const fn (w: *Writer, expr: []const u8, is_stored: bool) anyerror!void = noopEmitGeneratedColumn,

    // ══════════════════════════════════════════════════════════════
    // SECTION 6: Behavioral Flags (eliminate dialect checks in caller)
    // ══════════════════════════════════════════════════════════════

    /// MySQL CHANGE COLUMN requires the full column definition after the rename.
    rename_needs_column_def: bool,
    /// MODIFY COLUMN: MySQL/PG need column def, SQLite just emits a warning.
    modify_needs_column_def: bool,
    /// PG ALTER COLUMN TYPE skips the column name (it's in the ALTER prefix).
    modify_column_def_skips_name: bool,
};

pub fn getBackend(dialect: Dialect) DialectBackend {
    return switch (dialect) {
        .mysql => @import("../dialect/mysql.zig").mysql_backend,
        .pg => @import("../dialect/pg.zig").pg_backend,
        .sqlite => @import("../dialect/sqlite.zig").sqlite_backend,
    };
}

// ─── Comptime Dialect Validation ──────────────────────────────
// Validates at compile time that each backend implements all required vtable methods.
// Required fields are non-optional function pointers — their existence is guaranteed by the struct literal,
// but this check ensures they are not accidentally set to undefined at comptime.

fn validateBackend(comptime backend: DialectBackend) void {
    comptime {
        // ── Section 1: Shared methods ──
        if (@typeInfo(@TypeOf(backend.quoteIdent)) != .pointer) @compileError("quoteIdent must be a function pointer");
        if (@typeInfo(@TypeOf(backend.renderType)) != .pointer) @compileError("renderType must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitForeignKey)) != .pointer) @compileError("emitForeignKey must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitCreateView)) != .pointer) @compileError("emitCreateView must be a function pointer");

        // ── Section 2: Forward methods ──
        if (@typeInfo(@TypeOf(backend.emitIndex)) != .pointer) @compileError("emitIndex must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitTimestampModifier)) != .pointer) @compileError("emitTimestampModifier must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitTableFooter)) != .pointer) @compileError("emitTableFooter must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitTableComment)) != .pointer) @compileError("emitTableComment must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitColumnComment)) != .pointer) @compileError("emitColumnComment must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitPrimaryKey)) != .pointer) @compileError("emitPrimaryKey must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitInlineIndex)) != .pointer) @compileError("emitInlineIndex must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitStandaloneIndex)) != .pointer) @compileError("emitStandaloneIndex must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitInlineColumnComment)) != .pointer) @compileError("emitInlineColumnComment must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitEnumTypeCheck)) != .pointer) @compileError("emitEnumTypeCheck must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitInlineColumnStandaloneIndex)) != .pointer) @compileError("emitInlineColumnStandaloneIndex must be a function pointer");

        // ── Section 3: Alter methods ──
        if (@typeInfo(@TypeOf(backend.emitAlterDropColumn)) != .pointer) @compileError("emitAlterDropColumn must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterModifyColumn)) != .pointer) @compileError("emitAlterModifyColumn must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterRenameColumn)) != .pointer) @compileError("emitAlterRenameColumn must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterAddIndex)) != .pointer) @compileError("emitAlterAddIndex must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterDropIndex)) != .pointer) @compileError("emitAlterDropIndex must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterDropFk)) != .pointer) @compileError("emitAlterDropFk must be a function pointer");
        if (@typeInfo(@TypeOf(backend.commentResult)) != .pointer) @compileError("commentResult must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterTableComment)) != .pointer) @compileError("emitAlterTableComment must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAlterEngine)) != .pointer) @compileError("emitAlterEngine must be a function pointer");

        // ── Section 4: Type mapping ──
        if (@typeInfo(@TypeOf(backend.lookupSym)) != .pointer) @compileError("lookupSym must be a function pointer");
    }
}

/// Validate optional methods — ensure all function pointers are valid.
fn validateOptionalMethods(comptime backend: DialectBackend, comptime name: []const u8) void {
    comptime {
        if (@typeInfo(@TypeOf(backend.emitCreateDatabase)) != .pointer) @compileError(name ++ ": emitCreateDatabase must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitUnsigned)) != .pointer) @compileError(name ++ ": emitUnsigned must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitAutoIncrement)) != .pointer) @compileError(name ++ ": emitAutoIncrement must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitTypeMetadata)) != .pointer) @compileError(name ++ ": emitTypeMetadata must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitConfidenceComment)) != .pointer) @compileError(name ++ ": emitConfidenceComment must be a function pointer");
        if (@typeInfo(@TypeOf(backend.reverseLookup)) != .pointer) @compileError(name ++ ": reverseLookup must be a function pointer");
        if (@typeInfo(@TypeOf(backend.emitGeneratedColumn)) != .pointer) @compileError(name ++ ": emitGeneratedColumn must be a function pointer");
    }
}

// Validate all dialect backends at comptime
comptime {
    validateBackend(@import("../dialect/mysql.zig").mysql_backend);
    validateBackend(@import("../dialect/pg.zig").pg_backend);
    validateBackend(@import("../dialect/sqlite.zig").sqlite_backend);
    validateOptionalMethods(@import("../dialect/mysql.zig").mysql_backend, "mysql");
    validateOptionalMethods(@import("../dialect/pg.zig").pg_backend, "pg");
    validateOptionalMethods(@import("../dialect/sqlite.zig").sqlite_backend, "sqlite");
}

// ─── Table-Driven Type Rendering ────────────────────────────
// Shared data structure for renderType implementations.
// Each dialect defines a comptime table of RenderEntry values,
// one per SqlType variant. Simple types use comptime_str;
// complex types (decimal, varchar, enum_values) use render_fn.

pub const RenderEntry = struct {
    /// Static string output for simple types. Used when render_fn is null.
    comptime_str: []const u8 = "",
    /// Custom render function for parameterized types (decimal, varchar, enum_values).
    /// If null, comptime_str is written instead.
    render_fn: ?*const fn (w: *Writer, sql_type: SqlType) anyerror!void = null,
};

/// Render a SqlType using a comptime dispatch table.
/// Looks up the active tag in the table, calls render_fn if set, else writes comptime_str.
pub fn renderFromTable(w: *Writer, sql_type: SqlType, comptime table: []const RenderEntry) anyerror!void {
    const tag = @intFromEnum(sql_type);
    const entry = if (tag < table.len) table[tag] else RenderEntry{};
    if (entry.render_fn) |fn_ptr| {
        try fn_ptr(w, sql_type);
    } else {
        try w.writeAll(entry.comptime_str);
    }
}

// ─── Shared helpers (dialect-independent) ──────────────────────

pub fn emitCheckExpr(w: *Writer, field_name: []const u8, ck: CheckConstraint) !void {
    switch (ck.kind) {
        .range => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} BETWEEN {s} AND {s}", .{ field_name, low, high });
        },
        .range_upper_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} >= {s} AND {s} < {s}", .{ field_name, low, field_name, high });
        },
        .range_lower_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} > {s} AND {s} <= {s}", .{ field_name, low, field_name, high });
        },
        .range_both_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} > {s} AND {s} < {s}", .{ field_name, low, field_name, high });
        },
        .in_list => {
            try w.print("{s} IN (", .{field_name});
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            var first = true;
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len == 0) continue;
                if (!first) try w.writeAll(", ");
                first = false;
                const is_num = blk: {
                    _ = std.fmt.parseFloat(f64, trimmed) catch break :blk false;
                    break :blk true;
                };
                if (is_num) {
                    try w.print("{s}", .{trimmed});
                } else {
                    const val = if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'')
                        trimmed[1 .. trimmed.len - 1]
                    else
                        trimmed;
                    try w.print("'{s}'", .{val});
                }
            }
            try w.writeAll(")");
        },
        .comparison => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            var first = true;
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len == 0) continue;
                if (!first) try w.writeAll(" AND ");
                first = false;
                if (trimmed[0] == '>' and trimmed.len > 1 and trimmed[1] == '=') {
                    try w.print("{s} >= {s}", .{ field_name, trimmed[2..] });
                } else if (trimmed[0] == '<' and trimmed.len > 1 and trimmed[1] == '=') {
                    try w.print("{s} <= {s}", .{ field_name, trimmed[2..] });
                } else if (trimmed[0] == '>') {
                    try w.print("{s} > {s}", .{ field_name, trimmed[1..] });
                } else if (trimmed[0] == '<') {
                    try w.print("{s} < {s}", .{ field_name, trimmed[1..] });
                } else if (trimmed[0] == '=') {
                    try w.print("{s} = {s}", .{ field_name, trimmed[1..] });
                } else {
                    try w.print("{s} = {s}", .{ field_name, trimmed });
                }
            }
        },
    }
}
