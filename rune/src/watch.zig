const std = @import("std");
const handlers = @import("pipeline/handlers.zig");
const io_mod = @import("io.zig");
const dialect_enum = @import("dialect/enum.zig");
const color_mod = @import("color.zig");
const fmt = @import("diagnostic/format.zig");

// ─── Watch Mode ───────────────────────────────────────────────
// Polls .ss files for changes and recompiles automatically.
// Supports single-file and directory mode (--recursive).
// Uses file content hash comparison for change detection.

/// Configuration for watch mode.
pub const WatchConfig = struct {
    /// Input .ss file or directory path to watch.
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
    /// Streaming compilation (output SQL as each table resolves).
    stream: bool = false,
    /// Use parallel streaming compilation (compile independent tables concurrently).
    parallel: bool = false,
    /// Watch directory recursively instead of a single file.
    recursive: bool = false,
    /// Import search paths for @import directives.
    import_paths: []const []const u8 = &.{},
    /// Color mode for output.
    color: color_mod.ColorMode = .auto,
};

/// Hash file content for change detection.
fn hashFileContent(io: std.Io, path: []const u8) ?u64 {
    const file_data = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .unlimited) catch return null;
    defer std.heap.page_allocator.free(file_data);
    return std.hash.Wyhash.hash(0, file_data);
}

/// Per-file watch state: content hash plus the stat snapshot it was computed
/// at. Both mtime and size participate in the short-circuit: an mtime-equal
/// check alone misses a write landing within the same timestamp tick (FAT
/// family granularity), which would never be sampled again.
const FileState = struct {
    hash: u64,
    mtime_ns: i128,
    size: u64,
};

const StatSnapshot = struct { mtime_ns: i128, size: u64 };

fn statMtimeNs(io: std.Io, path: []const u8) ?i128 {
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return st.mtime.nanoseconds;
}

fn statFileSnapshot(io: std.Io, path: []const u8) ?StatSnapshot {
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return .{ .mtime_ns = st.mtime.nanoseconds, .size = st.size };
}

/// Run one compilation cycle. Returns true on success, false on error.
fn compileOnce(io: std.Io, alloc: std.mem.Allocator, cfg: WatchConfig, input: []const u8) bool {
    handlers.handleCompileRequest(io, alloc, .{
        .input = input,
        .output_path = cfg.output_path,
        .trace = cfg.trace,
        .dialect = cfg.dialect,
        .format = cfg.target,
        .stats = cfg.stats,
        .quiet = cfg.quiet,
        .json_errors = cfg.json_errors,
        .stream = cfg.stream or cfg.parallel,
        .parallel = cfg.parallel,
        .import_paths = cfg.import_paths,
        .color = cfg.color.shouldUseColor(io),
    }) catch |err| {
        if (!cfg.quiet) {
            fmt.printError("compile", "compilation failed");
            std.debug.print("  {s}: {s}\n", .{ input, @errorName(err) });
        }
        return false;
    };
    return true;
}

/// Scan a directory for .ss files. Adds them to the provided list.
/// When recursive=true, descends into subdirectories.
fn scanDir(io: std.Io, alloc: std.mem.Allocator, dir_path: []const u8, recursive: bool, files: *std.ArrayList([]const u8)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file) {
            // Check for .ss extension
            if (entry.name.len > 3 and std.mem.eql(u8, entry.name[entry.name.len - 3 ..], ".ss")) {
                const full_path = if (dir_path.len == 0 or std.mem.eql(u8, dir_path, "."))
                    try std.fmt.allocPrint(alloc, "{s}", .{entry.name})
                else
                    try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir_path, entry.name });
                try files.append(alloc, full_path);
            }
        } else if (entry.kind == .directory and recursive) {
            const sub_path = if (dir_path.len == 0 or std.mem.eql(u8, dir_path, "."))
                try std.fmt.allocPrint(alloc, "{s}", .{entry.name})
            else
                try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir_path, entry.name });
            try scanDir(io, alloc, sub_path, true, files);
        }
    }
}

/// Collect all .ss files to watch from a path.
/// Returns a list of file paths (caller owns the list).
fn collectFiles(io: std.Io, alloc: std.mem.Allocator, input: []const u8, recursive: bool) !std.ArrayList([]const u8) {
    var files = try std.ArrayList([]const u8).initCapacity(alloc, 16);

    // Try to open as directory first — if it succeeds, it's a directory
    if (std.Io.Dir.cwd().openDir(io, input, .{ .iterate = true })) |*dir| {
        defer dir.close(io);
        try scanDir(io, alloc, input, recursive, &files);
    } else |_| {
        // Not a directory — treat as a single file
        try files.append(alloc, input);
    }

    return files;
}

/// Watch a .ss file or directory for changes and recompile automatically.
/// Polls file content hashes at the configured interval.
/// Exits cleanly on any error (file not found, compile error).
pub fn watch(io: std.Io, alloc: std.mem.Allocator, cfg: WatchConfig) !void {
    const files = try collectFiles(io, alloc, cfg.input, cfg.recursive);

    if (files.items.len == 0) {
        if (!cfg.quiet) {
            fmt.printError("io", "no .ss files found");
            std.debug.print("  {s}\n", .{cfg.input});
        }
        return error.FileNotFound;
    }

    if (!cfg.quiet) {
        if (files.items.len == 1) {
            std.debug.print("Watching {s} (polling every {d}ms)\n", .{ files.items[0], cfg.interval_ms });
        } else {
            std.debug.print("Watching {d} files in {s} (polling every {d}ms)\n", .{ files.items.len, cfg.input, cfg.interval_ms });
        }
        std.debug.print("Press Ctrl+C to stop\n\n", .{});
    }

    // Build initial state map (content hash + stat snapshot). Keys and the
    // map itself live in `alloc` (command lifetime); everything a single
    // poll cycle allocates goes into a per-cycle arena freed below.
    var hashes = std.StringHashMap(FileState).init(alloc);
    for (files.items) |file_path| {
        if (hashFileContent(io, file_path)) |hash| {
            const snap = statFileSnapshot(io, file_path) orelse StatSnapshot{ .mtime_ns = 0, .size = 0 };
            const owned_path = try alloc.dupe(u8, file_path);
            hashes.put(owned_path, .{ .hash = hash, .mtime_ns = snap.mtime_ns, .size = snap.size }) catch {};
        }
    }

    // Initial compilation
    if (!cfg.quiet) {
        std.debug.print("Initial compilation...\n", .{});
    }
    var success_count: u32 = 0;
    var fail_count: u32 = 0;
    var initial_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer initial_arena.deinit();
    for (files.items) |file_path| {
        const ok = compileOnce(io, initial_arena.allocator(), cfg, file_path);
        if (ok) success_count += 1 else fail_count += 1;
    }
    if (!cfg.quiet) {
        if (files.items.len == 1) {
            if (fail_count == 0) std.debug.print("OK\n\n", .{}) else std.debug.print("FAILED\n\n", .{});
        } else {
            std.debug.print("{d}/{d} compiled successfully\n\n", .{ success_count, files.items.len });
        }
    }

    // Poll loop. Each cycle compiles on a fresh arena — without this, every
    // recompile's pipeline intermediates accumulate in the command-lifetime
    // allocator and long watch sessions grow without bound.
    var change_count: u64 = 0;
    var error_streak: u32 = 0;
    while (true) {
        // Sleep for the configured interval — efficient, no CPU waste
        const dur = std.Io.Clock.Duration{
            .raw = .{ .nanoseconds = @intCast(cfg.interval_ms * std.time.ns_per_ms) },
            .clock = .awake,
        };
        dur.sleep(io) catch {};

        var cycle_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer cycle_arena.deinit();
        const cycle_alloc = cycle_arena.allocator();

        // Check for new files (in directory mode)
        if (cfg.recursive) {
            const new_files = collectFiles(io, cycle_alloc, cfg.input, true) catch return error.FileNotFound;
            for (new_files.items) |file_path| {
                if (!hashes.contains(file_path)) {
                    // New file detected — add it
                    if (!cfg.quiet) {
                        std.debug.print("New file detected: {s}\n", .{file_path});
                    }
                    if (hashFileContent(io, file_path)) |hash| {
                        const snap = statFileSnapshot(io, file_path) orelse StatSnapshot{ .mtime_ns = 0, .size = 0 };
                        const owned_path = try alloc.dupe(u8, file_path);
                        try hashes.put(owned_path, .{ .hash = hash, .mtime_ns = snap.mtime_ns, .size = snap.size });
                        if (!cfg.quiet) {
                            std.debug.print("Compiling {s}...\n", .{file_path});
                        }
                        const ok = compileOnce(io, cycle_alloc, cfg, file_path);
                        if (ok) error_streak = 0 else error_streak += 1;
                    }
                }
            }
        }

        // Check for changes in existing files
        var iter = hashes.iterator();
        while (iter.next()) |entry| {
            const path = entry.key_ptr.*;
            // Short-circuit: identical mtime AND size → skip read+hash. Size
            // participates because a write can land within the same mtime tick.
            const snap = statFileSnapshot(io, path) orelse {
                // File disappeared: warn once, then evict so we stop polling
                // a ghost every cycle (a later re-creation re-registers).
                if (!cfg.quiet) {
                    fmt.printWarn("file disappeared");
                    std.debug.print("  {s}\n", .{path});
                }
                _ = hashes.remove(path);
                alloc.free(path);
                continue;
            };
            if (snap.mtime_ns == entry.value_ptr.mtime_ns and snap.size == entry.value_ptr.size) continue;

            const current_hash = hashFileContent(io, path);
            if (current_hash == null) continue; // vanished mid-cycle; next poll evicts

            if (current_hash != entry.value_ptr.hash) {
                entry.value_ptr.* = .{ .hash = current_hash.?, .mtime_ns = snap.mtime_ns, .size = snap.size };
                change_count += 1;
                if (!cfg.quiet) {
                    std.debug.print("[{d}] Change detected in {s}, recompiling...\n", .{ change_count, path });
                }
                const ok = compileOnce(io, cycle_alloc, cfg, path);
                if (ok) {
                    error_streak = 0;
                    if (!cfg.quiet) {
                        std.debug.print("[{d}] OK\n\n", .{change_count});
                    }
                } else {
                    error_streak += 1;
                    if (!cfg.quiet) {
                        std.debug.print("[{d}] FAILED", .{change_count});
                        if (error_streak > 1) {
                            std.debug.print(" (streak: {d})", .{error_streak});
                        }
                        std.debug.print("\n\n", .{});
                    }
                }
            } else {
                // Hash unchanged — just refresh the snapshot so the
                // short-circuit keeps working after touch-style rewrites.
                entry.value_ptr.* = .{ .hash = current_hash.?, .mtime_ns = snap.mtime_ns, .size = snap.size };
            }
        }
    }
}
