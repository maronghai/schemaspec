const std = @import("std");

// ─── Document Manager ──────────────────────────────────────────
// Tracks open text documents in the LSP session.
// Each document is identified by its URI and has a version number
// that increments on each change.

pub const DocumentState = struct {
    uri: []const u8,
    version: u32,
    text: []const u8,
    language_id: []const u8,
};

pub const DocumentManager = struct {
    alloc: std.mem.Allocator,
    documents: std.StringHashMap(DocumentState),

    pub fn init(alloc: std.mem.Allocator) DocumentManager {
        return .{
            .alloc = alloc,
            .documents = std.StringHashMap(DocumentState).init(alloc),
        };
    }

    pub fn deinit(self: *DocumentManager) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*.text);
            self.alloc.free(entry.value_ptr.*.language_id);
        }
        self.documents.deinit();
    }

    /// Open a document. If already open, replaces its content.
    pub fn open(self: *DocumentManager, uri: []const u8, version: u32, text: []const u8, language_id: []const u8) !void {
        const owned_uri = try self.alloc.dupe(u8, uri);
        const owned_text = try self.alloc.dupe(u8, text);
        const owned_lang = try self.alloc.dupe(u8, language_id);

        // If already open, free old content and the duplicate URI
        if (self.documents.getEntry(owned_uri)) |entry| {
            self.alloc.free(owned_uri);
            self.alloc.free(entry.value_ptr.*.text);
            self.alloc.free(entry.value_ptr.*.language_id);
            entry.value_ptr.* = .{
                .uri = entry.key_ptr.*,
                .version = version,
                .text = owned_text,
                .language_id = owned_lang,
            };
        } else {
            try self.documents.put(owned_uri, .{
                .uri = owned_uri,
                .version = version,
                .text = owned_text,
                .language_id = owned_lang,
            });
        }
    }

    /// Update a document's content (full sync).
    pub fn change(self: *DocumentManager, uri: []const u8, version: u32, text: []const u8) !void {
        if (self.documents.getEntry(uri)) |entry| {
            self.alloc.free(entry.value_ptr.*.text);
            entry.value_ptr.*.text = try self.alloc.dupe(u8, text);
            entry.value_ptr.*.version = version;
        }
    }

    /// Close a document.
    pub fn close(self: *DocumentManager, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |kv| {
            self.alloc.free(kv.key);
            self.alloc.free(kv.value.text);
            self.alloc.free(kv.value.language_id);
        }
    }

    /// Get a document by URI.
    pub fn get(self: *const DocumentManager, uri: []const u8) ?DocumentState {
        return self.documents.get(uri);
    }

    /// Get the file path from a file:// URI.
    pub fn uriToPath(self: *const DocumentManager, uri: []const u8) ![]const u8 {
        const prefix = "file://";
        if (std.mem.startsWith(u8, uri, prefix)) {
            return try self.alloc.dupe(u8, uri[prefix.len..]);
        }
        return try self.alloc.dupe(u8, uri);
    }

    /// Get the number of open documents.
    pub fn count(self: *const DocumentManager) usize {
        return self.documents.count();
    }
};

// ─── Tests ─────────────────────────────────────────────────────

test "DocumentManager open and get" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try dm.open("file:///test.ss", 1, "table users { id n }", "rune");
    const doc = dm.get("file:///test.ss");
    try std.testing.expect(doc != null);
    try std.testing.expectEqual(@as(u32, 1), doc.?.version);
    try std.testing.expectEqualStrings("table users { id n }", doc.?.text);
    try std.testing.expectEqualStrings("rune", doc.?.language_id);
}

test "DocumentManager change" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try dm.open("file:///test.ss", 1, "old content", "rune");
    try dm.change("file:///test.ss", 2, "new content");

    const doc = dm.get("file:///test.ss");
    try std.testing.expect(doc != null);
    try std.testing.expectEqual(@as(u32, 2), doc.?.version);
    try std.testing.expectEqualStrings("new content", doc.?.text);
}

test "DocumentManager close" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try dm.open("file:///test.ss", 1, "content", "rune");
    try std.testing.expectEqual(@as(usize, 1), dm.count());

    dm.close("file:///test.ss");
    try std.testing.expectEqual(@as(usize, 0), dm.count());
    try std.testing.expect(dm.get("file:///test.ss") == null);
}

test "DocumentManager replace on reopen" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try dm.open("file:///test.ss", 1, "first", "rune");
    try dm.open("file:///test.ss", 2, "second", "text");

    const doc = dm.get("file:///test.ss");
    try std.testing.expect(doc != null);
    try std.testing.expectEqual(@as(u32, 2), doc.?.version);
    try std.testing.expectEqualStrings("second", doc.?.text);
    try std.testing.expectEqualStrings("text", doc.?.language_id);
}

test "DocumentManager multiple documents" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try dm.open("file:///a.ss", 1, "a content", "rune");
    try dm.open("file:///b.ss", 1, "b content", "rune");
    try std.testing.expectEqual(@as(usize, 2), dm.count());

    dm.close("file:///a.ss");
    try std.testing.expectEqual(@as(usize, 1), dm.count());
    try std.testing.expect(dm.get("file:///a.ss") == null);
    try std.testing.expect(dm.get("file:///b.ss") != null);
}

test "DocumentManager uriToPath" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    const path = try dm.uriToPath("file:///home/user/schema.ss");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/user/schema.ss", path);
}

test "DocumentManager count" {
    var dm = DocumentManager.init(std.testing.allocator);
    defer dm.deinit();

    try std.testing.expectEqual(@as(usize, 0), dm.count());
    try dm.open("file:///a.ss", 1, "", "rune");
    try std.testing.expectEqual(@as(usize, 1), dm.count());
    try dm.open("file:///b.ss", 1, "", "rune");
    try std.testing.expectEqual(@as(usize, 2), dm.count());
    dm.close("file:///a.ss");
    try std.testing.expectEqual(@as(usize, 1), dm.count());
}
