const std = @import("std");
const ast_mod = @import("ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const ir_version = @import("ir_version.zig");
const Writer = std.Io.Writer;
const Field = ast_mod.Field;
const TypeInfo = ast_mod.TypeInfo;
const Modifier = ast_mod.Modifier;
const DefaultVal = ast_mod.DefaultVal;
const CheckConstraint = ast_mod.CheckConstraint;
const FkDecl = ast_mod.FkDecl;
const FkAction = ast_mod.FkAction;
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
const SqlComment = ast_mod.SqlComment;
const Dialect = dialect_enum.Dialect;

// ─── TypedAst: Dialect-agnostic IR between Semantic and Codegen ─
//
// ResolvedAst → TypedAst resolves types to structured SqlType.
// TypedAst → SQL: SqlType.toSql(dialect, writer) renders dialect-specific output.
// TypedAst → JSON/Prisma: inspect SqlType variants directly (no SQL binding).
// SqlType is defined in sql_type.zig.

pub const ColumnFlags = packed struct {
    nullable: bool = false,
    primary_key: bool = false,
    auto_increment: bool = false,
    unsigned: bool = false,
    inline_unique: bool = false,
    inline_index: bool = false,
    is_enum: bool = false,
    is_datetime: bool = false,
    has_timestamp_default: bool = false,
    on_update_current_timestamp: bool = false,
    is_virtual: bool = false,
    is_stored: bool = false,
};

pub const TypedAst = struct {
    /// IR format version for forward/backward compatibility detection.
    ir_version: u32 = ir_version.CURRENT_IR_VERSION,
    schema_name: ?[]const u8,
    schema_charset: ?[]const u8,
    /// Custom type definitions from ~ directives (carried from ResolvedAst).
    custom_types: []const ast_mod.CustomType = &.{},
    tables: []const TypedTable,
    views: []const TypedView,
    sql_comments: []const SqlComment,
};

pub const TypedView = struct {
    name: []const u8,
    query: []const u8,
    comment: ?[]const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    line_no: usize,
    /// UNION/INTERSECT/EXCEPT operator (null if no set operation).
    union_op: ?ast_mod.ViewUnionOp = null,
    /// Second SELECT query for set operations (null if no set operation).
    second_query: ?[]const u8 = null,
};

pub const TypedTable = struct {
    name: []const u8,
    comment: ?[]const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    engine: ?[]const u8,
    columns: []const TypedColumn,
    fks: []const FkDecl,
    indexes: []const IndexDecl,
    line_no: usize,
};

pub const TypedColumn = struct {
    name: []const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    sql_type: sql_type_mod.SqlType,
    /// Original SS symbol string for roundtrip preservation (SQLite only).
    /// Used to emit `-- @sym col_name symbol` comments that the reverse
    /// pipeline reads back to preserve the original DSL type symbol.
    /// Null for PG/MySQL (they don't need symbol roundtrip).
    ss_symbol: ?[]const u8 = null,
    flags: ColumnFlags = .{},
    default: ?[]const u8,
    check: ?CheckConstraint,
    comment: ?[]const u8,
    enum_values: []const []const u8,
    generated_expr: ?[]const u8 = null,
    line_no: usize,
};

// ─── Resolution: ResolvedAst → TypedAst ──────────────────────
//
// Extracted to type_resolver.zig in v0.4.54 Phase 3.
