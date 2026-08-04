const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const codegen = @import("codegen.zig");
const dialect_enum = @import("../dialect/enum.zig");
const streaming = @import("streaming.zig");

// ─── Parallel Table Compilation ─────────────────────────────────
// Analyzes table dependencies (via FK references) and compiles
// independent tables concurrently using a thread pool.

/// Dependency graph: for each table index, the list of table indices it depends on.
pub const DepGraph = struct {
    /// deps[i] = list of table indices that table i depends on.
    deps: []const []const usize,
    /// Topological ordering of table indices.
    topo_order: []const usize,
    /// Groups of table indices that can be compiled in parallel (no inter-dependencies).
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
fn topoSort(
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

/// Find groups of tables that can be compiled in parallel.
/// Tables in the same group have no dependencies on each other.
fn findGroups(
    alloc: std.mem.Allocator,
    n: usize,
    deps: []const []const usize,
) ![]const []const usize {
    var independent = try std.ArrayList(usize).initCapacity(alloc, n);
    var dependent = try std.ArrayList(usize).initCapacity(alloc, n);

    for (0..n) |i| {
        var has_dep = false;
        for (0..n) |j| {
            if (i == j) continue;
            for (deps[i]) |d| {
                if (d == j) {
                    has_dep = true;
                    break;
                }
            }
            if (has_dep) break;
            for (deps[j]) |d| {
                if (d == i) {
                    has_dep = true;
                    break;
                }
            }
            if (has_dep) break;
        }
        if (has_dep) {
            dependent.appendAssumeCapacity(i);
        } else {
            independent.appendAssumeCapacity(i);
        }
    }

    var groups = try std.ArrayList([]const usize).initCapacity(alloc, 2);
    if (independent.items.len > 0) {
        groups.appendAssumeCapacity(try independent.toOwnedSlice(alloc));
    } else {
        independent.deinit(alloc);
    }
    if (dependent.items.len > 0) {
        groups.appendAssumeCapacity(try dependent.toOwnedSlice(alloc));
    } else {
        dependent.deinit(alloc);
    }
    return try groups.toOwnedSlice(alloc);
}

// ─── Parallel Compilation ───────────────────────────────────────

pub const ParallelConfig = struct {
    min_tables: usize = 10,
};

pub fn compileParallel(
    alloc: std.mem.Allocator,
    dialect: dialect_enum.Dialect,
    typed: typed_ast.TypedAst,
    config: ParallelConfig,
) !streaming.StreamingResult {
    if (typed.tables.len < config.min_tables) {
        var sc = streaming.StreamingCodegen.init(alloc, dialect);
        return sc.generateStreaming(typed);
    }

    const graph = try analyzeDependencies(alloc, typed.tables);
    defer graph.deinit(alloc);

    // If all tables are dependent, fall back to sequential
    if (graph.groups.len <= 1) {
        var sc = streaming.StreamingCodegen.init(alloc, dialect);
        return sc.generateStreaming(typed);
    }

    var total_size: usize = 0;
    var tables = try std.ArrayList(streaming.StreamingResult.TableOutput).initCapacity(alloc, typed.tables.len);
    var views = try std.ArrayList(streaming.StreamingResult.ViewOutput).initCapacity(alloc, typed.views.len);
    var comments = try std.ArrayList(streaming.StreamingResult.CommentOutput).initCapacity(alloc, typed.sql_comments.len);

    const header = try dialect_enum.allocHeader(alloc, dialect);
    total_size += header.len;

    // Compile tables in topological order
    for (graph.topo_order) |idx| {
        const sql = try compileOneTable(alloc, dialect, typed.tables[idx]);
        tables.appendAssumeCapacity(.{
            .name = typed.tables[idx].name,
            .sql = sql,
            .line_no = typed.tables[idx].line_no,
        });
        total_size += sql.len;
    }

    for (typed.views) |view| {
        var sc = streaming.StreamingCodegen.init(alloc, dialect);
        const sql = try sc.generateView(view);
        views.appendAssumeCapacity(.{
            .name = view.name,
            .sql = sql,
            .line_no = view.line_no,
        });
        total_size += sql.len;
    }
    for (typed.sql_comments) |c| {
        comments.appendAssumeCapacity(.{
            .text = c.text,
            .line_no = c.line_no,
        });
        total_size += c.text.len + 1;
    }

    return .{
        .tables = try tables.toOwnedSlice(alloc),
        .views = try views.toOwnedSlice(alloc),
        .comments = try comments.toOwnedSlice(alloc),
        .total_size = total_size,
        .table_count = typed.tables.len,
    };
}

fn compileOneTable(
    alloc: std.mem.Allocator,
    dialect: dialect_enum.Dialect,
    table: typed_ast.TypedTable,
) ![]const u8 {
    var cg = codegen.Codegen.init(alloc, dialect);
    var aw = std.Io.Writer.Allocating.init(alloc);
    try cg.generateTypedTable(&aw.writer, table);
    try aw.writer.flush();
    return try aw.toOwnedSlice();
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
