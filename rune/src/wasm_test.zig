const std = @import("std");
const common = @import("wasm/common.zig");
const testing = std.testing;

// ─── classifyError Tests ──────────────────────────────────────

test "classifyError: syntax errors" {
    try testing.expectEqual(@as(i32, 1), common.classifyError("SyntaxError"));
    try testing.expectEqual(@as(i32, 1), common.classifyError("ParseError"));
    try testing.expectEqual(@as(i32, 1), common.classifyError("Syntax error in line 5"));
    try testing.expectEqual(@as(i32, 1), common.classifyError("Parse failed: unexpected token"));
}

test "classifyError: type errors" {
    try testing.expectEqual(@as(i32, 2), common.classifyError("TypeError"));
    try testing.expectEqual(@as(i32, 2), common.classifyError("Type mismatch: expected int"));
    try testing.expectEqual(@as(i32, 2), common.classifyError("Unknown Type: xyz"));
}

test "classifyError: FK errors" {
    try testing.expectEqual(@as(i32, 3), common.classifyError("ForeignKeyError"));
    try testing.expectEqual(@as(i32, 3), common.classifyError("Fk constraint violation"));
    try testing.expectEqual(@as(i32, 3), common.classifyError("Foreign key not found"));
}

test "classifyError: semantic errors" {
    try testing.expectEqual(@as(i32, 4), common.classifyError("SemanticError"));
    try testing.expectEqual(@as(i32, 4), common.classifyError("DiagnosticError"));
    try testing.expectEqual(@as(i32, 4), common.classifyError("Semantic analysis failed"));
    try testing.expectEqual(@as(i32, 4), common.classifyError("Diagnostic: warning"));
}

test "classifyError: unknown errors" {
    try testing.expectEqual(@as(i32, 5), common.classifyError("unknown error"));
    try testing.expectEqual(@as(i32, 5), common.classifyError(""));
    try testing.expectEqual(@as(i32, 5), common.classifyError("runtime error"));
    try testing.expectEqual(@as(i32, 5), common.classifyError("connection refused"));
}

test "classifyError: case sensitivity" {
    // classifyError is case-sensitive — keywords must match exact case
    try testing.expectEqual(@as(i32, 1), common.classifyError("Syntax"));
    try testing.expectEqual(@as(i32, 5), common.classifyError("syntax")); // lowercase 's' doesn't match
}

// ─── storeError / clearError Tests ────────────────────────────

test "storeError: stores error message" {
    common.clearError();
    try testing.expect(common.last_error == null);
    try testing.expectEqual(@as(i32, 0), common.last_error_code);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    common.storeError(alloc, "SyntaxError: unexpected token");
    try testing.expect(common.last_error != null);
    try testing.expectEqual(@as(i32, 1), common.last_error_code); // syntax = 1
}

test "storeError: classifies error code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    common.storeError(alloc, "TypeError: mismatch");
    try testing.expectEqual(@as(i32, 2), common.last_error_code);

    common.storeError(alloc, "ForeignKeyError");
    try testing.expectEqual(@as(i32, 3), common.last_error_code);

    common.storeError(alloc, "SemanticError");
    try testing.expectEqual(@as(i32, 4), common.last_error_code);

    common.storeError(alloc, "unknown");
    try testing.expectEqual(@as(i32, 5), common.last_error_code);
}

test "clearError: resets error state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    common.storeError(alloc, "SyntaxError");
    try testing.expect(common.last_error != null);
    try testing.expectEqual(@as(i32, 1), common.last_error_code);

    common.clearError();
    try testing.expect(common.last_error == null);
    try testing.expectEqual(@as(i32, 0), common.last_error_code);
}

// ─── containsSubstring Tests ──────────────────────────────────

test "containsSubstring: found" {
    try testing.expect(common.containsSubstring("hello world", "world"));
    try testing.expect(common.containsSubstring("hello world", "hello"));
    try testing.expect(common.containsSubstring("hello world", "lo wo"));
    try testing.expect(common.containsSubstring("abc", "abc"));
}

test "containsSubstring: not found" {
    try testing.expect(!common.containsSubstring("hello world", "xyz"));
    try testing.expect(!common.containsSubstring("hello world", "Hello")); // case-sensitive
    try testing.expect(!common.containsSubstring("abc", "abcd"));
}

test "containsSubstring: edge cases" {
    try testing.expect(common.containsSubstring("abc", "")); // empty needle always matches
    try testing.expect(!common.containsSubstring("", "a")); // empty haystack
    try testing.expect(common.containsSubstring("", "")); // both empty
}

// ─── parseOption Tests ────────────────────────────────────────

test "parseOption: single key-value" {
    const result = common.parseOption("dialect=pg", "dialect");
    try testing.expect(result != null);
    try testing.expectEqualStrings("pg", result.?);
}

test "parseOption: multiple key-values" {
    const result = common.parseOption("dialect=pg format=json", "format");
    try testing.expect(result != null);
    try testing.expectEqualStrings("json", result.?);
}

test "parseOption: key not found" {
    const result = common.parseOption("dialect=pg format=json", "target");
    try testing.expect(result == null);
}

test "parseOption: empty options" {
    const result = common.parseOption("", "dialect");
    try testing.expect(result == null);
}

test "parseOption: value contains equals" {
    // Edge case: value part contains '=' character
    const result = common.parseOption("key=value=extra", "key");
    try testing.expect(result != null);
    try testing.expectEqualStrings("value=extra", result.?);
}

test "parseOption: empty value" {
    const result = common.parseOption("dialect=", "dialect");
    try testing.expect(result != null);
    try testing.expectEqualStrings("", result.?);
}

test "parseOption: first key matches" {
    const result = common.parseOption("dialect=pg format=json", "dialect");
    try testing.expect(result != null);
    try testing.expectEqualStrings("pg", result.?);
}

// ─── parseDialectOption Tests ─────────────────────────────────

test "parseDialectOption: valid dialects" {
    try testing.expectEqual(.pg, common.parseDialectOption("dialect=pg"));
    try testing.expectEqual(.mysql, common.parseDialectOption("dialect=mysql"));
    try testing.expectEqual(.sqlite, common.parseDialectOption("dialect=sqlite"));
    try testing.expectEqual(.mssql, common.parseDialectOption("dialect=mssql"));
    try testing.expectEqual(.oracle, common.parseDialectOption("dialect=oracle"));
    try testing.expectEqual(.db2, common.parseDialectOption("dialect=db2"));
}

test "parseDialectOption: default to mysql" {
    try testing.expectEqual(.mysql, common.parseDialectOption(""));
    try testing.expectEqual(.mysql, common.parseDialectOption("format=json"));
    try testing.expectEqual(.mysql, common.parseDialectOption("dialect=invalid"));
}

test "parseDialectOption: dialect with other options" {
    try testing.expectEqual(.pg, common.parseDialectOption("dialect=pg format=json"));
}

// ─── parseDiffFormatOption Tests ──────────────────────────────

test "parseDiffFormatOption: valid formats" {
    try testing.expectEqual(.text, common.parseDiffFormatOption("format=text"));
    try testing.expectEqual(.json, common.parseDiffFormatOption("format=json"));
    try testing.expectEqual(.sarif, common.parseDiffFormatOption("format=sarif"));
    try testing.expectEqual(.markdown, common.parseDiffFormatOption("format=markdown"));
}

test "parseDiffFormatOption: default to text" {
    try testing.expectEqual(.text, common.parseDiffFormatOption(""));
    try testing.expectEqual(.text, common.parseDiffFormatOption("dialect=pg"));
    try testing.expectEqual(.text, common.parseDiffFormatOption("format=invalid"));
}

test "parseDiffFormatOption: format with other options" {
    try testing.expectEqual(.sarif, common.parseDiffFormatOption("dialect=pg format=sarif"));
}
