const sql_type_mod = @import("./sql_type.zig");
const SqlType = sql_type_mod.SqlType;

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
// Dialect type mapping uses DialectTypeMap — a struct with one field
// per dialect. To add a new dialect, add a field here and in the
// DialectTypeMap struct. Existing entries default to "" (no match).

pub const DialectTypeMap = struct {
    mysql: []const u8 = "",
    pg: []const u8 = "",
    sqlite: []const u8 = "",
    mssql: []const u8 = "",
    oracle: []const u8 = "",
    db2: []const u8 = "",
};

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
};

pub const REVERSE_MAP = [_]ReverseMapping{
    // ─── Core single-char symbols (used by SQLite reverse) ───
    .{ .sym = "n", .types = .{ .mysql = "int", .pg = "integer", .sqlite = "INTEGER", .mssql = "INT", .oracle = "NUMBER(10)", .db2 = "INTEGER" }, .rev_priority = 10, .sql_type = .int, .confidence_base = 100 },
    .{ .sym = "N", .types = .{ .mysql = "bigint", .pg = "bigint", .sqlite = "INTEGER", .mssql = "BIGINT", .oracle = "NUMBER(19)", .db2 = "BIGINT" }, .rev_priority = 10, .sql_type = .bigint, .confidence_base = 100 },
    .{ .sym = "M", .types = .{ .mysql = "decimal(20, 6)", .pg = "numeric(20, 6)", .sqlite = "NUMERIC", .mssql = "NUMERIC(20, 6)", .oracle = "NUMBER(20, 6)", .db2 = "DECIMAL(20, 6)" }, .rev_priority = 10, .sql_type = .{ .decimal = .{ .precision = 20, .scale = 6 } }, .confidence_base = 100 },
    .{ .sym = "S", .types = .{ .mysql = "text", .pg = "text", .sqlite = "TEXT", .mssql = "NVARCHAR(MAX)", .oracle = "CLOB", .db2 = "CLOB" }, .rev_priority = 10, .sql_type = .text, .confidence_base = 100 },
    .{ .sym = "b", .types = .{ .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER", .mssql = "BIT", .oracle = "NUMBER(1)", .db2 = "BOOLEAN" }, .rev_priority = 10, .sql_type = .boolean, .confidence_base = 100 },
    .{ .sym = "B", .types = .{ .mysql = "blob", .pg = "bytea", .sqlite = "BLOB", .mssql = "VARBINARY(MAX)", .oracle = "BLOB", .db2 = "BLOB" }, .rev_priority = 10, .sql_type = .blob, .confidence_base = 100 },
    .{ .sym = "j", .types = .{ .mysql = "json", .pg = "json", .sqlite = "TEXT", .mssql = "NVARCHAR(MAX)", .oracle = "CLOB", .db2 = "CLOB" }, .rev_priority = 10, .sql_type = .json, .confidence_base = 100 },
    .{ .sym = "d", .types = .{ .mysql = "date", .pg = "date", .sqlite = "TEXT", .mssql = "DATE", .oracle = "DATE", .db2 = "DATE" }, .rev_priority = 10, .sql_type = .date, .confidence_base = 100 },
    .{ .sym = "t", .types = .{ .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT", .mssql = "DATETIME2", .oracle = "TIMESTAMP", .db2 = "TIMESTAMP" }, .rev_priority = 10, .sql_type = .datetime, .confidence_base = 100 },

    // ─── MySQL integer variants → reverse to "n" ───
    .{ .sym = "n", .types = .{ .mysql = "tinyint", .pg = "smallint", .sqlite = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .mysql = "mediumint", .pg = "integer", .sqlite = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },

    // ─── MySQL BLOB/TEXT variants ───
    .{ .sym = "B", .types = .{ .mysql = "tinyblob", .pg = "bytea", .sqlite = "BLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .mysql = "mediumblob", .pg = "bytea", .sqlite = "BLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .mysql = "longblob", .pg = "bytea", .sqlite = "BLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .mysql = "tinytext", .pg = "varchar(255)", .sqlite = "TEXT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .types = .{ .mysql = "mediumtext", .pg = "text", .sqlite = "TEXT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .types = .{ .mysql = "longtext", .pg = "text", .sqlite = "TEXT" }, .rev_priority = 20, .confidence_base = 85 },

    // ─── MySQL datetime → reverse to "t" ───
    .{ .sym = "t", .types = .{ .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT" }, .rev_priority = 15, .confidence_base = 90 },

    // ─── MySQL-specific → reverse to core types ───
    .{ .sym = "b", .types = .{ .mysql = "bit(1)", .pg = "boolean", .sqlite = "INTEGER" }, .rev_priority = 15, .confidence_base = 90 },

    // ─── PostgreSQL types → reverse to core types ───
    .{ .sym = "n", .types = .{ .mysql = "serial", .pg = "serial", .sqlite = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "N", .types = .{ .mysql = "bigserial", .pg = "bigserial", .sqlite = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "i", .types = .{ .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER", .db2 = "SMALLINT" }, .rev_priority = 10, .sql_type = .smallint, .confidence_base = 100 },
    .{ .sym = "T", .types = .{ .mysql = "timestamp", .pg = "timestamptz", .sqlite = "TEXT", .mssql = "DATETIMEOFFSET", .oracle = "TIMESTAMP WITH TIME ZONE", .db2 = "TIMESTAMP WITH TIME ZONE" }, .rev_priority = 10, .sql_type = .timestamptz, .confidence_base = 100 },
    .{ .sym = "U", .types = .{ .mysql = "char(36)", .pg = "uuid", .sqlite = "TEXT", .mssql = "UNIQUEIDENTIFIER", .oracle = "RAW(16)", .db2 = "CHAR(16) FOR BIT DATA" }, .rev_priority = 10, .sql_type = .uuid, .confidence_base = 100 },
    .{ .sym = "p", .types = .{ .mysql = "int", .pg = "serial", .sqlite = "INTEGER", .db2 = "INTEGER" }, .rev_priority = 10, .sql_type = .serial, .confidence_base = 100 },
    .{ .sym = "J", .types = .{ .mysql = "json", .pg = "jsonb", .sqlite = "TEXT" }, .rev_priority = 10, .sql_type = .jsonb, .confidence_base = 100 },
    .{ .sym = "I", .types = .{ .mysql = "varchar(45)", .pg = "inet", .sqlite = "TEXT", .oracle = "VARCHAR2(45)", .db2 = "VARCHAR(45)" }, .rev_priority = 10, .sql_type = .inet, .confidence_base = 100 },
    .{ .sym = "m", .types = .{ .mysql = "numeric", .pg = "numeric", .sqlite = "NUMERIC" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .mysql = "varchar", .pg = "varchar", .sqlite = "TEXT", .db2 = "VARCHAR" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "b", .types = .{ .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "j", .types = .{ .mysql = "json", .pg = "json", .sqlite = "TEXT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "t", .types = .{ .mysql = "timestamp", .pg = "timestamp", .sqlite = "TEXT" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "t", .types = .{ .mysql = "timestamp without time zone", .pg = "timestamp without time zone", .sqlite = "TEXT" }, .rev_priority = 25, .confidence_base = 80 },
    .{ .sym = "t", .types = .{ .mysql = "timestamp", .pg = "timestamp with time zone", .sqlite = "TEXT" }, .rev_priority = 25, .confidence_base = 80 },

    // ─── MSSQL-specific types ───
    .{ .sym = "n", .types = .{ .mssql = "TINYINT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .mssql = "SMALLINT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .mssql = "INT IDENTITY" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "t", .types = .{ .mssql = "SMALLDATETIME" }, .rev_priority = 20, .confidence_base = 85 },

    // ─── Oracle-specific types ───
    .{ .sym = "n", .types = .{ .oracle = "NUMBER(5)" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .oracle = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .oracle = "SMALLINT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .oracle = "BINARY_INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .oracle = "PLS_INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "N", .types = .{ .oracle = "NUMBER(19)" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "N", .types = .{ .oracle = "LONG" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .oracle = "NVARCHAR2" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .oracle = "CHAR" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .types = .{ .oracle = "NCLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "T", .types = .{ .oracle = "TIMESTAMP WITH LOCAL TIME Z" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .oracle = "LONG RAW" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .oracle = "RAW" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "j", .types = .{ .oracle = "JSON" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "t", .types = .{ .oracle = "DATE" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "b", .types = .{ .oracle = "BOOLEAN" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .oracle = "REAL" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .oracle = "FLOAT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .oracle = "BINARY_FLOAT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "R", .types = .{ .oracle = "BINARY_DOUBLE" }, .rev_priority = 20, .confidence_base = 85 },

    // ─── Db2-specific types ───
    .{ .sym = "n", .types = .{ .db2 = "SMALLINT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .db2 = "BIGINT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .db2 = "INT" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .types = .{ .db2 = "INTEGER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .db2 = "CHAR" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .types = .{ .db2 = "CHARACTER" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .types = .{ .db2 = "LONG VARCHAR" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .types = .{ .db2 = "CLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .db2 = "BLOB" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .db2 = "BINARY" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .db2 = "VARBINARY" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .types = .{ .db2 = "LONG VARCHAR FOR BIT DATA" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .db2 = "REAL" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .db2 = "DOUBLE" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "r", .types = .{ .db2 = "DOUBLE PRECISION" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "t", .types = .{ .db2 = "DATE" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "t", .types = .{ .db2 = "TIMESTAMP" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "T", .types = .{ .db2 = "TIMESTAMP WITH TIME ZONE" }, .rev_priority = 10, .confidence_base = 100 },
    .{ .sym = "d", .types = .{ .db2 = "DATE" }, .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "b", .types = .{ .db2 = "BOOLEAN" }, .rev_priority = 10, .confidence_base = 100 },
    .{ .sym = "B", .types = .{ .db2 = "BLOB" }, .rev_priority = 10, .confidence_base = 100 },
    .{ .sym = "m", .types = .{ .db2 = "DECIMAL" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "m", .types = .{ .db2 = "NUMERIC" }, .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "U", .types = .{ .db2 = "CHAR(16) FOR BIT DATA" }, .rev_priority = 10, .confidence_base = 100 },
    .{ .sym = "U", .types = .{ .db2 = "CHARACTER(16) FOR BIT DATA" }, .rev_priority = 20, .confidence_base = 85 },

    // ─── Passthrough types (not in Rune DSL, emitted as-is) ───
    .{ .sym = "uuid", .types = .{ .mysql = "uuid", .pg = "uuid", .sqlite = "TEXT" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "real", .types = .{ .mysql = "real", .pg = "real", .sqlite = "REAL" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float4", .types = .{ .mysql = "float4", .pg = "float4", .sqlite = "REAL" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float8", .types = .{ .mysql = "float8", .pg = "float8", .sqlite = "REAL" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float8", .types = .{ .mysql = "double precision", .pg = "double precision", .sqlite = "REAL" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "s", .types = .{ .mysql = "character", .pg = "character", .sqlite = "TEXT" }, .rev_priority = 10, .confidence_base = 70 },
    // ─── PostgreSQL-specific passthrough types ───
    .{ .sym = "xml", .types = .{ .pg = "xml" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "cidr", .types = .{ .pg = "cidr" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "macaddr", .types = .{ .pg = "macaddr" }, .rev_priority = 10, .confidence_base = 70 },
    // ─── Oracle-specific passthrough types ───
    .{ .sym = "NUMBER", .types = .{ .oracle = "NUMBER" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "VARCHAR2", .types = .{ .oracle = "VARCHAR2" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "NVARCHAR2", .types = .{ .oracle = "NVARCHAR2" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "CLOB", .types = .{ .oracle = "CLOB" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "NCLOB", .types = .{ .oracle = "NCLOB" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "BLOB", .types = .{ .oracle = "BLOB" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "RAW", .types = .{ .oracle = "RAW" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "LONG", .types = .{ .oracle = "LONG" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "XMLTYPE", .types = .{ .oracle = "XMLTYPE" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "SDO_GEOMETRY", .types = .{ .oracle = "SDO_GEOMETRY" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "SPATIAL", .types = .{ .oracle = "MDSYS.SDO_GEOMETRY" }, .rev_priority = 10, .confidence_base = 70 },
    // ─── Db2-specific passthrough types ───
    .{ .sym = "DECFLOAT", .types = .{ .db2 = "DECFLOAT" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "GRAPHIC", .types = .{ .db2 = "GRAPHIC" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "VARGRAPHIC", .types = .{ .db2 = "VARGRAPHIC" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "DBCLOB", .types = .{ .db2 = "DBCLOB" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "BIGINT", .types = .{ .db2 = "BIGINT" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "SMALLINT", .types = .{ .db2 = "SMALLINT" }, .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "INTEGER", .types = .{ .db2 = "INTEGER" }, .rev_priority = 10, .confidence_base = 70 },
};
