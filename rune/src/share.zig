const std = @import("std");
const io_mod = @import("io.zig");
const fmt = @import("diagnostic/format.zig");

/// Configuration for the share command.
pub const ShareConfig = struct {
    /// Input .ss file path (null = stdin).
    input: ?[]const u8,
    /// Output file path for the generated URL (null = stdout).
    output: ?[]const u8,
    /// Output format: url (default), json, qr.
    format: ShareFormat,
};

/// Share output format.
pub const ShareFormat = enum { url, json, qr };

/// Result of the share operation.
pub const ShareResult = struct {
    /// The playground URL.
    url: []const u8,
    /// Base64-encoded schema.
    encoded: []const u8,
    /// Original schema size in bytes.
    original_size: usize,
    /// Compressed size in bytes.
    compressed_size: usize,
};

/// Handle the share command.
pub fn handleShare(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ShareConfig) !void {
    const encoded = try encodeForPlayground(alloc, file_data);
    defer alloc.free(encoded);
    const url = try buildPlaygroundUrl(alloc, encoded);
    defer alloc.free(url);

    const result = ShareResult{
        .url = url,
        .encoded = encoded,
        .original_size = file_data.len,
        .compressed_size = encoded.len,
    };

    // Output based on format. The writer's buffer lives in THIS frame —
    // File.Writer stores a pointer to it, so handing one back from a helper
    // would leave the interface pointing at that helper's dead stack.
    var buf: [8192]u8 = undefined;
    var out = try getOutputWriter(io, alloc, cfg.output, &buf);
    defer out.flush() catch {};
    switch (cfg.format) {
        .url => {
            try (&out.interface).print("{s}\n", .{result.url});
        },
        .json => {
            try (&out.interface).print("{{\n  \"url\": \"{s}\",\n  \"encoded\": \"{s}\",\n  \"original_size\": {d},\n  \"compressed_size\": {d}\n}}\n", .{ result.url, result.encoded, result.original_size, result.compressed_size });
        },
        .qr => {
            try printQrCode(&out.interface, result.url);
        },
    }
}

/// Encode schema data for playground URL (base64url, no compression for simplicity).
fn encodeForPlayground(alloc: std.mem.Allocator, data: []const u8) ![]const u8 {
    // Base64 URL-safe encode (no padding)
    // base64 encoded length = ceil(data.len / 3) * 4
    const encoded_len = ((data.len + 2) / 3) * 4;
    var encoded = try alloc.alloc(u8, encoded_len);
    defer alloc.free(encoded);
    var encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
    _ = encoder.encode(encoded, data);
    // Convert to URL-safe: + -> -, / -> _, remove padding =
    for (encoded) |*c| {
        if (c.* == '+') {
            c.* = '-';
        } else if (c.* == '/') {
            c.* = '_';
        }
    }
    // Trim padding
    var i = encoded.len;
    while (i > 0 and encoded[i - 1] == '=') i -= 1;
    const final_encoded = encoded[0..i];

    var b64buf = try std.ArrayList(u8).initCapacity(alloc, final_encoded.len);
    defer b64buf.deinit(alloc);
    try b64buf.appendSlice(alloc, final_encoded);
    return b64buf.toOwnedSlice(alloc);
}

/// Build playground URL.
fn buildPlaygroundUrl(alloc: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const base_url = "https://rune-lang.org/playground#";
    var url = try alloc.alloc(u8, base_url.len + encoded.len);
    std.mem.copyForwards(u8, url[0..base_url.len], base_url);
    std.mem.copyForwards(u8, url[base_url.len..], encoded);
    return url;
}

/// Get output writer (file or stdout). `buf` must outlive the returned
/// writer — File.Writer stores a pointer to it (see io.zig's same-frame rule).
fn getOutputWriter(io: std.Io, alloc: std.mem.Allocator, output: ?[]const u8, buf: *[8192]u8) anyerror!std.Io.File.Writer {
    if (output) |path| {
        const file = try io_mod.openFileForWrite(io, alloc, path);
        return file.writer(io, buf);
    }
    const stdout_file = std.Io.File.stdout();
    return stdout_file.writer(io, buf);
}

/// Print QR code (simplified - just outputs the URL for now).
/// In a full implementation, this would generate an actual QR code.
fn printQrCode(out: *std.Io.Writer, url: []const u8) !void {
    try out.print("QR Code for: {s}\n", .{url});
    try out.print("(Install a QR code library for graphical output)\n", .{});
    try out.print("{s}\n", .{url});
}

// ─── Tests ───────────────────────────────────────────────────

test "encodeForPlayground: basic" {
    const alloc = std.testing.allocator;
    const data = "test schema";
    const encoded = try encodeForPlayground(alloc, data);
    defer alloc.free(encoded);

    // Verify it's valid base64url (no +, /, =)
    for (encoded) |c| {
        try std.testing.expect(c != '+');
        try std.testing.expect(c != '/');
        try std.testing.expect(c != '=');
    }
}

test "encodeForPlayground roundtrip decodes to the original" {
    const alloc = std.testing.allocator;
    const data = "$ test\n# users\n  id n++ PK\n  name s100?\n";
    const encoded = try encodeForPlayground(alloc, data);
    defer alloc.free(encoded);

    // Decode: restore URL-safe chars, pad, then base64-decode.
    const decoded = try alloc.alloc(u8, encoded.len + ((4 - encoded.len % 4) % 4));
    defer alloc.free(decoded);
    @memcpy(decoded[0..encoded.len], encoded);
    for (decoded[0..encoded.len]) |*c| {
        if (c.* == '-') c.* = '+';
        if (c.* == '_') c.* = '/';
    }
    @memset(decoded[encoded.len..], '=');

    const decoder = std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '=');
    const plain = try decoder.calcSizeForSlice(decoded);
    const out = try alloc.alloc(u8, plain);
    defer alloc.free(out);
    try decoder.decode(out, decoded);
    try std.testing.expectEqualStrings(data, out);
}

test "buildPlaygroundUrl: format" {
    const alloc = std.testing.allocator;
    const encoded = "abc123";
    const url = try buildPlaygroundUrl(alloc, encoded);
    defer alloc.free(url);

    try std.testing.expect(std.mem.startsWith(u8, url, "https://rune-lang.org/playground#"));
    try std.testing.expect(std.mem.endsWith(u8, url, "abc123"));
}

test "handleShare url format writes playground URL" {
    const alloc = std.testing.allocator;
    const testing = std.testing;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_abs_len = try tmp.dir.realPath(testing.io, &path_buf);
    const out_path = try std.fs.path.join(alloc, &.{ path_buf[0..tmp_abs_len], "share_url.txt" });
    defer alloc.free(out_path);

    const data = "$ test\n# users\n  id n++\n  name s100\n";
    try handleShare(testing.io, alloc, data, .{ .input = null, .output = out_path, .format = .url });

    const written = try std.Io.Dir.cwd().readFileAlloc(testing.io, out_path, alloc, .unlimited);
    defer alloc.free(written);
    try std.testing.expect(std.mem.startsWith(u8, written, "https://rune-lang.org/playground#"));
}
