const std = @import("std");
const typed_ast = @import("types/typed_ast.zig");
const dialect_enum = @import("dialect/enum.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ─── Incremental Compilation Cache ─────────────────────────────
// Table-level content hash cache for streaming compilation.
// Cache key = table_name + dialect + content_hash (from resolved columns/FKs/indexes).
// Cache stored in .rune-cache/ directory as individual .sql files.
// Opt-in via --cache flag; disabled by default.

/// Cache key for a single table's compiled SQL.
pub const CacheKey = struct {
    table_name: []const u8,
    dialect: []const u8,
    content_hash: [64]u8, // hex-encoded SHA-256

    /// Format as cache file name: `<hex_hash>.sql`
    pub fn fileName(self: CacheKey, buf: *[68]u8) void {
        @memcpy(buf[0..64], &self.content_hash);
        buf[64] = '.';
        buf[65] = 's';
        buf[66] = 'q';
        buf[67] = 'l';
    }
};

/// A single cached table entry.
pub const CacheEntry = struct {
    key: CacheKey,
    sql: []const u8,
};

/// Table-level compilation cache.
/// Stores generated SQL keyed by (table_name, dialect, content_hash).
/// Thread-safe for single-threaded use (streaming compilation path).
pub const TableCache = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    entries: std.StringHashMapUnmanaged(CacheEntry),
    cache_dir: ?[]const u8,
    hit_count: u32,
    miss_count: u32,

    pub fn init(alloc: std.mem.Allocator, io: std.Io) TableCache {
        return .{
            .alloc = alloc,
            .io = io,
            .entries = .{},
            .cache_dir = null,
            .hit_count = 0,
            .miss_count = 0,
        };
    }

    pub fn deinit(self: *TableCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.value_ptr.*.sql);
        }
        self.entries.deinit(self.alloc);
    }

    /// Compute content hash for a TypedTable.
    /// The hash captures columns, FKs, and indexes — everything that affects generated SQL.
    /// Template inheritance is handled naturally: after resolution, TypedTable has resolved fields.
    pub fn computeTableHash(table: typed_ast.TypedTable, dialect: []const u8) CacheKey {
        var hasher = Sha256.init(.{});

        // Hash table name
        hasher.update(table.name);

        // Hash dialect
        hasher.update(dialect);

        // Hash columns
        for (table.columns) |col| {
            hasher.update(col.name);
            hasher.update(@tagName(col.sql_type));
            const flags_bytes = std.mem.asBytes(&col.flags);
            hasher.update(flags_bytes);
            if (col.default) |d| hasher.update(d);
            if (col.check) |c| {
                hasher.update(c.expr);
            }
            for (col.enum_values) |ev| {
                hasher.update(ev);
            }
            if (col.generated_expr) |ge| {
                hasher.update(ge);
            }
        }

        // Hash foreign keys
        for (table.fks) |fk| {
            for (fk.fields) |f| hasher.update(f);
            hasher.update(fk.ref_table);
            for (fk.ref_fields) |rf| hasher.update(rf);
            for (fk.actions) |action| {
                hasher.update(@tagName(action.trigger));
                hasher.update(@tagName(action.action));
            }
        }

        // Hash indexes
        for (table.indexes) |idx| {
            hasher.update(idx.name);
            for (idx.fields) |c| hasher.update(c);
            hasher.update(@tagName(idx.kind));
        }

        // Hash engine
        if (table.engine) |e| hasher.update(e);

        var digest: [32]u8 = undefined;
        hasher.final(&digest);

        // Hex-encode the digest manually
        const hex_chars = "0123456789abcdef";
        var hex: [64]u8 = undefined;
        for (digest, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        return .{
            .table_name = table.name,
            .dialect = dialect,
            .content_hash = hex,
        };
    }

    /// Look up a table in the in-memory cache.
    /// Returns cached SQL if found, null otherwise.
    pub fn lookup(self: *TableCache, key: CacheKey) ?[]const u8 {
        const entry = self.entries.get(key.table_name) orelse {
            self.miss_count += 1;
            return null;
        };
        if (std.mem.eql(u8, &entry.key.content_hash, &key.content_hash) and std.mem.eql(u8, entry.key.dialect, key.dialect)) {
            self.hit_count += 1;
            return entry.sql;
        }
        self.miss_count += 1;
        return null;
    }

    /// Store a table's SQL in the in-memory cache.
    pub fn store(self: *TableCache, key: CacheKey, sql: []const u8) !void {
        const owned_sql = try self.alloc.dupe(u8, sql);
        const gop = try self.entries.getOrPut(self.alloc, key.table_name);
        if (gop.found_existing) {
            self.alloc.free(gop.value_ptr.sql);
        }
        gop.value_ptr.* = .{
            .key = key,
            .sql = owned_sql,
        };
    }

    /// Write all cached entries to disk.
    /// Creates `.rune-cache/<dialect>/` directories and writes each entry as `<hash>.sql`.
    /// Writes a manifest file (`manifest.json`) for fast lookup on load.
    /// Uses atomic writes (write to temp, then rename) for crash safety.
    pub fn flushToDisk(self: *TableCache) void {
        const dir = self.cache_dir orelse return;

        // Ensure cache directory exists
        std.Io.Dir.cwd().createDir(self.io, dir, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return;
        };

        // Write each entry to disk
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.writeEntryToDisk(dir, entry.value_ptr) catch continue;
        }

        // Write manifest file for fast lookup
        self.writeManifest(dir) catch {};
    }

    /// Write a single cache entry to disk as `<hash>.sql`.
    fn writeEntryToDisk(self: *TableCache, dir: []const u8, entry: *const CacheEntry) !void {
        // Ensure dialect subdirectory exists
        var dialect_buf: [256]u8 = undefined;
        const dialect_path = std.fmt.bufPrint(&dialect_buf, "{s}/{s}", .{ dir, entry.key.dialect }) catch return;
        std.Io.Dir.cwd().createDir(self.io, dialect_path, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return;
        };

        // Build file path: <dir>/<dialect>/<hash>.sql
        var file_buf: [68]u8 = undefined;
        entry.key.fileName(&file_buf);
        const file_path = std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ dialect_path, &file_buf }) catch return;
        defer self.alloc.free(file_path);

        // Write to temp file, then rename for atomicity
        const tmp_path = std.fmt.allocPrint(self.alloc, "{s}.tmp", .{file_path}) catch return;
        defer self.alloc.free(tmp_path);

        {
            const file = std.Io.Dir.cwd().createFile(self.io, tmp_path, .{}) catch return;
            defer file.close(self.io);
            file.writeStreamingAll(self.io, entry.sql) catch return;
        }
        std.Io.Dir.renameAbsolute(tmp_path, file_path, self.io) catch {};
    }

    /// Write manifest file mapping table_name → {dialect, hash} for fast lookup.
    fn writeManifest(self: *TableCache, dir: []const u8) !void {
        var buf = std.ArrayList(u8).initCapacity(self.alloc, 4096) catch return;
        defer buf.deinit(self.alloc);

        try buf.appendSlice(self.alloc, "{\"entries\":{");

        var first = true;
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(self.alloc, ",");
            first = false;

            // Escape table name for JSON
            try buf.append(self.alloc, '"');
            for (entry.value_ptr.*.key.table_name) |c| {
                if (c == '"') {
                    try buf.appendSlice(self.alloc, "\\\"");
                } else if (c == '\\') {
                    try buf.appendSlice(self.alloc, "\\\\");
                } else {
                    try buf.append(self.alloc, c);
                }
            }
            try buf.appendSlice(self.alloc, "\":{\"dialect\":\"");
            try buf.appendSlice(self.alloc, entry.value_ptr.*.key.dialect);
            try buf.appendSlice(self.alloc, "\",\"hash\":\"");
            try buf.appendSlice(self.alloc, &entry.value_ptr.*.key.content_hash);
            try buf.appendSlice(self.alloc, "\"}");
        }

        try buf.appendSlice(self.alloc, "}}");

        // Write manifest atomically
        var manifest_buf: [512]u8 = undefined;
        const manifest_path = std.fmt.bufPrint(&manifest_buf, "{s}/manifest.json", .{dir}) catch return;
        const tmp_path = std.fmt.bufPrint(&manifest_buf, "{s}/manifest.json.tmp", .{dir}) catch return;

        {
            const file = std.Io.Dir.cwd().createFile(self.io, tmp_path, .{}) catch return;
            defer file.close(self.io);
            file.writeStreamingAll(self.io, buf.items) catch return;
        }
        std.Io.Dir.renameAbsolute(tmp_path, manifest_path, self.io) catch {};
    }

    /// Load cache entries from disk into memory.
    /// Reads the manifest file to find entries, then loads each .sql file.
    pub fn loadFromDisk(self: *TableCache, dir: []const u8) void {
        self.cache_dir = dir;

        // Read manifest file
        const manifest_path = std.fmt.allocPrint(self.alloc, "{s}/manifest.json", .{dir}) catch return;
        defer self.alloc.free(manifest_path);

        const content = std.Io.Dir.cwd().readFileAlloc(self.io, manifest_path, self.alloc, .unlimited) catch return;
        defer self.alloc.free(content);

        // Parse simple JSON manifest: {"entries":{"table":{"dialect":"mysql","hash":"abc..."}}}
        // Simple parser — doesn't need full JSON library
        var pos: usize = 0;
        while (pos < content.len) {
            // Find table name (key in outer object)
            if (findJsonString(content, &pos)) |table_name| {
                // Skip : and {
                skipToChar(content, &pos, ':');
                skipToChar(content, &pos, '{');

                // Find dialect
                if (findJsonString(content, &pos)) |dialect| {
                    // Skip : and "
                    skipToChar(content, &pos, ':');
                    skipToChar(content, &pos, '"');

                    // Find hash value
                    if (readJsonValue(content, &pos)) |hash| {
                        // Build file path and load SQL
                        var file_buf: [68]u8 = undefined;
                        var hash_bytes: [64]u8 = undefined;
                        const hash_len = @min(hash.len, 64);
                        @memcpy(hash_bytes[0..hash_len], hash[0..hash_len]);
                        if (hash_len < 64) {
                            @memset(hash_bytes[hash_len..64], '0');
                        }

                        const key = CacheKey{
                            .table_name = table_name,
                            .dialect = dialect,
                            .content_hash = hash_bytes,
                        };
                        key.fileName(&file_buf);

                        var dialect_buf: [256]u8 = undefined;
                        const dialect_path = std.fmt.bufPrint(&dialect_buf, "{s}/{s}", .{ dir, dialect }) catch continue;
                        const file_path = std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ dialect_path, &file_buf }) catch continue;
                        defer self.alloc.free(file_path);

                        const sql = std.Io.Dir.cwd().readFileAlloc(self.io, file_path, self.alloc, .unlimited) catch continue;
                        _ = self.store(key, sql) catch continue;
                    }
                }
            } else {
                break;
            }
        }
    }

    /// Helper: find next JSON string value starting at pos. Returns slice of string content.
    fn findJsonString(content: []const u8, pos: *usize) ?[]const u8 {
        // Skip to next quote
        while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
        if (pos.* >= content.len) return null;
        pos.* += 1; // skip opening quote

        const start = pos.*;
        while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
        if (pos.* >= content.len) return null;
        const result = content[start..pos.*];
        pos.* += 1; // skip closing quote
        return result;
    }

    /// Helper: skip to next occurrence of char.
    fn skipToChar(content: []const u8, pos: *usize, c: u8) void {
        while (pos.* < content.len and content[pos.*] != c) : (pos.* += 1) {}
        if (pos.* < content.len) pos.* += 1;
    }

    /// Helper: read a JSON string value (after opening quote).
    fn readJsonValue(content: []const u8, pos: *usize) ?[]const u8 {
        return findJsonString(content, pos);
    }

    /// Remove the cache directory and all its contents, then clear in-memory state.
    pub fn clean(self: *TableCache) void {
        if (self.cache_dir) |dir| {
            // Remove all .sql files we know about
            var it = self.entries.iterator();
            while (it.next()) |entry| {
                var file_buf: [68]u8 = undefined;
                entry.value_ptr.*.key.fileName(&file_buf);
                var dialect_buf: [256]u8 = undefined;
                const dialect_path = std.fmt.bufPrint(&dialect_buf, "{s}/{s}", .{ dir, entry.value_ptr.*.key.dialect }) catch continue;
                const file_path = std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ dialect_path, &file_buf }) catch continue;
                defer self.alloc.free(file_path);
                std.Io.Dir.cwd().deleteFile(self.io, file_path) catch {};
            }
            // Remove manifest
            const manifest_path = std.fmt.allocPrint(self.alloc, "{s}/manifest.json", .{dir}) catch null;
            if (manifest_path) |mp| {
                defer self.alloc.free(mp);
                std.Io.Dir.cwd().deleteFile(self.io, mp) catch {};
            }
            // Remove dialect subdirectories (will fail if non-empty, which is fine)
            var it2 = self.entries.iterator();
            var seen_dirs = std.BufSet.init(self.alloc);
            defer seen_dirs.deinit();
            while (it2.next()) |entry| {
                var dialect_buf: [256]u8 = undefined;
                const dialect_path = std.fmt.bufPrint(&dialect_buf, "{s}/{s}", .{ dir, entry.value_ptr.*.key.dialect }) catch continue;
                if (!seen_dirs.contains(dialect_path)) {
                    seen_dirs.insert(dialect_path) catch {};
                    std.Io.Dir.cwd().deleteDir(self.io, dialect_path) catch {};
                }
            }
            // Remove root cache dir
            std.Io.Dir.cwd().deleteDir(self.io, dir) catch {};
        }
        self.entries.clearRetainingCapacity();
        self.hit_count = 0;
        self.miss_count = 0;
    }

    /// Return cache statistics.
    pub fn stats(self: *const TableCache) CacheStats {
        return .{
            .entries = self.entries.count(),
            .hits = self.hit_count,
            .misses = self.miss_count,
        };
    }
};

/// Cache performance statistics.
pub const CacheStats = struct {
    entries: u32,
    hits: u32,
    misses: u32,

    pub fn format(self: CacheStats, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("cache: {d} entries, {d} hits, {d} misses", .{ self.entries, self.hits, self.misses });
    }
};

// ─── Tests ─────────────────────────────────────────────────────

/// Helper: create a CacheKey with a short hash prefix, zero-padded to 64 chars.
fn testKey(table_name: []const u8, dialect: []const u8, hash_prefix: []const u8) CacheKey {
    var hash: [64]u8 = [_]u8{0} ** 64;
    @memcpy(hash[0..@min(hash_prefix.len, 64)], hash_prefix[0..@min(hash_prefix.len, 64)]);
    return .{
        .table_name = table_name,
        .dialect = dialect,
        .content_hash = hash,
    };
}

test "computeTableHash produces stable hash" {
    const table = typed_ast.TypedTable{
        .name = "users",
        .comment = null,
        .doc = null,
        .engine = null,
        .columns = &.{
            .{
                .name = "id",
                .doc = null,
                .sql_type = .int,
                .ss_symbol = null,
                .flags = .{ .primary_key = true, .auto_increment = true },
                .default = null,
                .check = null,
                .comment = null,
                .enum_values = &.{},
                .generated_expr = null,
                .line_no = 1,
            },
            .{
                .name = "name",
                .doc = null,
                .sql_type = .{ .varchar = 255 },
                .ss_symbol = null,
                .flags = .{},
                .default = null,
                .check = null,
                .comment = null,
                .enum_values = &.{},
                .generated_expr = null,
                .line_no = 2,
            },
        },
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };

    const key1 = TableCache.computeTableHash(table, "mysql");
    const key2 = TableCache.computeTableHash(table, "mysql");
    const key3 = TableCache.computeTableHash(table, "pg");

    // Same input → same hash
    try std.testing.expectEqualStrings(&key1.content_hash, &key2.content_hash);
    // Different dialect → different hash
    try std.testing.expect(!std.mem.eql(u8, &key1.content_hash, &key3.content_hash));
}

test "lookup returns cached SQL" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    try cache.store(key, "CREATE TABLE users (id INT PRIMARY KEY);");
    const result = cache.lookup(key);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("CREATE TABLE users (id INT PRIMARY KEY);", result.?);
}

test "lookup returns null for cache miss" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    const result = cache.lookup(key);
    try std.testing.expect(result == null);
}

test "lookup returns null for different dialect" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key_mysql = testKey("users", "mysql", "aaa");
    const key_pg = testKey("users", "pg", "aaa");

    try cache.store(key_mysql, "SQL for mysql");
    const result = cache.lookup(key_pg);
    try std.testing.expect(result == null);
}

test "lookup returns null for different content hash" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key1 = testKey("users", "mysql", "aaa");
    const key2 = testKey("users", "mysql", "bbb");

    try cache.store(key1, "SQL v1");
    const result = cache.lookup(key2);
    try std.testing.expect(result == null);
}

test "stats tracks hits and misses" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    _ = cache.lookup(key); // miss
    _ = cache.lookup(key); // miss
    try cache.store(key, "SQL");
    _ = cache.lookup(key); // hit

    const s = cache.stats();
    try std.testing.expectEqual(@as(u32, 1), s.hits);
    try std.testing.expectEqual(@as(u32, 2), s.misses);
    try std.testing.expectEqual(@as(u32, 1), s.entries);
}

test "cacheKey fileName formats correctly" {
    const key = CacheKey{
        .table_name = "users",
        .dialect = "mysql",
        .content_hash = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789".*,
    };
    var buf: [68]u8 = undefined;
    key.fileName(&buf);
    try std.testing.expectEqualStrings("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789.sql", &buf);
}

test "store replaces existing entry" {
    const io = std.Io{ .vtable = undefined, .userdata = undefined };
    var cache = TableCache.init(std.testing.allocator, io);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    try cache.store(key, "SQL v1");
    try cache.store(key, "SQL v2");

    const result = cache.lookup(key);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("SQL v2", result.?);
    try std.testing.expectEqual(@as(u32, 1), cache.stats().entries);
}
