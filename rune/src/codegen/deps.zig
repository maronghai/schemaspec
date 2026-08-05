const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");

// ─── Dependency Graph Analysis ──────────────────────────────────
// Analyzes table dependencies (via FK references) and determines
// which tables can be compiled in parallel.

/// Dependency graph: for each table index, the list of table indices it depends on.
pub const DepGraph = struct {
    /// deps[i] = list of table indices that table i depends on.
    deps: []const []const usize,
    /// Topological ordering of table indices.
    topo_order: []const usize,
    /// Groups of table indices that can be compiled in parallel (no inter-dependencies).
    /// Indexed by dependency level: groups[0] = tables with no deps, etc.
    groups: []const []const usize,

    pub fn deinit(self: DepGraph, alloc: std.mem.Allocator) void {
        for (self.deps) |d| alloc.free(d);
        alloc.free(self.deps);
        alloc.free(self.topo_order);
        for (self.groups) |g| alloc.free(g);
        alloc.free(self.groups);
    }
};

/// Analyze dependencies between tables based on FK references.
/// Returns a dependency graph that can be used for parallel compilation.
pub fn analyzeDependencies(
    alloc: std.mem.Allocator,
    tables: []const typed_ast.TypedTable,
) !DepGraph {
    const n = tables.len;

    // Build name → index map
    var name_map = std.StringHashMap(usize).init(alloc);
    defer name_map.deinit();
    for (tables, 0..) |t, i| {
        try name_map.put(t.name, i);
    }

    // Build dependency lists
    var deps = try std.ArrayList([]const usize).initCapacity(alloc, n);
    for (tables) |t| {
        var table_deps = try std.ArrayList(usize).initCapacity(alloc, t.fks.len);
        for (t.fks) |fk| {
            if (name_map.get(fk.ref_table)) |dep_idx| {
                if (dep_idx != deps.items.len) {
                    var is_dup = false;
                    for (table_deps.items) |d| {
                        if (d == dep_idx) {
                            is_dup = true;
                            break;
                        }
                    }
                    if (!is_dup) {
                        table_deps.appendAssumeCapacity(dep_idx);
                    }
                }
            }
        }
        deps.appendAssumeCapacity(try table_deps.toOwnedSlice(alloc));
    }

    const topo = try topoSort(alloc, n, deps.items);
    const groups = try findGroups(alloc, n, deps.items);

    return .{
        .deps = try deps.toOwnedSlice(alloc),
        .topo_order = topo,
        .groups = groups,
    };
}

/// Topological sort using Kahn's algorithm.
pub fn topoSort(
    alloc: std.mem.Allocator,
    n: usize,
    deps: []const []const usize,
) ![]const usize {
    // in_degree[i] = number of tables that table i depends on
    var in_degree = try alloc.alloc(usize, n);
    defer alloc.free(in_degree);
    @memset(in_degree, 0);
    for (deps, 0..) |d, i| {
        in_degree[i] = d.len;
    }

    // Queue: nodes with no dependencies (use a ring buffer)
    var queue = try std.ArrayList(usize).initCapacity(alloc, n);
    for (in_degree, 0..) |deg, i| {
        if (deg == 0) queue.appendAssumeCapacity(i);
    }

    var result = try std.ArrayList(usize).initCapacity(alloc, n);
    var head: usize = 0;
    var processed: usize = 0;

    while (head < queue.items.len) {
        const node = queue.items[head];
        head += 1;
        result.appendAssumeCapacity(node);
        processed += 1;

        for (deps, 0..) |d, i| {
            for (d) |dep| {
                if (dep == node) {
                    in_degree[i] -= 1;
                    if (in_degree[i] == 0) {
                        try queue.append(alloc, i);
                    }
                }
            }
        }
    }

    // If not all nodes processed, there's a cycle — add remaining in order
    if (processed < n) {
        for (0..n) |i| {
            var found = false;
            for (result.items) |r| {
                if (r == i) {
                    found = true;
                    break;
                }
            }
            if (!found) result.appendAssumeCapacity(i);
        }
    }

    queue.deinit(alloc);
    return try result.toOwnedSlice(alloc);
}

/// Find groups of tables that can be compiled in parallel, organized by
/// dependency level. Tables at the same level have no dependencies on each
/// other and can be compiled concurrently. Level 0 = no dependencies,
/// level 1 = depends only on level-0 tables, etc.
pub fn findGroups(
    alloc: std.mem.Allocator,
    n: usize,
    deps: []const []const usize,
) ![]const []const usize {
    // Compute in-degree for each table
    var in_degree = try alloc.alloc(usize, n);
    defer alloc.free(in_degree);
    @memset(in_degree, 0);
    for (deps, 0..) |d, i| {
        in_degree[i] = d.len;
    }

    // BFS level assignment: level[i] = longest dependency chain length
    var level = try alloc.alloc(usize, n);
    defer alloc.free(level);
    @memset(level, 0);

    var queue = try std.ArrayList(usize).initCapacity(alloc, n);
    defer queue.deinit(alloc);

    for (0..n) |i| {
        if (in_degree[i] == 0) {
            queue.appendAssumeCapacity(i);
        }
    }

    var head: usize = 0;
    var max_level: usize = 0;
    while (head < queue.items.len) {
        const node = queue.items[head];
        head += 1;
        for (deps, 0..) |d, i| {
            for (d) |dep| {
                if (dep == node) {
                    in_degree[i] -= 1;
                    const new_level = level[node] + 1;
                    if (new_level > level[i]) level[i] = new_level;
                    if (new_level > max_level) max_level = new_level;
                    if (in_degree[i] == 0) {
                        queue.appendAssumeCapacity(i);
                    }
                }
            }
        }
    }

    // Handle cycles: assign unvisited nodes (in_degree > 0) to an extra level
    var has_cycles = false;
    for (in_degree) |d| {
        if (d > 0) {
            has_cycles = true;
            break;
        }
    }
    if (has_cycles) {
        for (level, 0..) |*l, i| {
            if (in_degree[i] > 0) l.* = max_level + 1;
        }
        max_level += 1;
    }

    const total_levels = max_level + 1;

    // Count tables per level
    var level_counts = try alloc.alloc(usize, total_levels);
    defer alloc.free(level_counts);
    @memset(level_counts, 0);
    for (level) |l| {
        level_counts[l] += 1;
    }

    // Build level groups
    var groups = try std.ArrayList([]const usize).initCapacity(alloc, total_levels);
    for (0..total_levels) |lvl| {
        var group = try std.ArrayList(usize).initCapacity(alloc, level_counts[lvl]);
        for (level, 0..) |l, i| {
            if (l == lvl) {
                group.appendAssumeCapacity(i);
            }
        }
        groups.appendAssumeCapacity(try group.toOwnedSlice(alloc));
    }
    return try groups.toOwnedSlice(alloc);
}

// ─── Tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "analyzeDependencies: no FKs" {
    const tables = &[_]typed_ast.TypedTable{
        .{ .name = "a", .comment = null, .engine = null, .columns = &.{}, .fks = &.{}, .indexes = &.{}, .line_no = 1 },
        .{ .name = "b", .comment = null, .engine = null, .columns = &.{}, .fks = &.{}, .indexes = &.{}, .line_no = 2 },
    };
    const graph = try analyzeDependencies(testing.allocator, tables);
    defer graph.deinit(testing.allocator);
    // All independent → one group with all tables
    try testing.expectEqual(@as(usize, 1), graph.groups.len);
    try testing.expectEqual(@as(usize, 2), graph.groups[0].len);
}

test "topoSort: simple chain" {
    var deps_buf: [3][]const usize = undefined;
    deps_buf[0] = &[_]usize{};
    deps_buf[1] = &[_]usize{0};
    deps_buf[2] = &[_]usize{1};
    const deps = &deps_buf;

    const order = try topoSort(testing.allocator, 3, deps);
    defer testing.allocator.free(order);
    try testing.expectEqual(@as(usize, 0), order[0]);
    try testing.expectEqual(@as(usize, 1), order[1]);
    try testing.expectEqual(@as(usize, 2), order[2]);
}

test "findGroups: all independent tables" {
    var deps_buf: [3][]const usize = undefined;
    deps_buf[0] = &[_]usize{};
    deps_buf[1] = &[_]usize{};
    deps_buf[2] = &[_]usize{};

    const groups = try findGroups(testing.allocator, 3, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    try testing.expectEqual(@as(usize, 1), groups.len);
    try testing.expectEqual(@as(usize, 3), groups[0].len);
}

test "findGroups: 3-level dependency chain" {
    var deps_buf: [3][]const usize = undefined;
    deps_buf[0] = &[_]usize{}; // a: no deps → level 0
    deps_buf[1] = &[_]usize{0}; // b: depends on a → level 1
    deps_buf[2] = &[_]usize{1}; // c: depends on b → level 2

    const groups = try findGroups(testing.allocator, 3, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 1), groups[0].len); // level 0: a
    try testing.expectEqual(@as(usize, 1), groups[1].len); // level 1: b
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: c
}

test "findGroups: diamond pattern" {
    var deps_buf: [4][]const usize = undefined;
    deps_buf[0] = &[_]usize{}; // a: no deps → level 0
    deps_buf[1] = &[_]usize{0}; // b: depends on a → level 1
    deps_buf[2] = &[_]usize{0}; // c: depends on a → level 1
    deps_buf[3] = &[_]usize{ 0, 1 }; // d: depends on a and b → level 2

    const groups = try findGroups(testing.allocator, 4, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 1), groups[0].len); // level 0: a
    try testing.expectEqual(@as(usize, 2), groups[1].len); // level 1: b, c
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: d
}

test "findGroups: mixed independent and dependent" {
    var deps_buf: [4][]const usize = undefined;
    deps_buf[0] = &[_]usize{}; // a: no deps → level 0
    deps_buf[1] = &[_]usize{0}; // b: depends on a → level 1
    deps_buf[2] = &[_]usize{}; // c: no deps → level 0
    deps_buf[3] = &[_]usize{1}; // d: depends on b → level 2

    const groups = try findGroups(testing.allocator, 4, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 2), groups[0].len); // level 0: a, c
    try testing.expectEqual(@as(usize, 1), groups[1].len); // level 1: b
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: d
}
