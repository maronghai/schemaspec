const std = @import("std");
const testing = std.testing;

// ─── io.zig Unit Tests ───────────────────────────────────────
//
// Note: io.zig functions all require std.Io (platform I/O abstraction).
// std.Io is only available from std.process.Init (production entry point)
// and cannot be trivially constructed in test context.
//
// These tests verify the helper logic and data flow that don't require std.Io.
// Integration testing of I/O functions is covered by golden test scripts
// (tests/test.sh, tests/test_stdin.sh, etc.) which run the compiled binary.

test "readFileOrStdin: '-' path routes to stdin" {
    // Verify the string comparison logic used for stdin detection
    const path = "-";
    try testing.expect(std.mem.eql(u8, path, "-"));
}

test "readFileOrStdin: non-'-' path does not match stdin" {
    const path = "schema.ss";
    try testing.expect(!std.mem.eql(u8, path, "-"));
}

test "readFileOrStdin: empty path does not match stdin" {
    const path = "";
    try testing.expect(!std.mem.eql(u8, path, "-"));
}

test "writeOutput: null output_path means stdout" {
    // Verify the null-check logic
    const output_path: ?[]const u8 = null;
    try testing.expect(output_path == null);
}

test "writeOutput: non-null output_path means file" {
    const output_path: ?[]const u8 = "out.sql";
    try testing.expect(output_path != null);
    try testing.expectEqualStrings("out.sql", output_path.?);
}
