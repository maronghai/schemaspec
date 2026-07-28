const std = @import("std");
const pm = @import("pass_manager.zig");

const testing = std.testing;

test "DEFAULT_PASSES: dependency order is valid" {
    pm.validateDependencyOrder();
}

test "DEFAULT_PASSES: expected count" {
    try testing.expectEqual(@as(usize, 8), pm.DEFAULT_PASSES.len);
}

test "canRunConcurrently: independent passes can run together" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined };
    const b = pm.SemanticPass{ .name = "b", .run = undefined };
    try testing.expect(pm.canRunConcurrently(a, b));
}

test "canRunConcurrently: dependent passes cannot run together" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .depends_on = &.{"b"} };
    const b = pm.SemanticPass{ .name = "b", .run = undefined };
    try testing.expect(!pm.canRunConcurrently(a, b));
}

test "canRunConcurrently: write-write conflict prevents concurrency" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .access = .{ .writes_tables = true } };
    const b = pm.SemanticPass{ .name = "b", .run = undefined, .access = .{ .writes_tables = true } };
    try testing.expect(!pm.canRunConcurrently(a, b));
}

test "canRunConcurrently: read-write is fine" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .access = .{ .reads_tables = true } };
    const b = pm.SemanticPass{ .name = "b", .run = undefined, .access = .{ .writes_tables = true } };
    try testing.expect(pm.canRunConcurrently(a, b));
}

test "detectConflicts: no conflicts in DEFAULT_PASSES" {
    // All DEFAULT_PASSES have proper dependency ordering, so no conflicts
    const conflicts = pm.detectConflicts();
    try testing.expectEqual(@as(usize, 0), conflicts.len);
}

test "getParallelGroups: returns non-empty groups" {
    const groups = pm.getParallelGroups();
    try testing.expect(groups.len > 0);
}

test "hasConflict: write-write conflict detected" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .access = .{ .writes_tables = true } };
    const b = pm.SemanticPass{ .name = "b", .run = undefined, .access = .{ .writes_tables = true } };
    try testing.expect(pm.hasConflict(a, b));
}

test "hasConflict: no conflict for read-write" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .access = .{ .reads_tables = true } };
    const b = pm.SemanticPass{ .name = "b", .run = undefined, .access = .{ .writes_tables = true } };
    try testing.expect(!pm.hasConflict(a, b));
}

test "dependsOn: direct dependency detected" {
    const a = pm.SemanticPass{ .name = "a", .run = undefined, .depends_on = &.{"b"} };
    const b = pm.SemanticPass{ .name = "b", .run = undefined };
    try testing.expect(pm.dependsOn(a, b));
    try testing.expect(!pm.dependsOn(b, a));
}
