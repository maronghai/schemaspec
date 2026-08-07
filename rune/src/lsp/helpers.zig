const protocol = @import("protocol.zig");
const Range = protocol.Range;

pub fn makeRange(start_line: u32, start_char: u32, end_line: u32, end_char: u32) Range {
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };
}
