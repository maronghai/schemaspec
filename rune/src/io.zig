const std = @import("std");

// ─── I/O Helpers ───────────────────────────────────────────────

/// Buffer size for stdin reading.
const STDIN_BUFFER_SIZE = 4096;
/// Buffer size for stdout writing.
const OUTPUT_BUFFER_SIZE = 8192;
/// Sentinel path meaning "read from stdin".
pub const STDIN_PATH = "-";

/// Read all data from stdin. Returns the complete input as a byte slice.
pub fn readStdin(io: std.Io, alloc: std.mem.Allocator) ![]const u8 {
    const stdin_file = std.Io.File.stdin();
    var buf: [STDIN_BUFFER_SIZE]u8 = undefined;
    var r = stdin_file.readerStreaming(io, &buf);
    var result = try std.ArrayList(u8).initCapacity(alloc, STDIN_BUFFER_SIZE);
    r.interface.appendRemainingUnlimited(alloc, &result) catch |e| {
        if (result.items.len == 0) return e;
    };
    return try result.toOwnedSlice(alloc);
}

/// Read a file by path, or stdin if path is "-".
pub fn readFileOrStdin(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.mem.eql(u8, path, STDIN_PATH)) {
        return readStdin(io, alloc);
    }
    return try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
}

/// Write data to a file or stdout. If output_path is null, writes to stdout.
pub fn writeOutput(io: std.Io, data: []const u8, output_path: ?[]const u8, quiet: bool) !void {
    if (output_path) |opath| {
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = opath,
            .data = data,
        });
        if (!quiet) {
            std.debug.print("Written to {s}\n", .{opath});
        }
    } else {
        var buf: [OUTPUT_BUFFER_SIZE]u8 = undefined;
        const stdout_file = std.Io.File.stdout();
        var w = stdout_file.writer(io, &buf);
        try w.interface.writeAll(data);
        try w.flush();
    }
}
