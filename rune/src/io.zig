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
    /// Whether data was heap-allocated (Windows fallback) vs mmap'd.
    is_heap: bool = false,

    /// Release memory-mapped region.
    pub fn deinit(self: MmapResult) void {
        if (self.is_heap) {
            if (self.data.len > 0) {
                std.heap.page_allocator.free(self.data);
            }
        } else if (comptime @import("builtin").os.tag != .windows and @import("builtin").os.tag != .wasi) {
            // Properly unmap the memory-mapped region on Linux.
            // Use the page-aligned base address for munmap.
            if (self.data.len > 0) {
                const page_size = std.mem.page_size;
                const aligned_len = (self.data.len + page_size - 1) & ~(page_size - 1);
                const aligned_ptr: [*]align(page_size) u8 = @alignCast(@constCast(self.data.ptr));
                std.posix.munmap(@alignCast(aligned_ptr[0..aligned_len]));
            }
        }
    }
};

/// Memory-map a file for efficient large-file access.
/// Caller must call result.deinit() when done.
pub fn mmapFile(io: std.Io, path: []const u8) !MmapResult {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const size = stat.size;

    if (size == 0) {
        return .{ .data = &.{}, .size = 0 };
    }

    if (comptime @import("builtin").os.tag == .windows or @import("builtin").os.tag == .wasi) {
        // Windows and WASM: fall back to regular read (no POSIX mmap)
        const data = try std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .unlimited);
        return .{ .data = data, .size = data.len, .is_heap = true };
    } else {
        const mapped = try std.posix.mmap(
            null,
            size,
            .{ .READ = true },
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );

        return .{
            .data = mapped,
            .size = size,
        };
    }
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
/// Uses standard file read for all sizes — mmap is available as a separate
/// public utility (mmapFile) for callers that need it directly.
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
