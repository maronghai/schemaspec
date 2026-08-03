const std = @import("std");
const reverse_pipe = @import("reverse.zig");

const testing = std.testing;

// ─── ReverseConfig Tests ──────────────────────────────────────

test "ReverseConfig: default values" {
    const cfg = reverse_pipe.ReverseConfig{};
    try testing.expectEqualStrings("<stdin>", cfg.input_name);
    try testing.expect(cfg.output_path == null);
    try testing.expectEqual(@import("../codegen/codegen.zig").Dialect.mysql, cfg.dialect);
    try testing.expect(!cfg.with_templates);
    try testing.expect(!cfg.trace);
    try testing.expect(!cfg.stats);
    try testing.expect(!cfg.validate_only);
}

test "ReverseConfig: custom values" {
    const cfg = reverse_pipe.ReverseConfig{
        .input_name = "schema.sql",
        .output_path = "out.ss",
        .dialect = .pg,
        .with_templates = true,
        .trace = true,
        .stats = true,
        .validate_only = true,
    };
    try testing.expectEqualStrings("schema.sql", cfg.input_name);
    try testing.expectEqualStrings("out.ss", cfg.output_path.?);
    try testing.expectEqual(@import("../codegen/codegen.zig").Dialect.pg, cfg.dialect);
    try testing.expect(cfg.with_templates);
    try testing.expect(cfg.trace);
    try testing.expect(cfg.stats);
    try testing.expect(cfg.validate_only);
}

test "ReverseConfig: partial override" {
    const cfg = reverse_pipe.ReverseConfig{
        .input_name = "test.sql",
        .dialect = .sqlite,
    };
    try testing.expectEqualStrings("test.sql", cfg.input_name);
    try testing.expect(cfg.output_path == null);
    try testing.expectEqual(@import("../codegen/codegen.zig").Dialect.sqlite, cfg.dialect);
    try testing.expect(!cfg.with_templates);
    try testing.expect(!cfg.trace);
    try testing.expect(!cfg.stats);
    try testing.expect(!cfg.validate_only);
}
