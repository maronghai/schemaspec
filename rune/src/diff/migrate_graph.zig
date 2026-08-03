const std = @import("std");
const io_mod = @import("../io.zig");

// ─── Migration Dependency Graph ────────────────────────────────

pub const MigrationInfo = struct {
    name: []const u8,
    tables: std.StringHashMap(void),
    depends_on: std.ArrayList([]const u8),
};

pub const SortedEntry = struct { name: []const u8, info: *MigrationInfo };

pub const MigrationGraph = struct {
    alloc: std.mem.Allocator,
    migrations: std.StringHashMap(MigrationInfo),
    order: std.ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) MigrationGraph {
        return .{
            .alloc = alloc,
            .migrations = std.StringHashMap(MigrationInfo).init(alloc),
            .order = std.ArrayList([]const u8).initCapacity(alloc, 16) catch unreachable,
        };
    }

    pub fn deinit(self: *MigrationGraph) void {
        var iter = self.migrations.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.tables.deinit();
            entry.value_ptr.depends_on.deinit(self.alloc);
        }
        self.migrations.deinit();
        self.order.deinit(self.alloc);
    }
};

/// Extract table names from SQL content (CREATE TABLE, ALTER TABLE)
fn extractTables(alloc: std.mem.Allocator, content: []const u8) !std.StringHashMap(void) {
    var tables = std.StringHashMap(void).init(alloc);
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '-' or trimmed[0] == '#') continue;

        // Look for CREATE TABLE or ALTER TABLE
        const upper = try std.ascii.allocUpperString(alloc, trimmed);
        defer alloc.free(upper);

        if (std.mem.indexOf(u8, upper, "CREATE TABLE") != null or std.mem.indexOf(u8, upper, "ALTER TABLE") != null) {
            // Extract table name after CREATE TABLE / ALTER TABLE
            const after_keyword = if (std.mem.indexOf(u8, upper, "CREATE TABLE") != null)
                trimmed[std.mem.indexOf(u8, upper, "CREATE TABLE").? + "CREATE TABLE".len ..]
            else
                trimmed[std.mem.indexOf(u8, upper, "ALTER TABLE").? + "ALTER TABLE".len ..];

            const word = std.mem.trimStart(u8, after_keyword, " \t\r\n(`\"");
            if (word.len > 0) {
                // Extract until whitespace, quote, or parenthesis
                var end: usize = 0;
                while (end < word.len) : (end += 1) {
                    if (word[end] == ' ' or word[end] == '\t' or word[end] == '(' or word[end] == '`' or word[end] == '"') break;
                }
                if (end > 0) {
                    const table_name = try alloc.dupe(u8, word[0..end]);
                    try tables.put(table_name, {});
                }
            }
        }
    }
    return tables;
}

/// Build dependency graph from migration files in a directory
pub fn buildGraph(io: std.Io, alloc: std.mem.Allocator, dir_path: []const u8) !MigrationGraph {
    var graph = MigrationGraph.init(alloc);

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| {
        const msg = try std.fmt.allocPrint(alloc, "error: cannot open directory '{s}': {}\n", .{ dir_path, err });
        try io_mod.writeOutput(io, msg, null, false);
        return graph;
    };
    defer dir.close(io);

    // Collect migration files
    var entries = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    defer entries.deinit(alloc);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (name.len > 4 and std.mem.eql(u8, name[name.len - 4 ..], ".sql")) {
            const base = name[0 .. name.len - 4];
            if (std.mem.indexOfScalar(u8, base, '_')) |underscore_pos| {
                const digits = base[0..underscore_pos];
                if (digits.len > 0) {
                    if (std.fmt.parseInt(u32, digits, 10)) |_| {
                        const owned = try alloc.dupe(u8, name);
                        try entries.append(alloc, owned);
                    } else |_| {}
                }
            }
        }
    }

    // Sort entries
    std.mem.sort([]const u8, entries.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    // Build graph: first pass - extract tables from each migration
    for (entries.items) |entry_name| {
        const file_path = try std.fs.path.join(alloc, &.{ dir_path, entry_name });
        const content = try std.Io.Dir.cwd().readFileAlloc(io, file_path, alloc, .unlimited);

        const info = MigrationInfo{
            .name = entry_name,
            .tables = try extractTables(alloc, content),
            .depends_on = try std.ArrayList([]const u8).initCapacity(alloc, 4),
        };
        try graph.migrations.put(entry_name, info);
    }

    // Second pass - build dependencies
    var prev_tables = std.StringHashMap(void).init(alloc);
    defer prev_tables.deinit();

    var sorted_iter = graph.migrations.iterator();
    var sorted_entries = try std.ArrayList(SortedEntry).initCapacity(alloc, graph.migrations.count());

    // Collect and sort
    while (sorted_iter.next()) |entry| {
        try sorted_entries.append(alloc, .{ .name = entry.key_ptr.*, .info = entry.value_ptr });
    }

    std.mem.sort(SortedEntry, sorted_entries.items, {}, struct {
        fn lessThan(_: void, a: SortedEntry, b: SortedEntry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    for (sorted_entries.items) |item| {
        var table_iter = item.info.tables.keyIterator();
        while (table_iter.next()) |table| {
            // Check if this table was modified by any previous migration
            var prev_iter = prev_tables.keyIterator();
            while (prev_iter.next()) |prev_table| {
                if (std.mem.eql(u8, table.*, prev_table.*)) {
                    // Find which previous migration modified this table
                    var dep_iter = graph.migrations.iterator();
                    while (dep_iter.next()) |dep_entry| {
                        if (dep_entry.value_ptr.tables.contains(table.*)) {
                            const dep_name = dep_entry.key_ptr.*;
                            if (!std.mem.eql(u8, dep_name, item.name)) {
                                // Check if already a dependency
                                var already_dep = false;
                                for (item.info.depends_on.items) |d| {
                                    if (std.mem.eql(u8, d, dep_name)) {
                                        already_dep = true;
                                        break;
                                    }
                                }
                                if (!already_dep) {
                                    try item.info.depends_on.append(alloc, dep_name);
                                }
                            }
                        }
                    }
                    break;
                }
            }
        }

        // Add this migration's tables to prev_tables
        var add_iter = item.info.tables.keyIterator();
        while (add_iter.next()) |table| {
            try prev_tables.put(table.*, {});
        }

        try graph.order.append(alloc, item.name);
    }

    return graph;
}

/// Detect circular dependencies using DFS
pub fn detectCycles(graph: *const MigrationGraph) !std.ArrayList([]const u8) {
    var cycles = try std.ArrayList([]const u8).initCapacity(graph.alloc, 4);

    // Simple cycle detection: check if any migration depends on itself transitively
    var iter = graph.migrations.iterator();
    while (iter.next()) |entry| {
        const start = entry.key_ptr.*;
        var visited = std.StringHashMap(void).init(graph.alloc);
        defer visited.deinit();

        var stack = try std.ArrayList([]const u8).initCapacity(graph.alloc, 8);
        defer stack.deinit(graph.alloc);

        try stack.append(graph.alloc, start);

        while (stack.items.len > 0) {
            const current = stack.pop() orelse continue;
            if (visited.contains(current)) continue;
            try visited.put(current, {});

            if (graph.migrations.get(current)) |info| {
                for (info.depends_on.items) |dep| {
                    if (std.mem.eql(u8, dep, start)) {
                        // Found cycle
                        const cycle_msg = try std.fmt.allocPrint(graph.alloc, "Circular dependency: {s} → {s}", .{ start, current });
                        try cycles.append(graph.alloc, cycle_msg);
                        break;
                    }
                    if (!visited.contains(dep)) {
                        try stack.append(graph.alloc, dep);
                    }
                }
            }
        }
    }

    return cycles;
}

/// Format graph output for display
pub fn formatGraph(alloc: std.mem.Allocator, graph: *const MigrationGraph) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.print("Migration Graph ({d} files):\n", .{graph.order.items.len});

    for (graph.order.items) |name| {
        if (graph.migrations.get(name)) |info| {
            if (info.depends_on.items.len == 0) {
                try w.print("  {s}\n", .{name});
            } else {
                try w.print("  {s} →", .{name});
                for (info.depends_on.items, 0..) |dep, i| {
                    if (i > 0) try w.writeAll(", ");
                    // Remove .sql extension for display
                    const dep_base = if (dep.len > 4 and std.mem.eql(u8, dep[dep.len - 4 ..], ".sql"))
                        dep[0 .. dep.len - 4]
                    else
                        dep;
                    try w.writeAll(dep_base);
                }
                try w.writeAll("\n");
            }
        }
    }

    try w.flush();
    return try aw.toOwnedSlice();
}
