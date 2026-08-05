const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
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

/// Find groups of tables that can be compiled in parallel, organized by
/// dependency level. Tables at the same level have no dependencies on each
/// other and can be compiled concurrently. Level 0 = no dependencies,
/// level 1 = depends only on level-0 tables, etc.
fn findGroups(
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

// ─── Parallel Compilation ───────────────────────────────────────

pub const ParallelConfig = struct {
    min_tables: usize = 10,
    /// Maximum number of concurrent threads per group.
    max_threads: usize = 4,
};

/// Result from a single table compilation, carrying its own arena for memory safety.
const ThreadResult = struct {
    arena: std.heap.ArenaAllocator,
    sql: []const u8,
    table_idx: usize,
};

/// Thread context for parallel table compilation.
const ThreadContext = struct {
    alloc: std.mem.Allocator,
    dialect: dialect_enum.Dialect,
    table: typed_ast.TypedTable,
    table_idx: usize,
    out: *?ThreadResult,
};

fn compileOneTableAsync(ctx: ThreadContext) void {
    var arena = std.heap.ArenaAllocator.init(ctx.alloc);
    errdefer arena.deinit();
    var cg = codegen.Codegen.init(arena.allocator(), ctx.dialect);
    var aw = std.Io.Writer.Allocating.init(arena.allocator());
    cg.generateTypedTable(&aw.writer, ctx.table) catch {
        ctx.out.* = null;
        return;
    };
    aw.writer.flush() catch {
        ctx.out.* = null;
        return;
    };
    const sql = aw.toOwnedSlice() catch {
        ctx.out.* = null;
        return;
    };
    ctx.out.* = .{
        .arena = arena,
        .sql = sql,
        .table_idx = ctx.table_idx,
    };
}

pub fn compileParallel(
    alloc: std.mem.Allocator,
    dialect: dialect_enum.Dialect,
    typed: typed_ast.TypedAst,
    config: ParallelConfig,
) !streaming.StreamingResult {
    if (typed.tables.len < config.min_tables) {
        var sc = try streaming.StreamingCodegen.init(alloc, dialect);
        return sc.generateStreaming(typed);
    }

    const graph = try analyzeDependencies(alloc, typed.tables);
    defer graph.deinit(alloc);

    // If all tables are dependent, fall back to sequential
    if (graph.groups.len <= 1) {
        var sc = try streaming.StreamingCodegen.init(alloc, dialect);
        return sc.generateStreaming(typed);
    }

    var total_size: usize = 0;
    var tables = try std.ArrayList(streaming.StreamingResult.TableOutput).initCapacity(alloc, typed.tables.len);
    var views = try std.ArrayList(streaming.StreamingResult.ViewOutput).initCapacity(alloc, typed.views.len);
    var comments = try std.ArrayList(streaming.StreamingResult.CommentOutput).initCapacity(alloc, typed.sql_comments.len);

    const header = try dialect_enum.allocHeader(alloc, dialect);
    total_size += header.len;

    const cpu_count = std.Thread.getCpuCount() catch 4;
    const max_threads = @min(config.max_threads, cpu_count);

    // Process each group of independent tables
    for (graph.groups) |group| {
        if (group.len == 1) {
            // Single table: compile directly (no thread overhead)
            const sql = try compileOneTable(alloc, dialect, typed.tables[group[0]]);
            tables.appendAssumeCapacity(.{
                .name = typed.tables[group[0]].name,
                .sql = sql,
                .line_no = typed.tables[group[0]].line_no,
            });
            total_size += sql.len;
        } else if (group.len <= max_threads) {
            // Multiple independent tables: compile concurrently with threads
            var thread_ctxs = try std.ArrayList(ThreadContext).initCapacity(alloc, group.len);
            defer thread_ctxs.deinit(alloc);

            var results = try alloc.alloc(?ThreadResult, group.len);
            defer alloc.free(results);
            @memset(results, null);

            for (group, 0..) |table_idx, slot| {
                thread_ctxs.appendAssumeCapacity(.{
                    .alloc = alloc,
                    .dialect = dialect,
                    .table = typed.tables[table_idx],
                    .table_idx = table_idx,
                    .out = &results[slot],
                });
            }

            var threads = try std.ArrayList(std.Thread).initCapacity(alloc, group.len);
            defer threads.deinit(alloc);

            for (thread_ctxs.items) |ctx| {
                threads.appendAssumeCapacity(try std.Thread.spawn(.{}, compileOneTableAsync, .{ctx}));
            }

            for (threads.items) |thread| thread.join();

            // Collect results in group order, free thread arenas
            for (results) |result_opt| {
                if (result_opt) |result| {
                    // Copy SQL from thread arena to main arena
                    const sql = try alloc.dupe(u8, result.sql);
                    tables.appendAssumeCapacity(.{
                        .name = typed.tables[result.table_idx].name,
                        .sql = sql,
                        .line_no = typed.tables[result.table_idx].line_no,
                    });
                    total_size += sql.len;
                    // Free thread arena (invalidates result.sql, but we already copied it)
                    result.arena.deinit();
                } else {
                    // Thread compilation failed — fall back to sequential for this group
                    for (group) |table_idx| {
                        const sql = try compileOneTable(alloc, dialect, typed.tables[table_idx]);
                        tables.appendAssumeCapacity(.{
                            .name = typed.tables[table_idx].name,
                            .sql = sql,
                            .line_no = typed.tables[table_idx].line_no,
                        });
                        total_size += sql.len;
                    }
                    break;
                }
            }
        } else {
            // More tables than max_threads: compile in batches
            var i: usize = 0;
            while (i < group.len) {
                const batch_end = @min(i + max_threads, group.len);
                const batch_len = batch_end - i;

                if (batch_len == 1) {
                    const sql = try compileOneTable(alloc, dialect, typed.tables[group[i]]);
                    tables.appendAssumeCapacity(.{
                        .name = typed.tables[group[i]].name,
                        .sql = sql,
                        .line_no = typed.tables[group[i]].line_no,
                    });
                    total_size += sql.len;
                } else {
                    var thread_ctxs = try std.ArrayList(ThreadContext).initCapacity(alloc, batch_len);
                    defer thread_ctxs.deinit(alloc);

                    var results = try alloc.alloc(?ThreadResult, batch_len);
                    defer alloc.free(results);
                    @memset(results, null);

                    for (group[i..batch_end], 0..) |table_idx, slot| {
                        thread_ctxs.appendAssumeCapacity(.{
                            .alloc = alloc,
                            .dialect = dialect,
                            .table = typed.tables[table_idx],
                            .table_idx = table_idx,
                            .out = &results[slot],
                        });
                    }

                    var threads = try std.ArrayList(std.Thread).initCapacity(alloc, batch_len);
                    defer threads.deinit(alloc);

                    for (thread_ctxs.items) |ctx| {
                        threads.appendAssumeCapacity(try std.Thread.spawn(.{}, compileOneTableAsync, .{ctx}));
                    }

                    for (threads.items) |thread| thread.join();

                    for (results) |result_opt| {
                        if (result_opt) |result| {
                            const sql = try alloc.dupe(u8, result.sql);
                            tables.appendAssumeCapacity(.{
                                .name = typed.tables[result.table_idx].name,
                                .sql = sql,
                                .line_no = typed.tables[result.table_idx].line_no,
                            });
                            total_size += sql.len;
                            result.arena.deinit();
                        } else {
                            for (group[i..batch_end]) |table_idx| {
                                const sql = try compileOneTable(alloc, dialect, typed.tables[table_idx]);
                                tables.appendAssumeCapacity(.{
                                    .name = typed.tables[table_idx].name,
                                    .sql = sql,
                                    .line_no = typed.tables[table_idx].line_no,
                                });
                                total_size += sql.len;
                            }
                            break;
                        }
                    }
                }
                i = batch_end;
            }
        }
    }

    for (typed.views) |view| {
        var sc = try streaming.StreamingCodegen.init(alloc, dialect);
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

test "findGroups: all independent tables" {
    // Tables: a, b, c — no dependencies at all
    var deps_buf: [3][]const usize = undefined;
    deps_buf[0] = &[_]usize{};
    deps_buf[1] = &[_]usize{};
    deps_buf[2] = &[_]usize{};

    const groups = try findGroups(testing.allocator, 3, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    // All at level 0 → 1 group with all 3 tables
    try testing.expectEqual(@as(usize, 1), groups.len);
    try testing.expectEqual(@as(usize, 3), groups[0].len);
}

test "findGroups: 3-level dependency chain" {
    // a → b → c (chain)
    var deps_buf: [3][]const usize = undefined;
    deps_buf[0] = &[_]usize{}; // a: no deps → level 0
    deps_buf[1] = &[_]usize{0}; // b: depends on a → level 1
    deps_buf[2] = &[_]usize{1}; // c: depends on b → level 2

    const groups = try findGroups(testing.allocator, 3, &deps_buf);
    defer {
        for (groups) |g| testing.allocator.free(g);
        testing.allocator.free(groups);
    }

    // 3 levels: [a], [b], [c]
    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 1), groups[0].len); // level 0: a
    try testing.expectEqual(@as(usize, 1), groups[1].len); // level 1: b
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: c
}

test "findGroups: diamond pattern" {
    // a → b, a → c, b → d, c → d (diamond)
    // Level 0: a; Level 1: b, c; Level 2: d
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

    // 3 levels: [a], [b,c], [d]
    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 1), groups[0].len); // level 0: a
    try testing.expectEqual(@as(usize, 2), groups[1].len); // level 1: b, c
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: d
}

test "findGroups: mixed independent and dependent" {
    // a (independent), b → a, c (independent), d → b
    // Level 0: a, c; Level 1: b; Level 2: d
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

    // 3 levels: [a,c], [b], [d]
    try testing.expectEqual(@as(usize, 3), groups.len);
    try testing.expectEqual(@as(usize, 2), groups[0].len); // level 0: a, c
    try testing.expectEqual(@as(usize, 1), groups[1].len); // level 1: b
    try testing.expectEqual(@as(usize, 1), groups[2].len); // level 2: d
}

test "compileParallel: fewer than min_tables falls back to sequential" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const cols = try alloc.alloc(typed_ast.TypedColumn, 1);
    cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{} };

    const table = typed_ast.TypedTable{
        .name = "t1",
        .comment = null,
        .engine = null,
        .columns = cols,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const tables = try alloc.dupe(typed_ast.TypedTable, &.{table});
    const typed = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };

    // With min_tables=10, a single table should fall back to sequential
    const result = try compileParallel(alloc, .mysql, typed, .{ .min_tables = 10 });
    try testing.expectEqual(@as(usize, 1), result.table_count);
    try testing.expect(result.tables.len >= 1);
    try testing.expect(std.mem.indexOf(u8, result.tables[0].sql, "CREATE TABLE") != null);
}

test "compileParallel: independent tables compile concurrently" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create 12 independent tables (exceeds min_tables=10)
    var table_list: [12]typed_ast.TypedTable = undefined;
    for (0..12) |i| {
        const cols = try alloc.alloc(typed_ast.TypedColumn, 1);
        cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{} };
        const name = try std.fmt.allocPrint(alloc, "t{d}", .{i});
        table_list[i] = .{
            .name = name,
            .comment = null,
            .engine = null,
            .columns = cols,
            .fks = &.{},
            .indexes = &.{},
            .line_no = @intCast(i + 1),
        };
    }
    const tables = try alloc.dupe(typed_ast.TypedTable, &table_list);
    const typed = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };

    const result = try compileParallel(alloc, .mysql, typed, .{ .min_tables = 10 });
    try testing.expectEqual(@as(usize, 12), result.table_count);
    try testing.expectEqual(@as(usize, 12), result.tables.len);

    // All tables should have CREATE TABLE output
    for (result.tables) |t| {
        try testing.expect(std.mem.indexOf(u8, t.sql, "CREATE TABLE") != null);
    }
}

test "compileParallel: dependent tables preserve topological order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create tables with FK dependencies: users → posts → comments
    // Plus independent tables: settings, logs
    const users_cols = try alloc.alloc(typed_ast.TypedColumn, 1);
    users_cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{ .primary_key = true } };

    const posts_cols = try alloc.alloc(typed_ast.TypedColumn, 2);
    posts_cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{ .primary_key = true } };
    posts_cols[1] = .{ .name = "user_id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 2, .flags = .{} };

    const posts_fks = try alloc.alloc(ast_mod.FkDecl, 1);
    posts_fks[0] = .{ .fields = &.{"user_id"}, .ref_table = "users", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 3 };

    const comments_cols = try alloc.alloc(typed_ast.TypedColumn, 2);
    comments_cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{ .primary_key = true } };
    comments_cols[1] = .{ .name = "post_id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 2, .flags = .{} };

    const comments_fks = try alloc.alloc(ast_mod.FkDecl, 1);
    comments_fks[0] = .{ .fields = &.{"post_id"}, .ref_table = "posts", .ref_fields = &.{"id"}, .actions = &.{}, .line_no = 3 };

    const settings_cols = try alloc.alloc(typed_ast.TypedColumn, 1);
    settings_cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{ .primary_key = true } };

    const logs_cols = try alloc.alloc(typed_ast.TypedColumn, 1);
    logs_cols[0] = .{ .name = "id", .sql_type = .int, .default = null, .check = null, .comment = null, .enum_values = &.{}, .line_no = 1, .flags = .{ .primary_key = true } };

    var table_list: [5]typed_ast.TypedTable = undefined;
    // Note: users and settings are independent, posts depends on users, comments depends on posts, logs is independent
    table_list[0] = .{ .name = "users", .comment = null, .engine = null, .columns = users_cols, .fks = &.{}, .indexes = &.{}, .line_no = 1 };
    table_list[1] = .{ .name = "posts", .comment = null, .engine = null, .columns = posts_cols, .fks = posts_fks, .indexes = &.{}, .line_no = 2 };
    table_list[2] = .{ .name = "comments", .comment = null, .engine = null, .columns = comments_cols, .fks = comments_fks, .indexes = &.{}, .line_no = 3 };
    table_list[3] = .{ .name = "settings", .comment = null, .engine = null, .columns = settings_cols, .fks = &.{}, .indexes = &.{}, .line_no = 4 };
    table_list[4] = .{ .name = "logs", .comment = null, .engine = null, .columns = logs_cols, .fks = &.{}, .indexes = &.{}, .line_no = 5 };

    const tables = try alloc.dupe(typed_ast.TypedTable, &table_list);
    const typed = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };

    // 5 tables, min_tables=3 → will use parallel path
    const result = try compileParallel(alloc, .mysql, typed, .{ .min_tables = 3 });
    try testing.expectEqual(@as(usize, 5), result.table_count);

    // Verify topological order: users before posts, posts before comments
    var users_idx: ?usize = null;
    var posts_idx: ?usize = null;
    var comments_idx: ?usize = null;
    for (result.tables, 0..) |t, i| {
        if (std.mem.eql(u8, t.name, "users")) users_idx = i;
        if (std.mem.eql(u8, t.name, "posts")) posts_idx = i;
        if (std.mem.eql(u8, t.name, "comments")) comments_idx = i;
    }
    try testing.expect(users_idx != null);
    try testing.expect(posts_idx != null);
    try testing.expect(comments_idx != null);
    try testing.expect(users_idx.? < posts_idx.?);
    try testing.expect(posts_idx.? < comments_idx.?);
}
