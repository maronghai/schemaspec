const std = @import("std");
const parse = @import("parse.zig");
const types = @import("types.zig");
const testing = std.testing;

// ─── Flag Parser Tests ──────────────────────────────────────────

test "parseRollbackFlag: present" {
    const args = &.{ "diff", "old.ss", "new.ss", "--rollback" };
    try testing.expect(parse.parseRollbackFlag(args, 0));
}

test "parseRollbackFlag: absent" {
    const args = &.{ "diff", "old.ss", "new.ss" };
    try testing.expect(!parse.parseRollbackFlag(args, 0));
}

test "parseRollbackFlag: respects start index" {
    const args = &.{ "diff", "--rollback", "old.ss", "new.ss" };
    try testing.expect(!parse.parseRollbackFlag(args, 2));
    try testing.expect(parse.parseRollbackFlag(args, 1));
}

test "parseOutputFlag: -o flag" {
    const args = &.{ "compile", "schema.ss", "-o", "out.sql" };
    try testing.expectEqualStrings("out.sql", parse.parseOutputFlag(args, 1).?);
}

test "parseOutputFlag: --output flag" {
    const args = &.{ "compile", "schema.ss", "--output", "out.sql" };
    try testing.expectEqualStrings("out.sql", parse.parseOutputFlag(args, 1).?);
}

test "parseOutputFlag: missing value" {
    const args = &.{ "compile", "schema.ss", "-o" };
    try testing.expectEqual(@as(?[]const u8, null), parse.parseOutputFlag(args, 1));
}

test "parseOutputFlag: value looks like flag" {
    const args = &.{ "compile", "schema.ss", "-o", "--other" };
    try testing.expectEqual(@as(?[]const u8, null), parse.parseOutputFlag(args, 1));
}

test "parseOutputFlag: absent" {
    const args = &.{ "compile", "schema.ss" };
    try testing.expectEqual(@as(?[]const u8, null), parse.parseOutputFlag(args, 0));
}

test "parseTraceFlag: present" {
    const args = &.{ "compile", "schema.ss", "--trace" };
    try testing.expect(parse.parseTraceFlag(args, 0));
}

test "parseTraceFlag: short form" {
    const args = &.{ "compile", "schema.ss", "-t" };
    try testing.expect(parse.parseTraceFlag(args, 0));
}

test "parseTraceFlag: absent" {
    const args = &.{ "compile", "schema.ss" };
    try testing.expect(!parse.parseTraceFlag(args, 0));
}

test "hasHelpFlag: --help present" {
    const args = &.{ "compile", "--help" };
    try testing.expect(parse.hasHelpFlag(args));
}

test "hasHelpFlag: -h present" {
    const args = &.{ "compile", "-h" };
    try testing.expect(parse.hasHelpFlag(args));
}

test "hasHelpFlag: absent" {
    const args = &.{ "compile", "schema.ss" };
    try testing.expect(!parse.hasHelpFlag(args));
}

// ─── Flag Detection Tests ──────────────────────────────────────

test "findUnknownFlag: finds unknown flag" {
    const args = &.{ "compile", "schema.ss", "--bogus" };
    const flag = parse.findUnknownFlag(args);
    try testing.expect(flag != null);
    try testing.expectEqualStrings("--bogus", flag.?);
}

test "findUnknownFlag: returns null for known flags" {
    const args = &.{ "compile", "schema.ss", "--dialect", "pg" };
    try testing.expectEqual(@as(?[]const u8, null), parse.findUnknownFlag(args));
}

test "findUnknownFlag: skips non-flag args" {
    const args = &.{ "schema.ss", "--bogus" };
    const flag = parse.findUnknownFlag(args);
    try testing.expect(flag != null);
    try testing.expectEqualStrings("--bogus", flag.?);
}

test "isKnownLongFlag: global flags are known" {
    try testing.expect(parse.isKnownLongFlag("--dialect"));
    try testing.expect(parse.isKnownLongFlag("--version"));
    try testing.expect(parse.isKnownLongFlag("--quiet"));
}

test "isKnownLongFlag: unknown flags" {
    try testing.expect(!parse.isKnownLongFlag("--bogus-flag"));
    try testing.expect(!parse.isKnownLongFlag("--not-a-real-flag"));
}

// ─── Suggestion Tests ──────────────────────────────────────────

test "suggestSimilarFlag: suggests close match" {
    const suggestion = parse.suggestSimilarFlag("--dialet");
    try testing.expect(suggestion != null);
    try testing.expectEqualStrings("--dialect", suggestion.?);
}

test "suggestSimilarFlag: no match for very different flags" {
    const suggestion = parse.suggestSimilarFlag("--completely-different");
    try testing.expectEqual(@as(?[]const u8, null), suggestion);
}

// ─── Target Parsing Tests ──────────────────────────────────────

test "parseTarget: sql" {
    try testing.expectEqual(types.Target.sql, try parse.parseTarget("sql"));
}

test "parseTarget: json-schema" {
    try testing.expectEqual(types.Target.json_schema, try parse.parseTarget("json-schema"));
}

test "parseTarget: json_schema (underscore variant)" {
    try testing.expectEqual(types.Target.json_schema, try parse.parseTarget("json_schema"));
}

test "parseTarget: unknown" {
    try testing.expectError(error.UnknownTarget, parse.parseTarget("xml"));
}

// ─── Generator Name Tests ──────────────────────────────────────

test "isValidGeneratorName: known generators" {
    try testing.expect(parse.isValidGeneratorName("json-schema"));
    try testing.expect(parse.isValidGeneratorName("prisma"));
    try testing.expect(parse.isValidGeneratorName("drizzle"));
    try testing.expect(parse.isValidGeneratorName("sql-ddl"));
    try testing.expect(parse.isValidGeneratorName("openapi"));
    try testing.expect(parse.isValidGeneratorName("graphql"));
}

test "isValidGeneratorName: unknown generator" {
    try testing.expect(!parse.isValidGeneratorName("rustorm"));
    try testing.expect(!parse.isValidGeneratorName("prism"));
}

// ─── parseSimpleSubcommand ─────────────────────────────────────

test "parseSimpleSubcommand: builds ParsedArgs correctly" {
    const result = parse.parseSimpleSubcommand(
        .pg,
        .sql,
        .version,
        .{ .dialect_was_explicit = true, .quiet = true, .stats = false, .check = false, .dry_run = false, .strict = false, .verbose_passes = false, .json_errors = false, .color = .auto, .format = .text, .validate_only = false, .import_paths = &.{} },
    );
    try testing.expectEqual(.pg, result.dialect);
    try testing.expect(result.dialect_was_explicit);
    try testing.expectEqual(types.Target.sql, result.target);
    try testing.expect(result.quiet);
    try testing.expectEqual(types.Command{ .version = {} }, result.command);
}

// ─── parseArgs Integration Tests ──────────────────────────────

test "parseArgs: version flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--version" });
    try testing.expectEqual(types.Command{ .version = {} }, result.command);
}

test "parseArgs: no args defaults to compile" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{"rune"});
    switch (result.command) {
        .compile => |cmd| {
            try testing.expectEqual(@as(?[]const u8, null), cmd.input);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: input file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "schema.ss" });
    switch (result.command) {
        .compile => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: subcommand dispatch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "validate", "schema.ss" });
    switch (result.command) {
        .validate => |cmd| {
            try testing.expectEqualStrings("schema.ss", cmd.input.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --dialect flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--dialect", "pg", "schema.ss" });
    try testing.expectEqual(.pg, result.dialect);
    try testing.expect(result.dialect_was_explicit);
}

test "parseArgs: --quiet flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--quiet", "schema.ss" });
    try testing.expect(result.quiet);
}

test "parseArgs: --json-errors flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--json-errors", "schema.ss" });
    try testing.expect(result.json_errors);
}

test "parseArgs: --target flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--target", "json-schema", "schema.ss" });
    try testing.expectEqual(types.Target.json_schema, result.target);
}

test "parseArgs: help flag with subcommand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "validate", "--help" });
    switch (result.command) {
        .help => |cmd| {
            try testing.expectEqualStrings("validate", cmd.subcommand.?);
        },
        else => try testing.expect(false),
    }
}

test "parseArgs: --init flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const result = try parse.parseArgs(alloc, &.{ "rune", "--init" });
    try testing.expect(result.init_flag);
}
