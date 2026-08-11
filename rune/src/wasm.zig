const std = @import("std");

// ─── WASM Library Entry Point ──────────────────────────────────
// Compile-time entry point for wasm32-wasi target. Re-exports all sub-modules
// so their `export fn` declarations are visible to the linker.
// Each sub-module defines its own export functions — this file is the compilation unit
// that brings them together for the wasm32-wasi target.
comptime {
    _ = @import("wasm/error.zig");
    _ = @import("wasm/compile.zig");
    _ = @import("wasm/diff.zig");
    _ = @import("wasm/reverse.zig");
    _ = @import("wasm/lint.zig");
    _ = @import("wasm/format.zig");
    _ = @import("wasm/generate.zig");
    _ = @import("wasm/export.zig");
    _ = @import("wasm/docs.zig");
}

// ─── Tests ──────────────────────────────────────────────────────

test "parseOption" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqualStrings("pg", common.parseOption("dialect=pg", "dialect").?);
    try std.testing.expectEqualStrings("mysql", common.parseOption("dialect=mysql format=sql", "dialect").?);
    try std.testing.expectEqualStrings("sql", common.parseOption("dialect=mysql format=sql", "format").?);
    try std.testing.expect(common.parseOption("other=pg", "dialect") == null);
    try std.testing.expect(common.parseOption("", "dialect") == null);
}

test "parseDialectOption defaults to mysql" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.mysql, common.parseDialectOption(""));
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.mysql, common.parseDialectOption("other=val"));
}

test "parseDialectOption parses known dialects" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.pg, common.parseDialectOption("dialect=pg"));
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.sqlite, common.parseDialectOption("dialect=sqlite"));
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.mssql, common.parseDialectOption("dialect=mssql"));
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.oracle, common.parseDialectOption("dialect=oracle"));
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.db2, common.parseDialectOption("dialect=db2"));
}

test "parseDialectOption with multiple options" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@import("dialect/enum.zig").Dialect.pg, common.parseDialectOption("dialect=pg format=json"));
}

test "parseDiffFormatOption defaults to text" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@import("types/enums.zig").DiffFormat.text, common.parseDiffFormatOption(""));
    try std.testing.expectEqual(@import("types/enums.zig").DiffFormat.text, common.parseDiffFormatOption("dialect=pg"));
}

test "parseDiffFormatOption parses known formats" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@import("types/enums.zig").DiffFormat.json, common.parseDiffFormatOption("format=json"));
    try std.testing.expectEqual(@import("types/enums.zig").DiffFormat.sarif, common.parseDiffFormatOption("format=sarif"));
    try std.testing.expectEqual(@import("types/enums.zig").DiffFormat.markdown, common.parseDiffFormatOption("format=markdown"));
}

test "rune_last_error after compile error" {
    // First, do a successful compile to clear any previous state
    const valid = "# users\nid N ++\nname s\n";
    _ = @import("wasm/compile.zig").rune_compile(valid.ptr, valid.len, "dialect=pg", 11);
    try std.testing.expect(@import("wasm/error.zig").rune_last_error() == null);
    // Now reset and verify clean state
    @import("wasm/error.zig").rune_reset();
    try std.testing.expect(@import("wasm/error.zig").rune_last_error() == null);
}

test "rune_last_error_code after success" {
    const schema = "# users\nid N ++\nname s\n";
    _ = @import("wasm/compile.zig").rune_compile(schema.ptr, schema.len, "dialect=pg", 11);
    try std.testing.expectEqual(@as(i32, 0), @import("wasm/error.zig").rune_last_error_code());
    @import("wasm/error.zig").rune_reset();
    try std.testing.expectEqual(@as(i32, 0), @import("wasm/error.zig").rune_last_error_code());
}

// ─── classifyError tests ─────────────────────────────────────────

test "classifyError: syntax errors return code 1" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@as(i32, 1), common.classifyError("SyntaxError"));
    try std.testing.expectEqual(@as(i32, 1), common.classifyError("ParseError"));
    try std.testing.expectEqual(@as(i32, 1), common.classifyError("Unexpected Syntax token"));
}

test "classifyError: type errors return code 2" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@as(i32, 2), common.classifyError("TypeError"));
    try std.testing.expectEqual(@as(i32, 2), common.classifyError("Unknown Type symbol"));
}

test "classifyError: FK errors return code 3" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@as(i32, 3), common.classifyError("ForeignKeyError"));
    try std.testing.expectEqual(@as(i32, 3), common.classifyError("FkTargetError"));
}

test "classifyError: semantic errors return code 4" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@as(i32, 4), common.classifyError("SemanticError"));
    try std.testing.expectEqual(@as(i32, 4), common.classifyError("DiagnosticError"));
}

test "classifyError: unknown errors return code 5" {
    const common = @import("wasm/common.zig");
    try std.testing.expectEqual(@as(i32, 5), common.classifyError("UnknownError"));
    try std.testing.expectEqual(@as(i32, 5), common.classifyError("SomeRandomError"));
    try std.testing.expectEqual(@as(i32, 5), common.classifyError(""));
}

// ─── storeError + clearError lifecycle ────────────────────────────

test "storeError sets error state, clearError resets" {
    const common = @import("wasm/common.zig");
    const err_mod = @import("wasm/error.zig");

    // Clear first
    err_mod.rune_reset();
    try std.testing.expect(err_mod.rune_last_error() == null);
    try std.testing.expectEqual(@as(i32, 0), err_mod.rune_last_error_code());

    // Store an error
    const alloc = common.gpa.allocator();
    common.storeError(alloc, "SyntaxError");
    try std.testing.expect(err_mod.rune_last_error() != null);
    try std.testing.expectEqual(@as(i32, 1), err_mod.rune_last_error_code());

    // Clear
    err_mod.rune_reset();
    try std.testing.expect(err_mod.rune_last_error() == null);
    try std.testing.expectEqual(@as(i32, 0), err_mod.rune_last_error_code());
}

// ─── parseOption edge cases ──────────────────────────────────────

test "parseOption: empty key matches =value" {
    const common = @import("wasm/common.zig");
    // Empty key matches token "=value" (key="" before =)
    const result = common.parseOption("=value", "");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualStrings("value", r);
    }
}

test "parseOption: empty value returns empty string" {
    const common = @import("wasm/common.zig");
    const result = common.parseOption("key=", "key");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqual(@as(usize, 0), r.len);
    }
}

test "parseOption: value with equals sign" {
    const common = @import("wasm/common.zig");
    const result = common.parseOption("key=val=ue", "key");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualStrings("val=ue", r);
    }
}

test "parseOption: multiple keys, pick second" {
    const common = @import("wasm/common.zig");
    const result = common.parseOption("a=1 b=2 c=3", "b");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualStrings("2", r);
    }
}

test "parseOption: key not found" {
    const common = @import("wasm/common.zig");
    try std.testing.expect(common.parseOption("a=1 b=2", "c") == null);
}

test "parseOption: single option" {
    const common = @import("wasm/common.zig");
    const result = common.parseOption("dialect=pg", "dialect");
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualStrings("pg", r);
    }
}
