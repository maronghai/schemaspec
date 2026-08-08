const std = @import("std");

// ─── JSON Utilities ────────────────────────────────────────────
// Low-level JSON serialization helpers for LSP protocol.
// Extracted from protocol.zig for single-responsibility.

/// Write a JSON string value, escaping special characters.
pub fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}

/// Write a JSON integer field.
pub fn writeJsonInt(w: anytype, key: []const u8, value: anytype) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try w.print("{d}", .{value});
}

/// Write a JSON string field.
pub fn writeJsonField(w: anytype, key: []const u8, value: []const u8) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try writeJsonString(w, value);
}

/// Write a JSON bool field.
pub fn writeJsonBool(w: anytype, key: []const u8, value: bool) !void {
    try writeJsonString(w, key);
    try w.writeByte(':');
    try w.writeAll(if (value) "true" else "false");
}

/// Write a JSON null field.
pub fn writeJsonNull(w: anytype, key: []const u8) !void {
    try writeJsonString(w, key);
    try w.writeAll(":null");
}

/// Generic JSON value writer.
pub fn writeJsonValue(w: anytype, val: anytype) !void {
    const T = @TypeOf(val);
    if (T == std.json.Value) {
        switch (val) {
            .null => try w.writeAll("null"),
            .bool => |b| try w.writeAll(if (b) "true" else "false"),
            .integer => |n| try w.print("{d}", .{n}),
            .float => |f| try w.print("{d}", .{f}),
            .number_string => |s| try w.writeAll(s),
            .string => |s| try writeJsonString(w, s),
            .array => |arr| {
                try w.writeByte('[');
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try w.writeByte(',');
                    try writeJsonValue(w, item);
                }
                try w.writeByte(']');
            },
            .object => |obj| {
                try w.writeByte('{');
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try w.writeByte(',');
                    first = false;
                    try writeJsonString(w, entry.key_ptr.*);
                    try w.writeByte(':');
                    try writeJsonValue(w, entry.value_ptr.*);
                }
                try w.writeByte('}');
            },
        }
    } else if (T == []const u8) {
        try writeJsonString(w, val);
    } else if (T == bool) {
        try w.writeAll(if (val) "true" else "false");
    } else if (comptime std.meta.fields(T).len == 0) {
        try w.writeAll("{}");
    } else if (comptime std.meta.fields(T).len > 0) {
        try w.writeByte('{');
        var first = true;
        inline for (std.meta.fields(T)) |field| {
            const field_val = @field(val, field.name);
            const FieldType = @TypeOf(field_val);
            if (comptime comptime_is_optional(FieldType)) {
                if (field_val == null) continue;
            }
            if (!first) try w.writeByte(',');
            first = false;
            try writeJsonString(w, field.name);
            try w.writeByte(':');
            try writeJsonValue(w, field_val);
        }
        try w.writeByte('}');
    } else if (T == comptime_int or T == i64 or T == u64 or T == i32 or T == u32) {
        try w.print("{d}", .{val});
    } else {
        // Fallback: skip unsupported types
    }
}

/// Check if a type is an optional type at comptime.
fn comptime_is_optional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

// ─── Tests ─────────────────────────────────────────────────────

test "writeJsonString" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonString(&aw.writer, "hello");
    try std.testing.expectEqualStrings("\"hello\"", aw.written());

    aw.clearRetainingCapacity();
    try writeJsonString(&aw.writer, "say \"hi\"");
    try std.testing.expectEqualStrings("\"say \\\"hi\\\"\"", aw.written());
}

test "writeJsonField" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonField(&aw.writer, "method", "initialize");
    try std.testing.expectEqualStrings("\"method\":\"initialize\"", aw.written());
}

test "writeJsonBool" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonBool(&aw.writer, "ok", true);
    try std.testing.expectEqualStrings("\"ok\":true", aw.written());
}

test "writeJsonNull" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    try writeJsonNull(&aw.writer, "val");
    try std.testing.expectEqualStrings("\"val\":null", aw.written());
}
