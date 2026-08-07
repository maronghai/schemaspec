const std = @import("std");
const handlers = @import("pipeline/handlers.zig");
const io_mod = @import("io.zig");
const dialect_enum = @import("dialect/enum.zig");

// ─── Watch Mode ───────────────────────────────────────────────
// Polls a .ss file for changes and recompiles automatically.
// Uses file content hash comparison for change detection.

/// Configuration for watch mode.
pub const WatchConfig = struct {
    /// Input .ss file path to watch.
    input: []const u8,
    /// Polling interval in milliseconds.
    interval_ms: u64 = 1000,
    /// Target SQL dialect.
    dialect: dialect_enum.Dialect = .mysql,
    /// Output format (sql or json_schema).
    target: handlers.OutputFormat = .sql,
    /// Output file path (null = stdout).
    output_path: ?[]const u8 = null,
    /// Suppress non-essential output.
    quiet: bool = false,
    /// Print compilation trace.
    trace: bool = false,
    /// Print compilation stats.
    stats: bool = false,
    /// JSON error output.
    json_errors: bool = false,
    /// Use parallel streaming compilation (compile independent tables concurrently).
    parallel: bool = false,
};

/// Hash file content for change detection.
fn hashFileContent(io: std.Io, path: []const u8) ?u64 {
    const file_data = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .unlimited) catch return null;
    defer std.heap.page_allocator.free(file_data);
    return std.hash.Wyhash.hash(0, file_data);
}

/// Run one compilation cycle. Returns true on success, false on error.
fn compileOnce(io: std.Io, alloc: std.mem.Allocator, cfg: WatchConfig) bool {
    // Compile mode: rune <file>
    handlers.handleCompileRequest(io, alloc, .{
        .input = cfg.input,
        .output_path = cfg.output_path,
        .trace = cfg.trace,
        .dialect = cfg.dialect,
        .format = cfg.target,
        .stats = cfg.stats,
        .quiet = cfg.quiet,
        .json_errors = cfg.json_errors,
        .stream = cfg.parallel,
        .parallel = cfg.parallel,
    }) catch |err| {
        if (!cfg.quiet) {
            std.debug.print("error: compilation failed: {s}\n", .{@errorName(err)});
        }
        return false;
    };
    return true;
}

/// Watch a .ss file for changes and recompile automatically.
/// Polls the file's content hash at the configured interval.
/// Exits cleanly on any error (file not found, compile error).
pub fn watch(io: std.Io, alloc: std.mem.Allocator, cfg: WatchConfig) !void {
    if (!cfg.quiet) {
        std.debug.print("Watching {s} (polling every {d}ms)\n", .{ cfg.input, cfg.interval_ms });
        std.debug.print("Press Ctrl+C to stop\n\n", .{});
    }

    var last_hash = hashFileContent(io, cfg.input);
    if (last_hash == null) {
        std.debug.print("error: file not found: {s}\n", .{cfg.input});
        return error.FileNotFound;
    }

    // Initial compilation
    if (!cfg.quiet) {
        std.debug.print("Initial compilation...\n", .{});
    }
    const initial_ok = compileOnce(io, alloc, cfg);
    if (!cfg.quiet) {
        if (initial_ok)
            std.debug.print("OK\n\n", .{})
        else
            std.debug.print("FAILED\n\n", .{});
    }

    // Poll loop
    var change_count: u64 = 0;
    while (true) {
        // Sleep for the configured interval — efficient, no CPU waste
        const dur = std.Io.Clock.Duration{
            .raw = .{ .nanoseconds = @intCast(cfg.interval_ms * std.time.ns_per_ms) },
            .clock = .awake,
        };
        dur.sleep(io) catch {};

        const current_hash = hashFileContent(io, cfg.input);
        if (current_hash == null) {
            if (!cfg.quiet) {
                std.debug.print("warning: file disappeared: {s}\n", .{cfg.input});
            }
            continue;
        }

        if (current_hash != last_hash) {
            last_hash = current_hash;
            change_count += 1;
            if (!cfg.quiet) {
                std.debug.print("[{d}] Change detected in {s}, recompiling...\n", .{ change_count, cfg.input });
            }
            const ok = compileOnce(io, alloc, cfg);
            if (!cfg.quiet) {
                if (ok)
                    std.debug.print("[{d}] OK\n\n", .{change_count})
                else
                    std.debug.print("[{d}] FAILED\n\n", .{change_count});
            }
        }
    }
}
