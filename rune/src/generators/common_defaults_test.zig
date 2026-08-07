const std = @import("std");
const common_defaults = @import("common_defaults.zig");

test "writeFormattedDefault: boolean true" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "true", fmt);
    try std.testing.expectEqualStrings("true", aw.written());
}

test "writeFormattedDefault: boolean TRUE" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "TRUE", fmt);
    try std.testing.expectEqualStrings("true", aw.written());
}

test "writeFormattedDefault: boolean false" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "false", fmt);
    try std.testing.expectEqualStrings("false", aw.written());
}

test "writeFormattedDefault: null" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "null", fmt);
    try std.testing.expectEqualStrings("null", aw.written());
}

test "writeFormattedDefault: NULL" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "NULL", fmt);
    try std.testing.expectEqualStrings("null", aw.written());
}

test "writeFormattedDefault: NOW()" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "NOW()", fmt);
    try std.testing.expectEqualStrings("new Date()", aw.written());
}

test "writeFormattedDefault: integer" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "42", fmt);
    try std.testing.expectEqualStrings("42", aw.written());
}

test "writeFormattedDefault: string fallback" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "'hello'", fmt);
    try std.testing.expectEqualStrings("'hello'", aw.written());
}

test "getOrmFormatter: drizzle NOW" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try fmt.now(&aw.writer);
    try std.testing.expectEqualStrings("new Date()", aw.written());
}

test "getOrmFormatter: knex NOW" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.knex);
    try fmt.now(&aw.writer);
    try std.testing.expectEqualStrings("knex.fn.now()", aw.written());
}

test "getOrmFormatter: sqlalchemy NULL" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.sqlalchemy);
    try fmt.nullValue(&aw.writer);
    try std.testing.expectEqualStrings("None", aw.written());
}

test "getOrmFormatter: sqlalchemy bool true" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.sqlalchemy);
    try fmt.boolTrue(&aw.writer);
    try std.testing.expectEqualStrings("'true'", aw.written());
}

test "getOrmFormatter: typeorm NOW" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.typeorm);
    try fmt.now(&aw.writer);
    try std.testing.expectEqualStrings("() => new Date()", aw.written());
}

test "writeFormattedDefault: CURRENT_TIMESTAMP" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "CURRENT_TIMESTAMP", fmt);
    try std.testing.expectEqualStrings("new Date()", aw.written());
}

test "writeFormattedDefault: float" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer aw.deinit();

    const fmt = common_defaults.getOrmFormatter(.drizzle);
    try common_defaults.writeFormattedDefault(&aw.writer, "3.14", fmt);
    try std.testing.expectEqualStrings("3.14", aw.written());
}
