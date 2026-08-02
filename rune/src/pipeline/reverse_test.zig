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
