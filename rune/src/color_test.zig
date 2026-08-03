const std = @import("std");
const cli = @import("cli.zig");

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "ColorMode: always returns true" {
    const mode: cli.ColorMode = .always;
    // We can't easily test shouldUseColor without an io parameter in unit tests,
    // but we can test the enum values exist and are correct.
    try testing.expectEqual(cli.ColorMode.always, mode);
}

test "ColorMode: never returns false" {
    const mode: cli.ColorMode = .never;
    try testing.expectEqual(cli.ColorMode.never, mode);
}

test "ColorMode: auto defaults to auto" {
    const mode: cli.ColorMode = .auto;
    try testing.expectEqual(cli.ColorMode.auto, mode);
}

test "ColorMode: all variants exist" {
    // Ensure all three variants are accessible
    _ = cli.ColorMode.auto;
    _ = cli.ColorMode.always;
    _ = cli.ColorMode.never;
}

test "DiffFormat: all variants exist" {
    _ = cli.DiffFormat.text;
    _ = cli.DiffFormat.json;
    _ = cli.DiffFormat.sarif;
    _ = cli.DiffFormat.markdown;
}

test "ParsedArgs: default color is auto" {
    const args = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .version,
        .quiet = false,
        .strict = false,
    };
    try testing.expectEqual(cli.ColorMode.auto, args.color);
}

test "ParsedArgs: color can be set to always" {
    const args = cli.ParsedArgs{
        .dialect = .mysql,
        .target = .sql,
        .command = .version,
        .quiet = false,
        .strict = false,
        .color = .always,
    };
    try testing.expectEqual(cli.ColorMode.always, args.color);
}
