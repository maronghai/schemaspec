const std = @import("std");
const hints = @import("sqlite_hints.zig");

const testing = std.testing;

test "hints: boolean column names" {
    try testing.expect(hints.isBooleanColumnName("is_active"));
    try testing.expect(hints.isBooleanColumnName("has_data"));
    try testing.expect(hints.isBooleanColumnName("can_edit"));
    try testing.expect(hints.isBooleanColumnName("should_notify"));
    try testing.expect(hints.isBooleanColumnName("was_deleted"));
    try testing.expect(hints.isBooleanColumnName("did_migrate"));
    try testing.expect(hints.isBooleanColumnName("enabled"));
    try testing.expect(hints.isBooleanColumnName("active"));
    try testing.expect(hints.isBooleanColumnName("deleted"));
    try testing.expect(!hints.isBooleanColumnName("name"));
    try testing.expect(!hints.isBooleanColumnName("description"));
}

test "hints: json column names" {
    try testing.expect(hints.isJsonColumnName("settings"));
    try testing.expect(hints.isJsonColumnName("data"));
    try testing.expect(hints.isJsonColumnName("metadata"));
    try testing.expect(hints.isJsonColumnName("config_json"));
    try testing.expect(hints.isJsonColumnName("user_settings"));
    try testing.expect(hints.isJsonColumnName("extra_options"));
    try testing.expect(!hints.isJsonColumnName("name"));
    try testing.expect(!hints.isJsonColumnName("is_active"));
}

test "hints: text column names" {
    try testing.expect(hints.isTextColumnName("description"));
    try testing.expect(hints.isTextColumnName("content"));
    try testing.expect(hints.isTextColumnName("bio"));
    try testing.expect(hints.isTextColumnName("long_text"));
    try testing.expect(hints.isTextColumnName("body_content"));
    try testing.expect(!hints.isTextColumnName("name"));
    try testing.expect(!hints.isTextColumnName("is_active"));
}

test "hints: lookupHint returns correct type" {
    try testing.expectEqual(hints.SqlHintType.boolean, hints.lookupHint("is_active").?);
    try testing.expectEqual(hints.SqlHintType.json, hints.lookupHint("settings").?);
    try testing.expectEqual(hints.SqlHintType.text, hints.lookupHint("description").?);
    try testing.expect(hints.lookupHint("name") == null);
}

test "hints: datetime and timestamp" {
    try testing.expect(hints.isDatetimeSqlType("datetime"));
    try testing.expect(hints.isDatetimeSqlType("timestamp"));
    try testing.expect(hints.isDatetimeSqlType("timestamp without time zone"));
    try testing.expect(hints.isDatetimeSqlType(" timestamp "));
    try testing.expect(!hints.isDatetimeSqlType("date"));
    try testing.expect(!hints.isDatetimeSqlType("text"));
}

test "hints: current timestamp" {
    try testing.expect(hints.isCurrentTimestamp("CURRENT_TIMESTAMP"));
    try testing.expect(hints.isCurrentTimestamp("now()"));
    try testing.expect(!hints.isCurrentTimestamp("2024-01-01"));
    try testing.expect(!hints.isCurrentTimestamp("NULL"));
}

test "scoreColumnName: exact match scores higher than prefix" {
    const exact = hints.scoreColumnName("is_active").?;
    try testing.expectEqual(hints.SqlHintType.boolean, exact.hint);
    try testing.expect(exact.score >= 90);

    const prefix = hints.scoreColumnName("is_verified").?;
    try testing.expectEqual(hints.SqlHintType.boolean, prefix.hint);
    try testing.expect(prefix.score >= 85);
    try testing.expect(prefix.score < exact.score);
}

test "scoreColumnName: unknown column returns null" {
    try testing.expect(hints.scoreColumnName("some_random_col") == null);
}
