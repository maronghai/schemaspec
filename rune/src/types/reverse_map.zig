const sql_type_mod = @import("./sql_type.zig");
const SqlType = sql_type_mod.SqlType;
const dialect_enum = @import("../dialect/enum.zig");
const ast_mod = @import("./ast.zig");
const TypeCategory = ast_mod.TypeCategory;
const categoryFromSym = ast_mod.categoryFromSym;

// ─── Reverse Mapping Data: SQL → SS ─────────────────────────
//
// All entries that reverse codegen may encounter. Includes:
//   - Core single-char entries (for SQLite which has lossy type affinity)
//   - MySQL/PG/MSSQL variant types (tinyint, serial, jsonb, nvarchar, etc.)
//   - Passthrough types (uuid, real, float4, float8)
//
// Priority ordering: lower number = preferred when multiple SQL types
// map to the same SS symbol. Checked top-to-bottom; first match wins.
//
// Canonical entries (rev_priority=10) carry a sql_type tag that links
// to the SqlType union. The consistency test in type_map.zig verifies
// that these match the forward mapping in sqlTypeName().
//
// To add a new dialect:
//   1. Add entry to DIALECT_NAMES array below
//   2. Add a field to DialectTypeMap struct
//   3. Add case to getDialectType switch
//   4. Add type strings to REVERSE_MAP entries

/// Ordered list of supported dialects. Used by comptime iteration in
/// reverse/map.zig and diff/semantic.zig for dialect-agnostic matching.
pub const DIALECT_NAMES = [_]dialect_enum.Dialect{ .mysql, .pg, .sqlite, .mssql, .oracle, .db2 };

pub const DialectTypeMap = struct {
    mysql: []const u8 = "",
    pg: []const u8 = "",
    sqlite: []const u8 = "",
    mssql: []const u8 = "",
    oracle: []const u8 = "",
    db2: []const u8 = "",
};

/// Get the SQL type string for a given dialect from a DialectTypeMap.
/// To add a new dialect, add a case here matching the Dialect enum variant.
pub fn getDialectType(map: DialectTypeMap, dialect: dialect_enum.Dialect) []const u8 {
    return switch (dialect) {
        .mysql => map.mysql,
        .pg => map.pg,
        .sqlite => map.sqlite,
        .mssql => map.mssql,
        .oracle => map.oracle,
        .db2 => map.db2,
    };
}

pub const ReverseMapping = struct {
    sym: []const u8,
    types: DialectTypeMap,
    /// Reverse-match priority: lower = preferred.
    rev_priority: u32 = 0,
    /// SqlType tag for canonical entries (null for non-canonical variants).
    /// Used by the consistency test to verify forward/reverse mapping agreement.
    sql_type: ?SqlType = null,
    /// Confidence base score (0-100) for this mapping entry.
    /// Core canonical symbols: 100, dialect variants: 80-95, passthrough: 70.
    confidence_base: u8 = 100,
    /// Semantic category of this mapping's SS symbol.
    /// Computed from sym via categoryFromSym — single source of truth with TypeInfo.
    category: TypeCategory = .other,
};

/// Helper to create a ReverseMapping with category auto-computed from sym.
/// Reduces boilerplate: category is always derived from the symbol, never hardcoded.
pub fn rev(
    comptime sym: []const u8,
    types: DialectTypeMap,
    comptime rest: struct {
        rev_priority: u32 = 0,
        sql_type: ?SqlType = null,
        confidence_base: u8 = 100,
    },
) ReverseMapping {
    return .{
        .sym = sym,
        .types = types,
        .rev_priority = rest.rev_priority,
        .sql_type = rest.sql_type,
        .confidence_base = rest.confidence_base,
        .category = categoryFromSym(sym),
    };
}

pub const REVERSE_MAP = [_]ReverseMapping{
    // ─── Core single-char symbols (used by SQLite reverse) ───
    rev("n", .{ .mysql = "int", .pg = "integer", .sqlite = "INTEGER", .mssql = "INT", .oracle = "NUMBER(10)", .db2 = "INTEGER" }, .{ .rev_priority = 10, .sql_type = .int }),
    rev("N", .{ .mysql = "bigint", .pg = "bigint", .sqlite = "INTEGER", .mssql = "BIGINT", .oracle = "NUMBER(19)", .db2 = "BIGINT" }, .{ .rev_priority = 10, .sql_type = .bigint }),
    rev("M", .{ .mysql = "decimal(20, 6)", .pg = "numeric(20, 6)", .sqlite = "NUMERIC", .mssql = "NUMERIC(20, 6)", .oracle = "NUMBER(20, 6)", .db2 = "DECIMAL(20, 6)" }, .{ .rev_priority = 10, .sql_type = .{ .decimal = .{ .precision = 20, .scale = 6 } } }),
    rev("S", .{ .mysql = "text", .pg = "text", .sqlite = "TEXT", .mssql = "NVARCHAR(MAX)", .oracle = "CLOB", .db2 = "CLOB" }, .{ .rev_priority = 10, .sql_type = .text }),
    rev("b", .{ .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER", .mssql = "BIT", .oracle = "NUMBER(1)", .db2 = "BOOLEAN" }, .{ .rev_priority = 10, .sql_type = .boolean }),
    rev("B", .{ .mysql = "blob", .pg = "bytea", .sqlite = "BLOB", .mssql = "VARBINARY(MAX)", .oracle = "BLOB", .db2 = "BLOB" }, .{ .rev_priority = 10, .sql_type = .blob }),
    rev("j", .{ .mysql = "json", .pg = "json", .sqlite = "TEXT", .mssql = "NVARCHAR(MAX)", .oracle = "CLOB", .db2 = "CLOB" }, .{ .rev_priority = 10, .sql_type = .json }),
    rev("d", .{ .mysql = "date", .pg = "date", .sqlite = "TEXT", .mssql = "DATE", .oracle = "DATE", .db2 = "DATE" }, .{ .rev_priority = 10, .sql_type = .date }),
    rev("t", .{ .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT", .mssql = "DATETIME2", .oracle = "TIMESTAMP", .db2 = "TIMESTAMP" }, .{ .rev_priority = 10, .sql_type = .datetime }),

    // ─── MySQL integer variants → reverse to "n" ───
    rev("n", .{ .mysql = "tinyint", .pg = "smallint", .sqlite = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .mysql = "mediumint", .pg = "integer", .sqlite = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),

    // ─── MySQL BLOB/TEXT variants ───
    rev("B", .{ .mysql = "tinyblob", .pg = "bytea", .sqlite = "BLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .mysql = "mediumblob", .pg = "bytea", .sqlite = "BLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .mysql = "longblob", .pg = "bytea", .sqlite = "BLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .mysql = "tinytext", .pg = "varchar(255)", .sqlite = "TEXT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("S", .{ .mysql = "mediumtext", .pg = "text", .sqlite = "TEXT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("S", .{ .mysql = "longtext", .pg = "text", .sqlite = "TEXT" }, .{ .rev_priority = 20, .confidence_base = 85 }),

    // ─── MySQL datetime → reverse to "t" ───
    rev("t", .{ .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT" }, .{ .rev_priority = 15, .confidence_base = 90 }),

    // ─── MySQL-specific → reverse to core types ───
    rev("b", .{ .mysql = "bit(1)", .pg = "boolean", .sqlite = "INTEGER" }, .{ .rev_priority = 15, .confidence_base = 90 }),

    // ─── PostgreSQL types → reverse to core types ───
    rev("n", .{ .mysql = "serial", .pg = "serial", .sqlite = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("N", .{ .mysql = "bigserial", .pg = "bigserial", .sqlite = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("i", .{ .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER", .db2 = "SMALLINT" }, .{ .rev_priority = 10, .sql_type = .smallint }),
    rev("T", .{ .mysql = "timestamp", .pg = "timestamptz", .sqlite = "TEXT", .mssql = "DATETIMEOFFSET", .oracle = "TIMESTAMP WITH TIME ZONE", .db2 = "TIMESTAMP WITH TIME ZONE" }, .{ .rev_priority = 10, .sql_type = .timestamptz }),
    rev("U", .{ .mysql = "char(36)", .pg = "uuid", .sqlite = "TEXT", .mssql = "UNIQUEIDENTIFIER", .oracle = "RAW(16)", .db2 = "CHAR(16) FOR BIT DATA" }, .{ .rev_priority = 10, .sql_type = .uuid }),
    rev("p", .{ .mysql = "int", .pg = "serial", .sqlite = "INTEGER", .db2 = "INTEGER" }, .{ .rev_priority = 10, .sql_type = .serial }),
    rev("J", .{ .mysql = "json", .pg = "jsonb", .sqlite = "TEXT" }, .{ .rev_priority = 10, .sql_type = .jsonb }),
    rev("I", .{ .mysql = "varchar(45)", .pg = "inet", .sqlite = "TEXT", .oracle = "VARCHAR2(45)", .db2 = "VARCHAR(45)" }, .{ .rev_priority = 10, .sql_type = .inet }),
    rev("m", .{ .mysql = "numeric", .pg = "numeric", .sqlite = "NUMERIC" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .mysql = "varchar", .pg = "varchar", .sqlite = "TEXT", .db2 = "VARCHAR" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("b", .{ .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("j", .{ .mysql = "json", .pg = "json", .sqlite = "TEXT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("t", .{ .mysql = "timestamp", .pg = "timestamp", .sqlite = "TEXT" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("t", .{ .mysql = "timestamp without time zone", .pg = "timestamp without time zone", .sqlite = "TEXT" }, .{ .rev_priority = 25, .confidence_base = 80 }),
    rev("t", .{ .mysql = "timestamp", .pg = "timestamp with time zone", .sqlite = "TEXT" }, .{ .rev_priority = 25, .confidence_base = 80 }),

    // ─── MSSQL-specific types ───
    rev("n", .{ .mssql = "TINYINT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .mssql = "SMALLINT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .mssql = "INT IDENTITY" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("t", .{ .mssql = "SMALLDATETIME" }, .{ .rev_priority = 20, .confidence_base = 85 }),

    // ─── Oracle-specific types ───
    rev("n", .{ .oracle = "NUMBER(5)" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .oracle = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .oracle = "SMALLINT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .oracle = "BINARY_INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .oracle = "PLS_INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("N", .{ .oracle = "NUMBER(19)" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("N", .{ .oracle = "LONG" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .oracle = "NVARCHAR2" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .oracle = "CHAR" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("S", .{ .oracle = "NCLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("T", .{ .oracle = "TIMESTAMP WITH LOCAL TIME Z" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .oracle = "LONG RAW" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .oracle = "RAW" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("j", .{ .oracle = "JSON" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("t", .{ .oracle = "DATE" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("b", .{ .oracle = "BOOLEAN" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .oracle = "REAL" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .oracle = "FLOAT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .oracle = "BINARY_FLOAT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("R", .{ .oracle = "BINARY_DOUBLE" }, .{ .rev_priority = 20, .confidence_base = 85 }),

    // ─── Db2-specific types ───
    rev("n", .{ .db2 = "SMALLINT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .db2 = "BIGINT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .db2 = "INT" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("n", .{ .db2 = "INTEGER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .db2 = "CHAR" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("s", .{ .db2 = "CHARACTER" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("S", .{ .db2 = "LONG VARCHAR" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("S", .{ .db2 = "CLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .db2 = "BLOB" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .db2 = "BINARY" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .db2 = "VARBINARY" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("B", .{ .db2 = "LONG VARCHAR FOR BIT DATA" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .db2 = "REAL" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .db2 = "DOUBLE" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("r", .{ .db2 = "DOUBLE PRECISION" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("t", .{ .db2 = "DATE" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("t", .{ .db2 = "TIMESTAMP" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("T", .{ .db2 = "TIMESTAMP WITH TIME ZONE" }, .{ .rev_priority = 10 }),
    rev("d", .{ .db2 = "DATE" }, .{ .rev_priority = 15, .confidence_base = 90 }),
    rev("b", .{ .db2 = "BOOLEAN" }, .{ .rev_priority = 10 }),
    rev("B", .{ .db2 = "BLOB" }, .{ .rev_priority = 10 }),
    rev("m", .{ .db2 = "DECIMAL" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("m", .{ .db2 = "NUMERIC" }, .{ .rev_priority = 20, .confidence_base = 85 }),
    rev("U", .{ .db2 = "CHAR(16) FOR BIT DATA" }, .{ .rev_priority = 10 }),
    rev("U", .{ .db2 = "CHARACTER(16) FOR BIT DATA" }, .{ .rev_priority = 20, .confidence_base = 85 }),

    // ─── Passthrough types (not in Rune DSL, emitted as-is) ───
    rev("uuid", .{ .mysql = "uuid", .pg = "uuid", .sqlite = "TEXT" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("real", .{ .mysql = "real", .pg = "real", .sqlite = "REAL" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("float4", .{ .mysql = "float4", .pg = "float4", .sqlite = "REAL" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("float8", .{ .mysql = "float8", .pg = "float8", .sqlite = "REAL" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("float8", .{ .mysql = "double precision", .pg = "double precision", .sqlite = "REAL" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("s", .{ .mysql = "character", .pg = "character", .sqlite = "TEXT" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    // ─── PostgreSQL-specific passthrough types ───
    rev("xml", .{ .pg = "xml" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("cidr", .{ .pg = "cidr" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("macaddr", .{ .pg = "macaddr" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    // ─── Oracle-specific passthrough types ───
    rev("NUMBER", .{ .oracle = "NUMBER" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("VARCHAR2", .{ .oracle = "VARCHAR2" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("NVARCHAR2", .{ .oracle = "NVARCHAR2" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("CLOB", .{ .oracle = "CLOB" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("NCLOB", .{ .oracle = "NCLOB" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("BLOB", .{ .oracle = "BLOB" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("RAW", .{ .oracle = "RAW" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("LONG", .{ .oracle = "LONG" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("XMLTYPE", .{ .oracle = "XMLTYPE" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("SDO_GEOMETRY", .{ .oracle = "SDO_GEOMETRY" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("SPATIAL", .{ .oracle = "MDSYS.SDO_GEOMETRY" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    // ─── Db2-specific passthrough types ───
    rev("DECFLOAT", .{ .db2 = "DECFLOAT" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("GRAPHIC", .{ .db2 = "GRAPHIC" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("VARGRAPHIC", .{ .db2 = "VARGRAPHIC" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("DBCLOB", .{ .db2 = "DBCLOB" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("BIGINT", .{ .db2 = "BIGINT" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("SMALLINT", .{ .db2 = "SMALLINT" }, .{ .rev_priority = 10, .confidence_base = 70 }),
    rev("INTEGER", .{ .db2 = "INTEGER" }, .{ .rev_priority = 10, .confidence_base = 70 }),
};
