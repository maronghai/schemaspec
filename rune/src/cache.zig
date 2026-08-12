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
    entries: std.StringHashMapUnmanaged(CacheEntry),
    cache_dir: ?[]const u8,
    hit_count: u32,
    miss_count: u32,

    pub fn init(alloc: std.mem.Allocator) TableCache {
        return .{
            .alloc = alloc,
            .entries = .{},
            .cache_dir = null,
            .hit_count = 0,
            .miss_count = 0,
        };
    }

    pub fn deinit(self: *TableCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.value_ptr.sql);
        }
        self.entries.deinit(self.alloc);
    }

    /// Enable disk cache in the given directory.
    /// Note: disk persistence is not yet implemented. Cache is in-memory only.
    pub fn enableDiskCache(self: *TableCache, dir: []const u8) !void {
        _ = dir;
        // Disk caching requires IO handle — reserved for future implementation.
        _ = self;
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
    /// Note: disk persistence is not yet implemented. This is a no-op.
    pub fn flushToDisk(self: *TableCache) void {
        _ = self;
    }

    /// Load cache entries from disk into memory.
    /// Note: disk persistence is not yet implemented. This is a no-op.
    pub fn loadFromDisk(self: *TableCache, dir: []const u8) void {
        _ = dir;
        _ = self;
    }

    /// Remove the cache directory and all its contents.
    /// Note: disk persistence is not yet implemented. This clears in-memory state only.
    pub fn clean(self: *TableCache) void {
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
    var cache = TableCache.init(std.testing.allocator);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    try cache.store(key, "CREATE TABLE users (id INT PRIMARY KEY);");
    const result = cache.lookup(key);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("CREATE TABLE users (id INT PRIMARY KEY);", result.?);
}

test "lookup returns null for cache miss" {
    var cache = TableCache.init(std.testing.allocator);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    const result = cache.lookup(key);
    try std.testing.expect(result == null);
}

test "lookup returns null for different dialect" {
    var cache = TableCache.init(std.testing.allocator);
    defer cache.deinit();

    const key_mysql = testKey("users", "mysql", "aaa");
    const key_pg = testKey("users", "pg", "aaa");

    try cache.store(key_mysql, "SQL for mysql");
    const result = cache.lookup(key_pg);
    try std.testing.expect(result == null);
}

test "lookup returns null for different content hash" {
    var cache = TableCache.init(std.testing.allocator);
    defer cache.deinit();

    const key1 = testKey("users", "mysql", "aaa");
    const key2 = testKey("users", "mysql", "bbb");

    try cache.store(key1, "SQL v1");
    const result = cache.lookup(key2);
    try std.testing.expect(result == null);
}

test "stats tracks hits and misses" {
    var cache = TableCache.init(std.testing.allocator);
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
    var cache = TableCache.init(std.testing.allocator);
    defer cache.deinit();

    const key = testKey("users", "mysql", "aaa");

    try cache.store(key, "SQL v1");
    try cache.store(key, "SQL v2");

    const result = cache.lookup(key);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("SQL v2", result.?);
    try std.testing.expectEqual(@as(u32, 1), cache.stats().entries);
}
