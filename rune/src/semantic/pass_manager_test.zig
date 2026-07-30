const std = @import("std");
const pm = @import("pass_manager.zig");

const testing = std.testing;

test "DEFAULT_PASSES: dependency order is valid" {
    pm.validateDependencyOrder(testing.allocator);
}

test "DEFAULT_PASSES: expected count" {
    try testing.expectEqual(@as(usize, 8), pm.DEFAULT_PASSES.len);
}
