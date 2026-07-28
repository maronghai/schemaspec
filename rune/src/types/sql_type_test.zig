const std = @import("std");
const st = @import("sql_type.zig");
const SqlType = st.SqlType;

const testing = std.testing;

test "SqlType basic roundtrip" {
    const int_type: SqlType = .int;
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try int_type.toSql(.mysql, &aw.writer);
    const result = try aw.toOwnedSlice();
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("int", result);
}
