const std = @import("std");
const rc = @import("codegen.zig");
const sp = @import("../parser/sql_parser.zig");
const ReverseCodegen = rc.ReverseCodegen;

const testing = std.testing;

test "ReverseCodegen basic generate" {
    const alloc = testing.allocator;
    const schema = sp.SqlSchema{
        .name = "testdb",
        .charset = "utf8mb4",
        .tables = &.{
            .{
                .name = "users",
                .engine = null,
                .charset = null,
                .comment = null,
                .columns = &.{
                    .{ .name = "id", .type_sql = "INTEGER", .nullable = false, .unsigned = false, .auto_increment = true, .primary_key = true, .on_update_current_timestamp = false, .default_val = null, .check_expr = null, .comment = null, .sym_override = "n" },
                    .{ .name = "name", .type_sql = "TEXT", .nullable = false, .unsigned = false, .auto_increment = false, .primary_key = false, .on_update_current_timestamp = false, .default_val = null, .check_expr = null, .comment = null, .sym_override = "s32" },
                },
                .indexes = &.{},
                .foreign_keys = &.{},
                .checks = &.{},
            },
        },
    };
    var rgen = ReverseCodegen.init(alloc, .sqlite);
    const output = try rgen.generate(schema);
    defer alloc.free(output);

    // Should contain schema name
    try testing.expect(std.mem.indexOf(u8, output, "$ testdb") != null);
    // Should contain table definition
    try testing.expect(std.mem.indexOf(u8, output, "# users") != null);
    // Should contain fields with SS types from override
    try testing.expect(std.mem.indexOf(u8, output, "id n++") != null);
    try testing.expect(std.mem.indexOf(u8, output, "name s32") != null);
}
