const std = @import("std");
const dialect_enum = @import("dialect/enum.zig");

// ─── Minimal TOML Parser ─────────────────────────────────────
// Handles: [section] headers, key = "string", key = true/false, key = integer.
// No arrays, inline tables, or datetime types — sufficient for rune.toml config.

pub const Config = struct {
    project_name: ?[]const u8 = null,
    dialect: ?[]const u8 = null,
    color: ?[]const u8 = null,
    quiet: ?bool = null,
    json_errors: ?bool = null,
    stats: ?bool = null,
    strict: ?bool = null,
    verbose_passes: ?bool = null,
};

pub const ParseError = error{InvalidSyntax};

pub const ConfigError = error{
    InvalidDialect,
    InvalidColor,
};

const Section = enum {
    project,
    dialect,
    output,
    unknown,
};

/// Parse a rune.toml config file from disk.
pub fn loadConfig(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Config {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch |err| {
        if (err == error.FileNotFound) return Config{};
        return err;
    };
    return try parseConfig(alloc, data);
}

/// Load config with parent-directory discovery and unknown-key warnings.
/// Searches upward from cwd for rune.toml, parses it, and warns about unknown keys.
pub fn loadConfigWithWarnings(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Config {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch |err| {
        if (err == error.FileNotFound) return Config{};
        return err;
    };
    warnUnknownKeys(data, true);
    return try parseConfig(alloc, data);
}

/// Load config with parent-directory discovery, unknown-key warnings, and discovery.
/// Searches upward from cwd for rune.toml (like git searches for .git/).
/// Stops at filesystem root or after 128 levels (safety bound).
pub fn loadConfigWithDiscoveryAndWarnings(io: std.Io, alloc: std.mem.Allocator) !Config {
    var dir = std.Io.Dir.cwd();
    var depth: u8 = 0;
    while (depth < 128) : (depth += 1) {
        const data = dir.readFileAlloc(io, "rune.toml", alloc, .unlimited) catch |err| {
            if (err != error.FileNotFound) return Config{};
            const parent = dir.openDir(io, "..", .{}) catch return Config{};
            dir.close(io);
            dir = parent;
            continue;
        };
        warnUnknownKeys(data, true);
        const result = try parseConfig(alloc, data);
        dir.close(io);
        return result;
    }
    dir.close(io);
    return Config{};
}

/// Parse TOML content into a Config struct.
pub fn parseConfig(_: std.mem.Allocator, data: []const u8) !Config {
    var config = Config{};
    var current_section: Section = .unknown;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = trimComment(raw_line);
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Section header: [name]
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            const section_name = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
            current_section = if (std.mem.eql(u8, section_name, "project"))
                .project
            else if (std.mem.eql(u8, section_name, "dialect"))
                .dialect
            else if (std.mem.eql(u8, section_name, "output"))
                .output
            else
                .unknown;
            continue;
        }

        // Key-value pair: key = value
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value_raw = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\r");

            switch (current_section) {
                .project => {
                    if (std.mem.eql(u8, key, "name")) {
                        config.project_name = try parseString(value_raw);
                    }
                },
                .dialect => {
                    if (std.mem.eql(u8, key, "default")) {
                        config.dialect = try parseString(value_raw);
                    }
                },
                .output => {
                    if (std.mem.eql(u8, key, "color")) {
                        config.color = try parseString(value_raw);
                    } else if (std.mem.eql(u8, key, "quiet")) {
                        config.quiet = try parseBool(value_raw);
                    } else if (std.mem.eql(u8, key, "json_errors")) {
                        config.json_errors = try parseBool(value_raw);
                    } else if (std.mem.eql(u8, key, "stats")) {
                        config.stats = try parseBool(value_raw);
                    } else if (std.mem.eql(u8, key, "strict")) {
                        config.strict = try parseBool(value_raw);
                    } else if (std.mem.eql(u8, key, "verbose_passes")) {
                        config.verbose_passes = try parseBool(value_raw);
                    }
                },
                .unknown => {},
            }
        }
    }

    return config;
}

/// Validate config values. Returns an error with a descriptive message.
pub fn validateConfig(cfg: Config) ConfigError!void {
    if (cfg.dialect) |d| {
        if (!isValidDialect(d)) return error.InvalidDialect;
    }
    if (cfg.color) |c| {
        if (!isValidColor(c)) return error.InvalidColor;
    }
}

fn isValidDialect(s: []const u8) bool {
    _ = dialect_enum.parseDialect(s) catch return false;
    return true;
}

fn isValidColor(s: []const u8) bool {
    return std.mem.eql(u8, s, "auto") or std.mem.eql(u8, s, "always") or std.mem.eql(u8, s, "never");
}

fn trimComment(line: []const u8) []const u8 {
    // Find # not inside a string
    var in_string = false;
    for (line, 0..) |c, i| {
        if (c == '"') in_string = !in_string;
        if (c == '#' and !in_string) return line[0..i];
    }
    return line;
}

fn parseString(raw: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return trimmed[1 .. trimmed.len - 1];
    }
    // Unquoted string (bare value)
    if (trimmed.len > 0) return trimmed;
    return error.InvalidSyntax;
}

fn parseBool(raw: []const u8) !bool {
    const trimmed = std.mem.trim(u8, raw, " \t");
    if (std.mem.eql(u8, trimmed, "true")) return true;
    if (std.mem.eql(u8, trimmed, "false")) return false;
    return error.InvalidSyntax;
}

// ─── Config Key Validation ────────────────────────────────────

const VALID_PROJECT_KEYS = [_][]const u8{"name"};
const VALID_DIALECT_KEYS = [_][]const u8{"default"};
const VALID_OUTPUT_KEYS = [_][]const u8{ "color", "quiet", "json_errors", "stats", "strict", "verbose_passes" };

/// Check a TOML string for unknown sections or keys.
/// Prints warnings to stderr when emit_warnings is true.
/// Called after parseConfig to alert users about typos.
pub fn warnUnknownKeys(data: []const u8, emit_warnings: bool) void {
    var current_section: Section = .unknown;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = trimComment(raw_line);
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Section header
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            const section_name = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
            current_section = if (std.mem.eql(u8, section_name, "project"))
                .project
            else if (std.mem.eql(u8, section_name, "dialect"))
                .dialect
            else if (std.mem.eql(u8, section_name, "output"))
                .output
            else blk: {
                if (emit_warnings) std.debug.print("warning: unknown config section '[{s}]'\n", .{section_name});
                break :blk .unknown;
            };
            continue;
        }

        // Key-value pair
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var found = false;
            switch (current_section) {
                .project => {
                    for (VALID_PROJECT_KEYS) |vk| {
                        if (std.mem.eql(u8, key, vk)) found = true;
                    }
                },
                .dialect => {
                    for (VALID_DIALECT_KEYS) |vk| {
                        if (std.mem.eql(u8, key, vk)) found = true;
                    }
                },
                .output => {
                    for (VALID_OUTPUT_KEYS) |vk| {
                        if (std.mem.eql(u8, key, vk)) found = true;
                    }
                },
                .unknown => {},
            }
            if (!found and current_section != .unknown) {
                if (emit_warnings) std.debug.print("warning: unknown config key '{s}' in section\n", .{key});
            }
        }
    }
}

// ─── Tests ─────────────────────────────────────────────────────

test "parse empty config" {
    const result = try parseConfig(std.testing.allocator, "");
    try std.testing.expectEqual(@as(?[]const u8, null), result.project_name);
    try std.testing.expectEqual(@as(?[]const u8, null), result.dialect);
    try std.testing.expectEqual(@as(?bool, null), result.quiet);
}

test "parse full config" {
    const toml =
        \\[project]
        \\name = "myapp"
        \\
        \\[dialect]
        \\default = "pg"
        \\
        \\[output]
        \\color = "always"
        \\quiet = true
        \\json_errors = false
        \\stats = true
    ;
    const result = try parseConfig(std.testing.allocator, toml);
    try std.testing.expectEqualStrings("myapp", result.project_name.?);
    try std.testing.expectEqualStrings("pg", result.dialect.?);
    try std.testing.expectEqualStrings("always", result.color.?);
    try std.testing.expectEqual(true, result.quiet.?);
    try std.testing.expectEqual(false, result.json_errors.?);
    try std.testing.expectEqual(true, result.stats.?);
}

test "parse with comments" {
    const toml =
        \\# Top-level comment
        \\[dialect]
        \\default = "mysql" # inline comment
    ;
    const result = try parseConfig(std.testing.allocator, toml);
    try std.testing.expectEqualStrings("mysql", result.dialect.?);
}

test "parse unknown sections ignored" {
    const toml =
        \\[unknown]
        \\foo = "bar"
        \\
        \\[dialect]
        \\default = "sqlite"
    ;
    const result = try parseConfig(std.testing.allocator, toml);
    try std.testing.expectEqualStrings("sqlite", result.dialect.?);
}

test "parse bare values" {
    const toml =
        \\[dialect]
        \\default = pg
    ;
    const result = try parseConfig(std.testing.allocator, toml);
    try std.testing.expectEqualStrings("pg", result.dialect.?);
}

test "validate valid config" {
    const cfg = Config{ .dialect = "pg", .color = "always" };
    try validateConfig(cfg);
}

test "validate invalid dialect" {
    const cfg = Config{ .dialect = "oracl" };
    try std.testing.expectError(error.InvalidDialect, validateConfig(cfg));
}

test "validate invalid color" {
    const cfg = Config{ .color = "sometimes" };
    try std.testing.expectError(error.InvalidColor, validateConfig(cfg));
}

test "validate null values pass" {
    const cfg = Config{};
    try validateConfig(cfg);
}

test "warnUnknownKeys does not crash on valid config" {
    const toml =
        \\[project]
        \\name = "myapp"
        \\
        \\[dialect]
        \\default = "pg"
    ;
    warnUnknownKeys(toml, false);
}

test "warnUnknownKeys handles unknown section" {
    const toml =
        \\[unknown]
        \\foo = "bar"
    ;
    warnUnknownKeys(toml, false);
}

test "warnUnknownKeys handles unknown key in known section" {
    const toml =
        \\[output]
        \\typo_key = "value"
    ;
    warnUnknownKeys(toml, false);
}

test "warnUnknownKeys handles empty input" {
    warnUnknownKeys("", false);
}
