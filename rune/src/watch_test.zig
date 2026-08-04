const std = @import("std");
const testing = std.testing;
const watch = @import("watch.zig");

test "WatchConfig defaults" {
    const cfg = watch.WatchConfig{
        .input = "test.ss",
    };
    try testing.expectEqual(@as(u64, 1000), cfg.interval_ms);
    try testing.expectEqual(false, cfg.quiet);
    try testing.expectEqual(false, cfg.trace);
    try testing.expectEqual(false, cfg.stats);
    try testing.expectEqual(false, cfg.json_errors);
    try testing.expectEqual(@as(?[]const u8, null), cfg.output_path);
}

test "WatchConfig with custom values" {
    const cfg = watch.WatchConfig{
        .input = "test.ss",
        .interval_ms = 500,
        .quiet = true,
        .trace = true,
        .stats = true,
        .json_errors = true,
        .output_path = "out.sql",
    };
    try testing.expectEqual(@as(u64, 500), cfg.interval_ms);
    try testing.expectEqual(true, cfg.quiet);
    try testing.expectEqual(true, cfg.trace);
    try testing.expectEqual(true, cfg.stats);
    try testing.expectEqual(true, cfg.json_errors);
    try testing.expectEqual(@as(?[]const u8, "out.sql"), cfg.output_path);
}

test "WatchConfig with dialect" {
    const cfg = watch.WatchConfig{
        .input = "test.ss",
        .dialect = .pg,
    };
    try testing.expectEqual(.pg, cfg.dialect);
}
