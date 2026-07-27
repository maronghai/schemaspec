const sql_type_mod = @import("./sql_type.zig");
const SqlType = sql_type_mod.SqlType;

// ─── Reverse Mapping Data: SQL → SS ─────────────────────────
//
// All entries that reverse codegen may encounter. Includes:
//   - Core single-char entries (for SQLite which has lossy type affinity)
//   - MySQL/PG variant types (tinyint, serial, jsonb, etc.)
//   - Passthrough types (uuid, real, float4, float8)
//
// Priority ordering: lower number = preferred when multiple SQL types
// map to the same SS symbol. Checked top-to-bottom; first match wins.
//
// Canonical entries (rev_priority=10) carry a sql_type tag that links
// to the SqlType union. The consistency test in type_map.zig verifies
// that these match the forward mapping in sqlTypeName().

pub const ReverseMapping = struct {
    sym: []const u8,
    mysql: []const u8,
    pg: []const u8,
    sqlite: []const u8,
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
    .{ .sym = "n", .mysql = "int", .pg = "integer", .sqlite = "INTEGER", .rev_priority = 10, .sql_type = .int, .confidence_base = 100 },
    .{ .sym = "N", .mysql = "bigint", .pg = "bigint", .sqlite = "INTEGER", .rev_priority = 10, .sql_type = .bigint, .confidence_base = 100 },
    .{ .sym = "M", .mysql = "decimal(20, 6)", .pg = "numeric(20, 6)", .sqlite = "NUMERIC", .rev_priority = 10, .sql_type = .{ .decimal = .{ .precision = 20, .scale = 6 } }, .confidence_base = 100 },
    .{ .sym = "S", .mysql = "text", .pg = "text", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .text, .confidence_base = 100 },
    .{ .sym = "b", .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER", .rev_priority = 10, .sql_type = .boolean, .confidence_base = 100 },
    .{ .sym = "B", .mysql = "blob", .pg = "bytea", .sqlite = "BLOB", .rev_priority = 10, .sql_type = .blob, .confidence_base = 100 },
    .{ .sym = "j", .mysql = "json", .pg = "json", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .json, .confidence_base = 100 },
    .{ .sym = "d", .mysql = "date", .pg = "date", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .date, .confidence_base = 100 },
    .{ .sym = "t", .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .datetime, .confidence_base = 100 },

    // ─── MySQL integer variants → reverse to "n" ───
    .{ .sym = "n", .mysql = "tinyint", .pg = "smallint", .sqlite = "INTEGER", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "n", .mysql = "mediumint", .pg = "integer", .sqlite = "INTEGER", .rev_priority = 20, .confidence_base = 85 },

    // ─── MySQL BLOB/TEXT variants ───
    .{ .sym = "B", .mysql = "tinyblob", .pg = "bytea", .sqlite = "BLOB", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .mysql = "mediumblob", .pg = "bytea", .sqlite = "BLOB", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "B", .mysql = "longblob", .pg = "bytea", .sqlite = "BLOB", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .mysql = "tinytext", .pg = "varchar(255)", .sqlite = "TEXT", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .mysql = "mediumtext", .pg = "text", .sqlite = "TEXT", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "S", .mysql = "longtext", .pg = "text", .sqlite = "TEXT", .rev_priority = 20, .confidence_base = 85 },

    // ─── MySQL datetime → reverse to "t" ───
    .{ .sym = "t", .mysql = "datetime", .pg = "timestamp", .sqlite = "TEXT", .rev_priority = 15, .confidence_base = 90 },

    // ─── MySQL-specific → reverse to core types ───
    .{ .sym = "b", .mysql = "bit(1)", .pg = "boolean", .sqlite = "INTEGER", .rev_priority = 15, .confidence_base = 90 },

    // ─── PostgreSQL types → reverse to core types ───
    .{ .sym = "n", .mysql = "serial", .pg = "serial", .sqlite = "INTEGER", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "N", .mysql = "bigserial", .pg = "bigserial", .sqlite = "INTEGER", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "i", .mysql = "smallint", .pg = "smallint", .sqlite = "INTEGER", .rev_priority = 10, .sql_type = .smallint, .confidence_base = 100 },
    .{ .sym = "T", .mysql = "timestamp with time zone", .pg = "timestamptz", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .timestamptz, .confidence_base = 100 },
    .{ .sym = "U", .mysql = "uuid", .pg = "uuid", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .uuid, .confidence_base = 100 },
    .{ .sym = "p", .mysql = "serial", .pg = "serial", .sqlite = "INTEGER", .rev_priority = 10, .sql_type = .serial, .confidence_base = 100 },
    .{ .sym = "J", .mysql = "jsonb", .pg = "jsonb", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .jsonb, .confidence_base = 100 },
    .{ .sym = "I", .mysql = "inet", .pg = "inet", .sqlite = "TEXT", .rev_priority = 10, .sql_type = .inet, .confidence_base = 100 },
    .{ .sym = "m", .mysql = "numeric", .pg = "numeric", .sqlite = "NUMERIC", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "s", .mysql = "varchar", .pg = "varchar", .sqlite = "TEXT", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "b", .mysql = "boolean", .pg = "boolean", .sqlite = "INTEGER", .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "j", .mysql = "json", .pg = "json", .sqlite = "TEXT", .rev_priority = 20, .confidence_base = 85 },
    .{ .sym = "t", .mysql = "timestamp", .pg = "timestamp", .sqlite = "TEXT", .rev_priority = 15, .confidence_base = 90 },
    .{ .sym = "t", .mysql = "timestamp without time zone", .pg = "timestamp without time zone", .sqlite = "TEXT", .rev_priority = 25, .confidence_base = 80 },
    .{ .sym = "t", .mysql = "timestamp with time zone", .pg = "timestamp with time zone", .sqlite = "TEXT", .rev_priority = 25, .confidence_base = 80 },

    // ─── Passthrough types (not in Rune DSL, emitted as-is) ───
    .{ .sym = "uuid", .mysql = "uuid", .pg = "uuid", .sqlite = "TEXT", .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "real", .mysql = "real", .pg = "real", .sqlite = "REAL", .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float4", .mysql = "float4", .pg = "float4", .sqlite = "REAL", .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float8", .mysql = "float8", .pg = "float8", .sqlite = "REAL", .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "float8", .mysql = "double precision", .pg = "double precision", .sqlite = "REAL", .rev_priority = 10, .confidence_base = 70 },
    .{ .sym = "s", .mysql = "character", .pg = "character", .sqlite = "TEXT", .rev_priority = 10, .confidence_base = 70 },
};
