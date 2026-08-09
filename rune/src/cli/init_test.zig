const std = @import("std");
const testing = std.testing;
const init_mod = @import("init.zig");

test "getTemplate: default template" {
    const result = init_mod.getTemplate("default");
    try testing.expect(result != null);
    try testing.expect(result.?.len > 0);
}

test "getTemplate: empty string returns default" {
    const result = init_mod.getTemplate("");
    try testing.expect(result != null);
}

test "getTemplate: blog template" {
    const result = init_mod.getTemplate("blog");
    try testing.expect(result != null);
    try testing.expect(result.?.len > 0);
    // Blog should contain categories table
    try testing.expect(std.mem.indexOf(u8, result.?, "categories") != null);
}

test "getTemplate: ecommerce template" {
    const result = init_mod.getTemplate("ecommerce");
    try testing.expect(result != null);
    try testing.expect(result.?.len > 0);
    // Ecommerce should contain products table
    try testing.expect(std.mem.indexOf(u8, result.?, "products") != null);
}

test "getTemplate: rest-api template" {
    const result = init_mod.getTemplate("rest-api");
    try testing.expect(result != null);
    try testing.expect(result.?.len > 0);
    // REST API should contain api_keys table
    try testing.expect(std.mem.indexOf(u8, result.?, "api_keys") != null);
}

test "getTemplate: unknown template returns null" {
    const result = init_mod.getTemplate("nonexistent");
    try testing.expect(result == null);
}

test "STARTER_SCHEMA: contains required tables" {
    const schema = init_mod.STARTER_SCHEMA;
    // Should have users, posts, comments tables
    try testing.expect(std.mem.indexOf(u8, schema, "# users") != null);
    try testing.expect(std.mem.indexOf(u8, schema, "# posts") != null);
    try testing.expect(std.mem.indexOf(u8, schema, "# comments") != null);
}

test "STARTER_SCHEMA: contains FK references" {
    const schema = init_mod.STARTER_SCHEMA;
    // Should have _id suffix columns for FK inference
    try testing.expect(std.mem.indexOf(u8, schema, "author_id") != null);
    try testing.expect(std.mem.indexOf(u8, schema, "post_id") != null);
}
