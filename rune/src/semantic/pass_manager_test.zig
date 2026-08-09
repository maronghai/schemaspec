const std = @import("std");
const pm = @import("pass_manager.zig");

const testing = std.testing;

test "DEFAULT_PASSES: dependency order is valid" {
    pm.validateDependencyOrder(testing.allocator);
}

test "DEFAULT_PASSES: expected count" {
    try testing.expectEqual(@as(usize, 13), pm.DEFAULT_PASSES.len);
}

test "DEFAULT_PASSES: access conflict detection passes" {
    // validatePassAccess should not panic with valid access patterns
    pm.validatePassAccess(testing.allocator);
}

test "DEFAULT_PASSES: all pass names are unique" {
    var seen = std.StringHashMap(void).init(testing.allocator);
    defer seen.deinit();
    for (pm.DEFAULT_PASSES) |pass| {
        const result = try seen.put(pass.name, {});
        if (result != null) {
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
    // Verify that passes with writes_tables access depend on earlier writers
    // to prevent write-write conflicts
    for (pm.DEFAULT_PASSES) |pass| {
        if (!pass.access.writes_tables and !pass.access.modifies_table_list and !pass.access.writes_types) {
            continue; // Not a writer, skip
        }
        // Check that this pass depends on all earlier writers
        // (validatePassAccess already checks this, but we verify independently)
        for (pm.DEFAULT_PASSES) |prev| {
            if (std.mem.eql(u8, prev.name, pass.name)) break; // Reached self
            if (!prev.access.writes_tables and !prev.access.modifies_table_list and !prev.access.writes_types) {
                continue; // Previous pass is not a writer
            }
            // Previous pass is a writer - check if current pass depends on it
            var depends = false;
            for (pass.depends_on) |dep| {
                if (std.mem.eql(u8, dep, prev.name)) {
                    depends = true;
                    break;
                }
            }
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
