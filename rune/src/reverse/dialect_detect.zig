const std = @import("std");
const codegen = @import("../codegen/codegen.zig");

// ─── SQL Dialect Detection ─────────────────────────────────────
//
// Auto-detects SQL dialect from content patterns using weighted scoring.
// Each pattern match adds weight to the corresponding dialect score.
// Highest score wins; ties default to MySQL.
//
// Supports: MySQL, PostgreSQL, SQLite, MSSQL, Oracle, Db2.

/// Auto-detect SQL dialect from content patterns using weighted scoring.
pub fn detectSqlDialect(sql: []const u8) codegen.Dialect {
    var scores = [6]u8{ 0, 0, 0, 0, 0, 0 }; // mysql, pg, sqlite, mssql, oracle, db2

    // MySQL-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "ENGINE=") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "CHARACTER SET") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "DEFAULT CHARSET") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "AUTO_INCREMENT") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "UNSIGNED") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "FULLTEXT INDEX") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "COMMENT '") != null) scores[0] += 1;
    if (std.mem.indexOf(u8, sql, "ROW_FORMAT=") != null) scores[0] += 3;
    if (std.mem.indexOf(u8, sql, "COLLATE=") != null) scores[0] += 1;
    if (std.mem.indexOf(u8, sql, "UNIQUE KEY") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "KEY `") != null) scores[0] += 2;
    if (std.mem.indexOf(u8, sql, "ON UPDATE CURRENT_TIMESTAMP") != null) scores[0] += 1;

    // PostgreSQL-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS IDENTITY") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "COMMENT ON") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE EXTENSION") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "ENCODING=") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE TYPE") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "IF NOT EXISTS\n  (") != null) scores[1] += 1; // PG style serial
    if (std.mem.indexOf(u8, sql, "SERIAL") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "BIGSERIAL") != null) scores[1] += 3;
    if (std.mem.indexOf(u8, sql, "bytea") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "boolean") != null) scores[1] += 1;
    if (std.mem.indexOf(u8, sql, "jsonb") != null) scores[1] += 2;
    if (std.mem.indexOf(u8, sql, "timestamptz") != null) scores[1] += 3;

    // SQLite-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "AUTOINCREMENT") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "INTEGER PRIMARY KEY") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "WITHOUT ROWID") != null) scores[2] += 3;
    if (std.mem.indexOf(u8, sql, "STRICT") != null) scores[2] += 2;
    if (std.mem.indexOf(u8, sql, "CREATE TABLE \"") != null) scores[2] += 1;
    if (std.mem.indexOf(u8, sql, "ON CONFLICT") != null) scores[2] += 1;

    // MSSQL-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "IDENTITY(1,1)") != null) scores[3] += 3;
    if (std.mem.indexOf(u8, sql, "IDENTITY(1, 1)") != null) scores[3] += 3;
    if (std.mem.indexOf(u8, sql, "NVARCHAR") != null) scores[3] += 2;
    if (std.mem.indexOf(u8, sql, "[dbo]") != null) scores[3] += 3;
    if (std.mem.indexOf(u8, sql, "GO\n") != null) scores[3] += 2;
    if (std.mem.indexOf(u8, sql, "BIT") != null) scores[3] += 1;
    if (std.mem.indexOf(u8, sql, "DATETIME2") != null) scores[3] += 3;
    if (std.mem.indexOf(u8, sql, "NTEXT") != null) scores[3] += 3;
    if (std.mem.indexOf(u8, sql, "VARCHAR(MAX)") != null) scores[3] += 2;
    if (std.mem.indexOf(u8, sql, "VARBINARY(MAX)") != null) scores[3] += 3;

    // Oracle-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "VARCHAR2") != null) scores[4] += 3;
    if (std.mem.indexOf(u8, sql, "NUMBER(") != null) scores[4] += 2;
    if (std.mem.indexOf(u8, sql, "SYSDATE") != null) scores[4] += 3;
    if (std.mem.indexOf(u8, sql, "CREATE SEQUENCE") != null) scores[4] += 3;
    if (std.mem.indexOf(u8, sql, "CREATE TRIGGER") != null) scores[4] += 2;
    if (std.mem.indexOf(u8, sql, "CLOB") != null) scores[4] += 2;
    if (std.mem.indexOf(u8, sql, "BLOB") != null) scores[4] += 1;
    if (std.mem.indexOf(u8, sql, "NCLOB") != null) scores[4] += 3;
    if (std.mem.indexOf(u8, sql, "NVARCHAR2") != null) scores[4] += 3;
    if (std.mem.indexOf(u8, sql, "ENABLE") != null) scores[4] += 1;

    // Db2-specific patterns (high confidence)
    if (std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS IDENTITY") != null) scores[5] += 3;
    if (std.mem.indexOf(u8, sql, "DECFLOAT") != null) scores[5] += 3;
    if (std.mem.indexOf(u8, sql, "GRAPHIC") != null) scores[5] += 3;
    if (std.mem.indexOf(u8, sql, "VARGRAPHIC") != null) scores[5] += 3;
    if (std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS (") != null) scores[5] += 3;
    if (std.mem.indexOf(u8, sql, "SMALLINT") != null) scores[5] += 1;
    if (std.mem.indexOf(u8, sql, "BIGINT") != null) scores[5] += 1;
    if (std.mem.indexOf(u8, sql, "DATALINKS") != null) scores[5] += 3;

    // Determine winner (ties → MySQL)
    var best: usize = 0;
    for (scores, 0..) |s, i| {
        if (s > scores[best]) best = i;
    }

    return switch (best) {
        1 => .pg,
        2 => .sqlite,
        3 => .mssql,
        4 => .oracle,
        5 => .db2,
        else => .mysql,
    };
}
