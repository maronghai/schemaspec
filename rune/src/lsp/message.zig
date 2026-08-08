const std = @import("std");

// ─── JSON-RPC Message Handling ─────────────────────────────────
// Parsing, cloning, and field extraction for JSON-RPC 2.0 messages.
// Extracted from protocol.zig for single-responsibility.

pub const ErrorCode = struct {
    pub const parse_error: i32 = -32700;
    pub const invalid_request: i32 = -32600;
    pub const method_not_found: i32 = -32601;
    pub const invalid_params: i32 = -32602;
    pub const internal_error: i32 = -32603;
};

pub const ParsedMessage = struct {
    id: ?i64,
    method: ?[]const u8,
    params: ?std.json.Value,
    result: ?std.json.Value,
    error_obj: ?JsonRpcError,
    is_response: bool,

    pub const JsonRpcError = struct {
        code: i32,
        message: []const u8,
    };

    /// Free all allocations owned by this message.
    pub fn deinit(self: *ParsedMessage, alloc: std.mem.Allocator) void {
        if (self.method) |m| alloc.free(m);
        if (self.params) |p| freeJsonValue(alloc, p);
        if (self.result) |r| freeJsonValue(alloc, r);
        if (self.error_obj) |e| alloc.free(e.message);
    }
};

/// Parse a JSON-RPC message from a JSON string.
/// Caller must free the returned ParsedMessage's allocations.
pub fn parseMessage(alloc: std.mem.Allocator, json_str: []const u8) !ParsedMessage {
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_str, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidMessage;

    const obj = root.object;

    const id: ?i64 = if (obj.get("id")) |v| switch (v) {
        .integer => |n| @intCast(n),
        .float => @intFromFloat(v.float),
        else => null,
    } else null;

    const method: ?[]const u8 = if (obj.get("method")) |v| switch (v) {
        .string => |s| try alloc.dupe(u8, s),
        else => null,
    } else null;

    const params: ?std.json.Value = if (obj.get("params")) |v| try cloneValue(alloc, v) else null;

    const result: ?std.json.Value = if (obj.get("result")) |v| try cloneValue(alloc, v) else null;

    const error_obj: ?ParsedMessage.JsonRpcError = if (obj.get("error")) |err_val| switch (err_val) {
        .object => |err_obj| .{
            .code = if (err_obj.get("code")) |c| switch (c) {
                .integer => @intCast(c.integer),
                else => ErrorCode.internal_error,
            } else ErrorCode.internal_error,
            .message = if (err_obj.get("message")) |m| switch (m) {
                .string => |s| try alloc.dupe(u8, s),
                else => "Unknown error",
            } else "Unknown error",
        },
        else => null,
    } else null;

    return .{
        .id = id,
        .method = method,
        .params = params,
        .result = result,
        .error_obj = error_obj,
        .is_response = obj.get("method") == null,
    };
}

/// Clone a JSON value into a new allocation.
fn cloneValue(alloc: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    return switch (val) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |n| .{ .integer = n },
        .float => |f| .{ .float = f },
        .string => |s| .{ .string = try alloc.dupe(u8, s) },
        .number_string => |s| .{ .number_string = try alloc.dupe(u8, s) },
        .array => |arr| {
            var new_arr = std.json.Array.init(alloc);
            for (arr.items) |item| {
                try new_arr.append(try cloneValue(alloc, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj: std.json.ObjectMap = .empty;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key = try alloc.dupe(u8, entry.key_ptr.*);
                const val_copy = try cloneValue(alloc, entry.value_ptr.*);
                try new_obj.put(alloc, key, val_copy);
            }
            return .{ .object = new_obj };
        },
    };
}

/// Free a cloned JSON value and all its children.
pub fn freeJsonValue(alloc: std.mem.Allocator, val: std.json.Value) void {
    switch (val) {
        .null, .bool, .integer, .float => {},
        .string => |s| alloc.free(s),
        .number_string => |s| alloc.free(s),
        .array => |arr| {
            for (arr.items) |item| freeJsonValue(alloc, item);
            arr.deinit();
        },
        .object => {
            var obj = val.object;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                alloc.free(entry.key_ptr.*);
                freeJsonValue(alloc, entry.value_ptr.*);
            }
            obj.deinit(alloc);
        },
    }
}

/// Extract a string field from a JSON object value.
pub fn getStringField(obj: std.json.Value, key: []const u8) ?[]const u8 {
    if (obj != .object) return null;
    if (obj.object.get(key)) |v| {
        if (v == .string) return v.string;
    }
    return null;
}

/// Extract an integer field from a JSON object value.
pub fn getIntField(obj: std.json.Value, key: []const u8) ?i64 {
    if (obj != .object) return null;
    if (obj.object.get(key)) |v| {
        if (v == .integer) return v.integer;
    }
    return null;
}

/// Get a nested object field.
pub fn getObjectField(obj: std.json.Value, key: []const u8) ?std.json.Value {
    if (obj != .object) return null;
    return obj.object.get(key);
}

// ─── Tests ─────────────────────────────────────────────────────

test "parseMessage request" {
    var msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    );
    defer msg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?i64, 1), msg.id);
    try std.testing.expect(msg.method != null);
    try std.testing.expectEqualStrings("initialize", msg.method.?);
    try std.testing.expect(!msg.is_response);
}

test "parseMessage response" {
    var msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}
    );
    defer msg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?i64, 1), msg.id);
    try std.testing.expect(msg.is_response);
    try std.testing.expect(msg.result != null);
}

test "parseMessage notification" {
    var msg = try parseMessage(std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{}}
    );
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg.id == null);
    try std.testing.expect(msg.method != null);
    try std.testing.expectEqualStrings("textDocument/didOpen", msg.method.?);
    try std.testing.expect(!msg.is_response);
}
