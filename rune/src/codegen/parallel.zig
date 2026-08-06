const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const codegen = @import("codegen.zig");
const dialect_enum = @import("../dialect/enum.zig");
const streaming = @import("streaming.zig");
const deps_mod = @import("deps.zig");

pub const DepGraph = deps_mod.DepGraph;
pub const analyzeDependencies = deps_mod.analyzeDependencies;
pub const findGroups = deps_mod.findGroups;

// ─── Parallel Table Compilation ─────────────────────────────────
// Compiles independent tables concurrently using a thread pool.
// Dependency analysis is in deps.zig.

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

    // WASM: no threads available — fall back to sequential streaming
    if (comptime @import("builtin").os.tag == .wasi) {
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

            var all_spawned = true;
            for (thread_ctxs.items) |ctx| {
                const t = std.Thread.spawn(.{}, compileOneTableAsync, .{ctx}) catch {
                    all_spawned = false;
                    break;
                };
                threads.appendAssumeCapacity(t);
            }

            // Join all spawned threads (whether or not all succeeded)
            for (threads.items) |thread| thread.join();

            if (all_spawned) {
                // Collect results in group order, free thread arenas
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
                // Spawn failure — compile all tables sequentially
                for (group) |table_idx| {
                    const sql = try compileOneTable(alloc, dialect, typed.tables[table_idx]);
                    tables.appendAssumeCapacity(.{
                        .name = typed.tables[table_idx].name,
                        .sql = sql,
                        .line_no = typed.tables[table_idx].line_no,
                    });
                    total_size += sql.len;
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

                    var all_spawned = true;
                    for (thread_ctxs.items) |ctx| {
                        const t = std.Thread.spawn(.{}, compileOneTableAsync, .{ctx}) catch {
                            all_spawned = false;
                            break;
                        };
                        threads.appendAssumeCapacity(t);
                    }

                    for (threads.items) |thread| thread.join();

                    if (all_spawned) {
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

test "compileParallel: fully dependent tables fall back to sequential" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Chain: users → posts → comments (all dependent, single group)
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

    var table_list: [3]typed_ast.TypedTable = undefined;
    table_list[0] = .{ .name = "users", .comment = null, .engine = null, .columns = users_cols, .fks = &.{}, .indexes = &.{}, .line_no = 1 };
    table_list[1] = .{ .name = "posts", .comment = null, .engine = null, .columns = posts_cols, .fks = posts_fks, .indexes = &.{}, .line_no = 2 };
    table_list[2] = .{ .name = "comments", .comment = null, .engine = null, .columns = comments_cols, .fks = comments_fks, .indexes = &.{}, .line_no = 3 };

    const tables = try alloc.dupe(typed_ast.TypedTable, &table_list);
    const typed = typed_ast.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };

    // All 3 tables are dependent → single group → sequential fallback
    const result = try compileParallel(alloc, .mysql, typed, .{ .min_tables = 2 });
    try testing.expectEqual(@as(usize, 3), result.table_count);
    try testing.expectEqual(@as(usize, 3), result.tables.len);

    // Verify order preserved: users before posts, posts before comments
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
