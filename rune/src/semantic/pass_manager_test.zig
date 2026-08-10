const std = @import("std");
const pm = @import("pass_manager.zig");

const testing = std.testing;

test "DEFAULT_PASSES: dependency order is valid" {
    pm.validateDependencyOrder(testing.allocator);
}

test "DEFAULT_PASSES: expected count" {
    try testing.expectEqual(@as(usize, 17), pm.DEFAULT_PASSES.len);
}

test "DEFAULT_PASSES: access conflict detection passes" {
    // validatePassAccess should not panic with valid access patterns
    pm.validatePassAccess(testing.allocator);
}

test "DEFAULT_PASSES: all pass names are unique" {
    var seen = std.StringHashMap(void).init(testing.allocator);
    defer seen.deinit();
    for (pm.DEFAULT_PASSES) |pass| {
        const result = try seen.getOrPut(pass.name);
        if (result.found_existing) {
            try testing.expect(false); // Duplicate pass name found
        }
    }
}

test "DEFAULT_PASSES: all dependency names reference existing passes" {
    // Verify that every depends_on entry refers to a pass that exists
    for (pm.DEFAULT_PASSES) |pass| {
        for (pass.depends_on) |dep| {
            var found = false;
            for (pm.DEFAULT_PASSES) |other| {
                if (std.mem.eql(u8, dep, other.name)) {
                    found = true;
                    break;
                }
            }
            try testing.expect(found);
        }
    }
}

test "DEFAULT_PASSES: writers depend on earlier writers" {
    // Verify that passes with writes_tables access transitively depend on earlier writers
    // to prevent write-write conflicts (matches validatePassAccess logic)
    for (pm.DEFAULT_PASSES) |pass| {
        if (!pass.access.writes_tables) {
            continue; // Only check table writers, not modifies_table_list or writes_types
        }
        // Check that this pass transitively depends on all earlier writers
        for (pm.DEFAULT_PASSES) |prev| {
            if (std.mem.eql(u8, prev.name, pass.name)) break; // Reached self
            if (!prev.access.writes_tables) {
                continue; // Previous pass is not a table writer
            }
            // Previous pass is a table writer - check if current pass transitively depends on it
            const depends = pm.transitivelyDependsOn(pass.name, prev.name);
            // Current pass should depend on previous writer
            try testing.expect(depends);
        }
    }
}

test "DEFAULT_PASSES: all passes have valid access defaults" {
    // Each pass should have at least reads_tables=true
    for (pm.DEFAULT_PASSES) |pass| {
        try testing.expect(pass.access.reads_tables);
    }
}
