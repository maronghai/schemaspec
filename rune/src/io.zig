const std = @import("std");

// ─── I/O Helpers ───────────────────────────────────────────────

/// Buffer size for stdin reading.
const STDIN_BUFFER_SIZE = 4096;
/// Buffer size for stdout writing.
const OUTPUT_BUFFER_SIZE = 8192;
/// Sentinel path meaning "read from stdin".
pub const STDIN_PATH = "-";
/// Threshold for using memory-mapped I/O (1MB).
const MMAP_THRESHOLD = 1024 * 1024;

// ─── Memory-Mapped File I/O ─────────────────────────────────────

/// Result of memory-mapped file access.
pub const MmapResult = struct {
    /// Memory-mapped data slice.
    data: []const u8,
    /// File size in bytes.
    size: usize,

    /// Release memory-mapped region.
    pub fn deinit(self: MmapResult) void {
        if (self.data.len > 0) {
            std.posix.munmap(@alignCast(@ptrCast(self.data.ptr)));
        }
    }
};

/// Memory-map a file for efficient large-file access.
/// Caller must call result.deinit() when done.
pub fn mmapFile(path: []const u8) !MmapResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const size = stat.size;

    if (size == 0) {
        return .{ .data = &.{}, .size = 0 };
    }

    const mapped = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    );

    return .{
        .data = mapped,
        .size = size,
    };
}

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
/// For files larger than 1MB, uses memory-mapped I/O for efficiency.
/// For smaller files, uses traditional read.
pub fn readFileOrStdin(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.mem.eql(u8, path, STDIN_PATH)) {
        return readStdin(io, alloc);
    }

    // Check file size to decide between mmap and traditional read
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();

    if (stat.size > MMAP_THRESHOLD) {
        // Use memory-mapped I/O for large files
        const mmap_result = try mmapFile(path);
        // For now, copy to owned slice since callers expect allocated memory
        // Future optimization: use mmap directly throughout the pipeline
        const owned = try alloc.dupe(u8, mmap_result.data);
        mmap_result.deinit();
        return owned;
    } else {
        // Traditional read for small files
        return try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    }
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
