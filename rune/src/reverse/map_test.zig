const std = @import("std");
const map = @import("map.zig");

const testing = std.testing;
const reverseLookup = map.reverseLookup;
const canOmitType = map.canOmitType;
const isDatetimeSqlType = map.isDatetimeSqlType;
const isCurrentTimestamp = map.isCurrentTimestamp;
const REVERSE_MAP = map.REVERSE_MAP;

test "reverse: int maps to n" {
    const r = reverseLookup("int", "col", false, false, .mysql);
    try testing.expectEqualStrings("n", r.sym);
}

test "reverse: varchar(255) maps to s" {
    const r = reverseLookup("varchar(255)", "col", false, false, .mysql);
    try testing.expectEqualStrings("s", r.sym);
}

test "reverse: varchar(128) maps to s128" {
    const r = reverseLookup("varchar(128)", "col", false, false, .mysql);
    try testing.expectEqualStrings("s128", r.sym);
}

test "reverse: decimal(16, 2) maps to 16,2" {
    const r = reverseLookup("decimal(16, 2)", "col", false, false, .mysql);
    try testing.expectEqualStrings("16,2", r.sym);
}

test "reverse: numeric(16, 2) maps to 16,2" {
    const r = reverseLookup("numeric(16, 2)", "col", false, false, .pg);
    try testing.expectEqualStrings("16,2", r.sym);
}

test "reverse: ENUM(...) passes through" {
    const r = reverseLookup("ENUM('M', 'F')", "col", false, false, .mysql);
    try testing.expectEqualStrings("ENUM('M', 'F')", r.sym);
}

test "reverse: tinyint maps to n" {
    const r = reverseLookup("tinyint", "col", false, false, .mysql);
    try testing.expectEqualStrings("n", r.sym);
}

test "canOmitType: _id suffix with n omits" {
    try testing.expect(canOmitType("user_id", "n", false, false));
}

test "canOmitType: _at suffix with t omits" {
    try testing.expect(canOmitType("created_at", "t", false, false));
}

test "canOmitType: _on suffix with d omits" {
    try testing.expect(canOmitType("deleted_on", "d", false, false));
}

test "canOmitType: s always omits" {
    try testing.expect(canOmitType("name", "s", false, false));
}

test "canOmitType: auto_inc prevents omission" {
    try testing.expect(!canOmitType("user_id", "n", true, false));
}

test "canOmitType: non-matching suffix does not omit" {
    try testing.expect(!canOmitType("user_name", "n", false, false));
}

test "isDatetimeSqlType: datetime is datetime" {
    try testing.expect(isDatetimeSqlType("datetime"));
}

test "isDatetimeSqlType: timestamp is datetime" {
    try testing.expect(isDatetimeSqlType("timestamp"));
}

test "isDatetimeSqlType: int is not datetime" {
    try testing.expect(!isDatetimeSqlType("int"));
}

test "isCurrentTimestamp: CURRENT_TIMESTAMP" {
    try testing.expect(isCurrentTimestamp("CURRENT_TIMESTAMP"));
}

test "isCurrentTimestamp: now()" {
    try testing.expect(isCurrentTimestamp("now()"));
}

test "isCurrentTimestamp: random string" {
    try testing.expect(!isCurrentTimestamp("2024-01-01"));
}

// ─── SQLite reverse tests ──────────────────────────────────────

test "reverse sqlite: INTEGER + auto_increment maps to n" {
    const r = reverseLookup("INTEGER", "id", true, false, .sqlite);
    try testing.expectEqualStrings("n", r.sym);
    try testing.expect(!r.omit);
}

test "reverse sqlite: INTEGER + _id suffix maps to n with omit" {
    const r = reverseLookup("INTEGER", "user_id", false, false, .sqlite);
    try testing.expectEqualStrings("n", r.sym);
    try testing.expect(r.omit);
}

test "reverse sqlite: INTEGER bare maps to n" {
    const r = reverseLookup("INTEGER", "count", false, false, .sqlite);
    try testing.expectEqualStrings("n", r.sym);
}

test "reverse sqlite: lowercase integer maps to n" {
    const r = reverseLookup("integer", "status", false, false, .sqlite);
    try testing.expectEqualStrings("n", r.sym);
}

test "reverse sqlite: NUMERIC maps to m" {
    const r = reverseLookup("NUMERIC", "balance", false, false, .sqlite);
    try testing.expectEqualStrings("m", r.sym);
}

test "reverse sqlite: TEXT + _at suffix maps to t with omit" {
    const r = reverseLookup("TEXT", "created_at", false, false, .sqlite);
    try testing.expectEqualStrings("t", r.sym);
    try testing.expect(r.omit);
}

test "reverse sqlite: TEXT + _on suffix maps to d with omit" {
    const r = reverseLookup("TEXT", "birth_on", false, false, .sqlite);
    try testing.expectEqualStrings("d", r.sym);
    try testing.expect(r.omit);
}

test "reverse sqlite: TEXT + is_default_ts maps to t" {
    const r = reverseLookup("TEXT", "created_at", false, true, .sqlite);
    try testing.expectEqualStrings("t", r.sym);
    try testing.expect(!r.omit);
}

test "reverse sqlite: TEXT bare maps to s with omit" {
    const r = reverseLookup("TEXT", "name", false, false, .sqlite);
    try testing.expectEqualStrings("s", r.sym);
    try testing.expect(r.omit);
}

test "reverse sqlite: BLOB maps to B" {
    const r = reverseLookup("BLOB", "data", false, false, .sqlite);
    try testing.expectEqualStrings("B", r.sym);
}

test "reverse sqlite: INTEGER + is_ prefix maps to b" {
    const r = reverseLookup("INTEGER", "is_admin", false, false, .sqlite);
    try testing.expectEqualStrings("b", r.sym);
}

test "reverse sqlite: INTEGER + has_ prefix maps to b" {
    const r = reverseLookup("INTEGER", "has_permission", false, false, .sqlite);
    try testing.expectEqualStrings("b", r.sym);
}

test "reverse sqlite: INTEGER + can_ prefix maps to b" {
    const r = reverseLookup("INTEGER", "can_edit", false, false, .sqlite);
    try testing.expectEqualStrings("b", r.sym);
}

test "reverse sqlite: TEXT + settings maps to j" {
    const r = reverseLookup("TEXT", "settings", false, false, .sqlite);
    try testing.expectEqualStrings("j", r.sym);
}

test "reverse sqlite: TEXT + metadata maps to j" {
    const r = reverseLookup("TEXT", "metadata", false, false, .sqlite);
    try testing.expectEqualStrings("j", r.sym);
}

test "reverse sqlite: TEXT + extra_data maps to j" {
    const r = reverseLookup("TEXT", "extra_data", false, false, .sqlite);
    try testing.expectEqualStrings("j", r.sym);
}

test "reverse sqlite: TEXT + description maps to S" {
    const r = reverseLookup("TEXT", "description", false, false, .sqlite);
    try testing.expectEqualStrings("S", r.sym);
}

test "reverse sqlite: TEXT + note maps to S" {
    const r = reverseLookup("TEXT", "note", false, false, .sqlite);
    try testing.expectEqualStrings("S", r.sym);
}

test "reverse sqlite: TEXT + content maps to S" {
    const r = reverseLookup("TEXT", "content", false, false, .sqlite);
    try testing.expectEqualStrings("S", r.sym);
}

// ─── Score tests ────────────────────────────────────────────────

test "score: MySQL exact match returns 100" {
    const r = reverseLookup("int", "id", false, false, .mysql);
    try testing.expectEqual(@as(u8, 100), r.score);
}

test "score: parameterized type returns 100" {
    const r = reverseLookup("varchar(128)", "col", false, false, .mysql);
    try testing.expectEqual(@as(u8, 100), r.score);
}

test "score: SQLite INTEGER with _id suffix returns 100" {
    const r = reverseLookup("INTEGER", "user_id", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 100), r.score);
}

test "score: SQLite INTEGER with boolean column name returns 80" {
    const r = reverseLookup("INTEGER", "is_active", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 80), r.score);
}

test "score: SQLite INTEGER fallback returns 50" {
    const r = reverseLookup("INTEGER", "some_col", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 50), r.score);
}

test "score: SQLite TEXT with _at suffix returns 100" {
    const r = reverseLookup("TEXT", "created_at", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 100), r.score);
}

test "score: SQLite TEXT with json column name returns 80" {
    const r = reverseLookup("TEXT", "settings", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 80), r.score);
}

test "score: SQLite TEXT fallback returns 50" {
    const r = reverseLookup("TEXT", "some_col", false, false, .sqlite);
    try testing.expectEqual(@as(u8, 50), r.score);
}

// ─── Round-trip tests: sym → toSql → reverseLookup → sym ──────

test "round-trip: MySQL int → n" {
    const r = reverseLookup("int", "id", false, false, .mysql);
    try testing.expectEqualStrings("n", r.sym);
}

test "round-trip: MySQL bigint → N" {
    const r = reverseLookup("bigint", "id", false, false, .mysql);
    try testing.expectEqualStrings("N", r.sym);
}

test "round-trip: MySQL text → S" {
    const r = reverseLookup("text", "col", false, false, .mysql);
    try testing.expectEqualStrings("S", r.sym);
}

test "round-trip: MySQL boolean → b" {
    const r = reverseLookup("boolean", "flag", false, false, .mysql);
    try testing.expectEqualStrings("b", r.sym);
}

test "round-trip: MySQL blob → B" {
    const r = reverseLookup("blob", "data", false, false, .mysql);
    try testing.expectEqualStrings("B", r.sym);
}

test "round-trip: MySQL json → j" {
    const r = reverseLookup("json", "meta", false, false, .mysql);
    try testing.expectEqualStrings("j", r.sym);
}

test "round-trip: MySQL date → d" {
    const r = reverseLookup("date", "col", false, false, .mysql);
    try testing.expectEqualStrings("d", r.sym);
}

test "round-trip: MySQL datetime → t" {
    const r = reverseLookup("datetime", "col", false, false, .mysql);
    try testing.expectEqualStrings("t", r.sym);
}

test "round-trip: PG integer → n" {
    const r = reverseLookup("integer", "id", false, false, .pg);
    try testing.expectEqualStrings("n", r.sym);
}

test "round-trip: PG smallint → i" {
    const r = reverseLookup("smallint", "id", false, false, .pg);
    try testing.expectEqualStrings("i", r.sym);
}

test "round-trip: PG bytea → B" {
    const r = reverseLookup("bytea", "data", false, false, .pg);
    try testing.expectEqualStrings("B", r.sym);
}

test "round-trip: PG timestamptz → T" {
    const r = reverseLookup("timestamptz", "col", false, false, .pg);
    try testing.expectEqualStrings("T", r.sym);
}

test "round-trip: PG uuid → U" {
    const r = reverseLookup("uuid", "col", false, false, .pg);
    try testing.expectEqualStrings("U", r.sym);
}

test "round-trip: PG jsonb → J" {
    const r = reverseLookup("jsonb", "col", false, false, .pg);
    try testing.expectEqualStrings("J", r.sym);
}

test "round-trip: PG inet → I" {
    const r = reverseLookup("inet", "col", false, false, .pg);
    try testing.expectEqualStrings("I", r.sym);
}

test "round-trip: PG serial → p" {
    const r = reverseLookup("serial", "id", false, false, .pg);
    try testing.expectEqualStrings("p", r.sym);
}

test "round-trip: PG bigserial → N" {
    const r = reverseLookup("bigserial", "id", false, false, .pg);
    try testing.expectEqualStrings("N", r.sym);
}

// ─── Confidence score range tests ───────────────────────────

test "confidence: all REVERSE_MAP entries have valid confidence_base" {
    for (REVERSE_MAP) |m| {
        try testing.expect(m.confidence_base <= 100);
    }
}

test "confidence: canonical entries (rev_priority=10, sql_type set) have confidence_base=100" {
    for (REVERSE_MAP) |m| {
        if (m.rev_priority == 10 and m.sql_type != null) {
            try testing.expectEqual(@as(u8, 100), m.confidence_base);
        }
    }
}

test "confidence: passthrough entries have confidence_base=70" {
    for (REVERSE_MAP) |m| {
        if (m.sym.len > 1) { // passthrough types have multi-char sym
            try testing.expectEqual(@as(u8, 70), m.confidence_base);
        }
    }
}

// ─── Reverse map data integrity tests ───────────────────────

test "data: REVERSE_MAP has expected minimum size" {
    try testing.expect(REVERSE_MAP.len >= 40);
}

test "data: every entry has non-empty sym" {
    for (REVERSE_MAP) |m| {
        try testing.expect(m.sym.len > 0);
    }
}

test "data: every entry has at least one non-empty dialect" {
    for (REVERSE_MAP) |m| {
        const has_any = m.types.mysql.len > 0 or m.types.pg.len > 0 or
            m.types.sqlite.len > 0 or m.types.mssql.len > 0 or m.types.oracle.len > 0 or m.types.db2.len > 0;
        try testing.expect(has_any);
    }
}

test "data: canonical entries (rev_priority=10, sql_type set) have sql_type" {
    for (REVERSE_MAP) |m| {
        if (m.rev_priority == 10 and m.sql_type != null) {
            try testing.expect(m.sql_type != null);
        }
    }
}

// ─── Buffer overflow guard tests ────────────────────────────────

test "reverse: varchar with long N falls back to raw" {
    const r = reverseLookup("varchar(9999999999999999)", "col", false, false, .mysql);
    try testing.expectEqualStrings("varchar(9999999999999999)", r.sym);
}

test "reverse: character varying with long N falls back to raw" {
    const r = reverseLookup("character varying(9999999999999999)", "col", false, false, .pg);
    try testing.expectEqualStrings("character varying(9999999999999999)", r.sym);
}

test "reverse: decimal with long P,S falls back to raw" {
    const r = reverseLookup("decimal(99999999999999999,99999999999999999)", "col", false, false, .mysql);
    try testing.expectEqualStrings("decimal(99999999999999999,99999999999999999)", r.sym);
}

test "reverse: numeric with long P,S falls back to raw" {
    const r = reverseLookup("numeric(99999999999999999,99999999999999999)", "col", false, false, .pg);
    try testing.expectEqualStrings("numeric(99999999999999999,99999999999999999)", r.sym);
}

// ─── Oracle-specific reverse tests ──────────────────────────────

test "reverse oracle: NUMBER(10) maps to n" {
    const r = reverseLookup("NUMBER(10)", "id", false, false, .oracle);
    try testing.expectEqualStrings("n", r.sym);
}

test "reverse oracle: NUMBER(19) maps to N" {
    const r = reverseLookup("NUMBER(19)", "id", false, false, .oracle);
    try testing.expectEqualStrings("N", r.sym);
}

test "reverse oracle: NUMBER(10,2) maps to 10,2" {
    const r = reverseLookup("NUMBER(10,2)", "amount", false, false, .oracle);
    try testing.expectEqualStrings("10,2", r.sym);
}

test "reverse oracle: VARCHAR2(100) maps to s100" {
    const r = reverseLookup("VARCHAR2(100)", "name", false, false, .oracle);
    try testing.expectEqualStrings("s100", r.sym);
}

test "reverse oracle: NVARCHAR2(50) maps to s50" {
    const r = reverseLookup("NVARCHAR2(50)", "name", false, false, .oracle);
    try testing.expectEqualStrings("s50", r.sym);
}

test "reverse oracle: CLOB maps to S" {
    const r = reverseLookup("CLOB", "data", false, false, .oracle);
    try testing.expectEqualStrings("S", r.sym);
}

test "reverse oracle: BLOB maps to B" {
    const r = reverseLookup("BLOB", "data", false, false, .oracle);
    try testing.expectEqualStrings("B", r.sym);
}

test "reverse oracle: DATE maps to d" {
    const r = reverseLookup("DATE", "created", false, false, .oracle);
    try testing.expectEqualStrings("d", r.sym);
}

test "reverse oracle: TIMESTAMP maps to t" {
    const r = reverseLookup("TIMESTAMP", "created", false, false, .oracle);
    try testing.expectEqualStrings("t", r.sym);
}

test "reverse oracle: TIMESTAMP WITH TIME ZONE maps to T" {
    const r = reverseLookup("TIMESTAMP WITH TIME ZONE", "created", false, false, .oracle);
    try testing.expectEqualStrings("T", r.sym);
}

test "reverse oracle: RAW(16) maps to U (uuid)" {
    const r = reverseLookup("RAW(16)", "uuid", false, false, .oracle);
    try testing.expectEqualStrings("U", r.sym);
}

test "reverse oracle: NUMBER maps to NUMBER passthrough" {
    const r = reverseLookup("NUMBER", "col", false, false, .oracle);
    try testing.expectEqualStrings("NUMBER", r.sym);
}

test "reverse oracle: VARCHAR2 maps to VARCHAR2 passthrough" {
    const r = reverseLookup("VARCHAR2", "col", false, false, .oracle);
    try testing.expectEqualStrings("VARCHAR2", r.sym);
}

// ─── Db2-specific reverse tests ─────────────────────────────────

test "reverse db2: INTEGER maps to n" {
    const r = reverseLookup("INTEGER", "id", false, false, .db2);
    try testing.expectEqualStrings("n", r.sym);
}

test "reverse db2: SMALLINT maps to i" {
    const r = reverseLookup("SMALLINT", "id", false, false, .db2);
    try testing.expectEqualStrings("i", r.sym);
}

test "reverse db2: BIGINT maps to N" {
    const r = reverseLookup("BIGINT", "id", false, false, .db2);
    try testing.expectEqualStrings("N", r.sym);
}

test "reverse db2: DECIMAL(10,2) maps to 10,2" {
    const r = reverseLookup("DECIMAL(10,2)", "amount", false, false, .db2);
    try testing.expectEqualStrings("10,2", r.sym);
}

test "reverse db2: VARCHAR(100) maps to s100" {
    const r = reverseLookup("VARCHAR(100)", "name", false, false, .db2);
    try testing.expectEqualStrings("s100", r.sym);
}

test "reverse db2: CLOB maps to S" {
    const r = reverseLookup("CLOB", "data", false, false, .db2);
    try testing.expectEqualStrings("S", r.sym);
}

test "reverse db2: BLOB maps to B" {
    const r = reverseLookup("BLOB", "data", false, false, .db2);
    try testing.expectEqualStrings("B", r.sym);
}

test "reverse db2: DATE maps to d" {
    const r = reverseLookup("DATE", "created", false, false, .db2);
    try testing.expectEqualStrings("d", r.sym);
}

test "reverse db2: TIMESTAMP maps to t" {
    const r = reverseLookup("TIMESTAMP", "created", false, false, .db2);
    try testing.expectEqualStrings("t", r.sym);
}

test "reverse db2: TIMESTAMP WITH TIME ZONE maps to T" {
    const r = reverseLookup("TIMESTAMP WITH TIME ZONE", "created", false, false, .db2);
    try testing.expectEqualStrings("T", r.sym);
}

test "reverse db2: BOOLEAN maps to b" {
    const r = reverseLookup("BOOLEAN", "flag", false, false, .db2);
    try testing.expectEqualStrings("b", r.sym);
}

test "reverse db2: REAL maps to r" {
    const r = reverseLookup("REAL", "col", false, false, .db2);
    try testing.expectEqualStrings("r", r.sym);
}

test "reverse db2: DOUBLE PRECISION maps to r" {
    const r = reverseLookup("DOUBLE PRECISION", "col", false, false, .db2);
    try testing.expectEqualStrings("r", r.sym);
}

test "reverse db2: CHAR(16) FOR BIT DATA maps to U" {
    const r = reverseLookup("CHAR(16) FOR BIT DATA", "uuid", false, false, .db2);
    try testing.expectEqualStrings("U", r.sym);
}
