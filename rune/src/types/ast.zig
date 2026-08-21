const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── Source Location ─────────────────────────────────────────

pub const SourceLocation = struct {
    line: usize, // 1-based line number
    col: usize, // 1-based column number
    offset: usize, // 0-based byte offset from start of file
};

// ─── Type Category ────────────────────────────────────────────

/// Semantic category of an SS type symbol. Used by both forward pipeline
/// (TypeInfo) and reverse mapping (REVERSE_MAP) to avoid duplicated logic.
pub const TypeCategory = enum {
    numeric,
    string,
    datetime,
    boolean,
    blob,
    other,
};

/// Get the TypeCategory for a raw SS symbol string.
/// Used by REVERSE_MAP entries and TypeInfo.category().
pub fn categoryFromSym(sym: []const u8) TypeCategory {
    if (sym.len == 1) return switch (sym[0]) {
        'n', 'N', 'i', 'm', 'M', 'p' => .numeric,
        's', 'S', 'j', 'J', 'I', 'U' => .string,
        'd', 't', 'T' => .datetime,
        'b' => .boolean,
        'B' => .blob,
        else => .other,
    };
    // Multi-char symbols are passthrough (string)
    return .string;
}

// ─── AST Types ───────────────────────────────────────────────

pub const TypeInfo = union(enum) {
    none,
    simple: []const u8,
    int_explicit: usize,
    decimal_explicit: struct { precision: usize, scale: usize },
    varchar_explicit: usize,
    enum_type: []const []const u8,
    /// Raw SQL type string — passed through directly, no further resolution.
    /// Used by dialect-specific custom type overrides.
    raw_sql: []const u8,

    /// Check if two TypeInfo values represent the same SS type.
    pub fn eql(a: TypeInfo, b: TypeInfo) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .none => true,
            .simple => |s| std.mem.eql(u8, s, b.simple),
            .raw_sql => |s| std.mem.eql(u8, s, b.raw_sql),
            .int_explicit => |n| n == b.int_explicit,
            .decimal_explicit => |ds| ds.precision == b.decimal_explicit.precision and ds.scale == b.decimal_explicit.scale,
            .varchar_explicit => |n| n == b.varchar_explicit,
            .enum_type => |vals| {
                if (vals.len != b.enum_type.len) return false;
                for (vals, 0..) |v, i| {
                    if (!std.mem.eql(u8, v, b.enum_type[i])) return false;
                }
                return true;
            },
        };
    }

    /// Semantic category of this type. Single source of truth for type classification.
    /// Used by both forward pipeline (TypeInfo) and reverse mapping (REVERSE_MAP).
    pub fn category(self: TypeInfo) TypeCategory {
        return switch (self) {
            .none => .other,
            .int_explicit, .decimal_explicit => .numeric,
            .varchar_explicit, .enum_type => .string,
            .raw_sql => .other,
            .simple => |s| categoryFromSym(s),
        };
    }

    /// True if the SS symbol maps to a numeric SQL type (int, bigint, decimal, etc.).
    pub fn isNumeric(self: TypeInfo) bool {
        return self.category() == .numeric;
    }

    /// True if the SS symbol maps to a string/text SQL type (varchar, char, json, etc.).
    pub fn isString(self: TypeInfo) bool {
        return self.category() == .string;
    }

    /// True if the SS symbol maps to a datetime/date/time SQL type.
    pub fn isDatetime(self: TypeInfo) bool {
        return self.category() == .datetime;
    }

    /// True if the SS symbol maps to a boolean SQL type.
    pub fn isBoolean(self: TypeInfo) bool {
        return self.category() == .boolean;
    }

    /// True if the SS symbol maps to a blob/binary SQL type.
    pub fn isBlob(self: TypeInfo) bool {
        return self.category() == .blob;
    }

    /// True if the SS symbol maps to an uncategorized SQL type.
    pub fn isOther(self: TypeInfo) bool {
        return self.category() == .other;
    }
};

pub const ModifierType = enum {
    auto_inc_pk,
    auto_inc,
    primary_key,
    nullable,
    unsigned,
    inline_unique,
    inline_index,
    virtual,
    stored,
};

pub const Modifier = struct {
    kind: ModifierType,
    line_no: usize,
};

pub const DefaultVal = struct {
    value: []const u8,
    line_no: usize,
};

pub const CheckKind = enum {
    range, // [a,b] — BETWEEN inclusive
    range_upper_exclusive, // [a,b) — upper exclusive
    range_lower_exclusive, // (a,b] — lower exclusive
    range_both_exclusive, // (a,b) — both exclusive
    in_list, // {a,b} — IN list
    comparison, // {>0} — comparison
};

pub const CheckConstraint = struct {
    kind: CheckKind,
    expr: []const u8,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const Field = struct {
    name: []const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    type_info: TypeInfo,
    modifiers: []const Modifier,
    default_val: ?DefaultVal,
    check: ?CheckConstraint,
    fk: ?FkDecl,
    comment: ?[]const u8,
    generated_expr: ?[]const u8 = null,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const FkActionType = enum {
    cascade,
    set_null,
    set_default,
    restrict,
    no_action,
};

pub const FkActionTrigger = enum {
    on_delete,
    on_update,
};

pub const FkAction = struct {
    trigger: FkActionTrigger,
    action: FkActionType,
};

pub const FkDecl = struct {
    fields: []const []const u8,
    ref_table: []const u8,
    ref_fields: []const []const u8,
    actions: []const FkAction,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const IndexType = enum {
    regular,
    unique,
    fulltext,
    primary_key,
};

pub const IndexDecl = struct {
    kind: IndexType,
    name: []const u8,
    fields: []const []const u8,
    descending: []const bool,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const Template = struct {
    name: ?[]const u8,
    parents: []const []const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    fields: []const Field,
    slot_index: ?usize,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const Table = struct {
    template_ref: ?[]const u8,
    name: []const u8,
    comment: ?[]const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    engine: ?[]const u8,
    fields: []const Field,
    fks: []const FkDecl,
    indexes: []const IndexDecl,
    /// Conditional blocks: fields between @if and @endif that are dialect-specific.
    /// Each block specifies which dialects it applies to and the field index range.
    conditional_blocks: []const ConditionalBlock = &.{},
    /// Composite type embeds (`*name` lines inside the table body), in source order.
    embeds: []const CompositeEmbed = &.{},
    line_no: usize,
    loc: ?SourceLocation = null,
};

/// Reusable field grouping declared at top level: `* name` followed by field lines.
/// Expanded in place at each embed site by the resolve_composites semantic pass.
pub const Composite = struct {
    name: []const u8,
    fields: []const Field,
    line_no: usize,
    loc: ?SourceLocation = null,
};

/// An embed site inside a table body: `*name`, expanded at insert_pos
/// (index into the table's literal field list, before composite expansion).
pub const CompositeEmbed = struct {
    name: []const u8,
    insert_pos: usize,
    line_no: usize,
};

/// A conditional block within a table: @if(dialect=pg|sqlite) ... @endif
/// Fields within the block are only included when compiling for a matching dialect.
pub const ConditionalBlock = struct {
    /// List of dialect names this block applies to (e.g., {"pg", "sqlite"}).
    dialects: []const []const u8,
    /// Start index in the table's fields array (inclusive).
    start_field: usize,
    /// End index in the table's fields array (exclusive).
    end_field: usize,
    line_no: usize,
};

/// Custom type definition: ~ name base_type [dialect=type ...]
pub const CustomType = struct {
    name: []const u8,
    base: TypeInfo,
    /// Dialect-specific overrides: key is dialect name ("mysql", "postgres", "sqlite")
    dialect_overrides: []const DialectOverride,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const DialectOverride = struct {
    dialect: Dialect,
    type_info: TypeInfo,
};

pub const Schema = struct {
    name: []const u8,
    charset: ?[]const u8,
    autofk: bool,
    /// User-defined type aliases via ~ directive
    custom_types: []const CustomType,
    /// Schema version via @version directive
    version: ?[]const u8 = null,
    line_no: usize,
    loc: ?SourceLocation = null,
};

pub const SqlComment = struct {
    text: []const u8,
    line_no: usize,
};

pub const ViewUnionOp = enum {
    union_all,
    union_distinct,
    intersect,
    except,
};

pub const View = struct {
    name: []const u8,
    query: []const u8,
    comment: ?[]const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    line_no: usize,
    loc: ?SourceLocation = null,
    /// UNION/INTERSECT/EXCEPT operator (null if no set operation).
    union_op: ?ViewUnionOp = null,
    /// Second SELECT query for set operations (null if no set operation).
    second_query: ?[]const u8 = null,
};

pub const Ast = struct {
    schema: ?Schema,
    templates: []const Template,
    tables: []const Table,
    views: []const View,
    sql_comments: []const SqlComment,
    /// Composite type declarations (`* name` at top level).
    composites: []const Composite = &.{},
    /// Number of parse errors recorded during parsing.
    /// When > 0, the AST is partial (some tables/templates may be missing).
    error_count: usize = 0,
};
