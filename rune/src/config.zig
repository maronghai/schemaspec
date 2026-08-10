const std = @import("std");
const dialect_enum = @import("dialect/enum.zig");
const fmt = @import("diagnostic/format.zig");

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
    stream: ?bool = null,
    parallel: ?bool = null,
    target: ?[]const u8 = null,
    format: ?[]const u8 = null,
};

pub const ParseError = error{InvalidSyntax};

pub const ConfigError = error{
    InvalidDialect,
    InvalidColor,
    InvalidTarget,
    InvalidFormat,
};

const Section = enum {
    project,
    dialect,
    output,
    unknown,
};

/// A parsed TOML line — either a section header or a key-value pair.
const ParsedLine = union(enum) {
    section: []const u8,
    key_value: struct { key: []const u8, value: []const u8 },
    empty,
};

/// Shared line iterator for TOML parsing.
/// Eliminates duplication between parseConfig and warnUnknownKeys.
const TomlLineIterator = struct {
    lines: std.mem.SplitIterator(u8, .scalar),

    fn init(data: []const u8) TomlLineIterator {
        return .{ .lines = std.mem.splitScalar(u8, data, '\n') };
    }

    fn next(self: *TomlLineIterator) ?ParsedLine {
        while (self.lines.next()) |raw_line| {
            const line = trimComment(raw_line);
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Section header: [name]
            if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
                const section_name = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
                return .{ .section = section_name };
            }

            // Key-value pair: key = value
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value_raw = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\r");
                return .{ .key_value = .{ .key = key, .value = value_raw } };
            }
        }
        return null;
    }
};

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
    var owned = false; // only close dirs we opened, not the PEB CWD handle
    var depth: u8 = 0;
    while (depth < 128) : (depth += 1) {
        const data = dir.readFileAlloc(io, "rune.toml", alloc, .unlimited) catch |err| {
            if (err != error.FileNotFound) {
                if (owned) dir.close(io);
                return err;
            }
            const parent = dir.openDir(io, "..", .{}) catch {
                if (owned) dir.close(io);
                return Config{};
            };
            if (owned) dir.close(io);
            dir = parent;
            owned = true;
            continue;
        };
        if (owned) dir.close(io);
        warnUnknownKeys(data, true);
        return try parseConfig(alloc, data);
    }
    if (owned) dir.close(io);
    return Config{};
}

/// Parse TOML content into a Config struct.
pub fn parseConfig(_: std.mem.Allocator, data: []const u8) !Config {
    var config = Config{};
    var current_section: Section = .unknown;
    var iter = TomlLineIterator.init(data);

    while (iter.next()) |line| {
        switch (line) {
            .section => |section_name| {
                current_section = if (std.mem.eql(u8, section_name, "project"))
                    .project
                else if (std.mem.eql(u8, section_name, "dialect"))
                    .dialect
                else if (std.mem.eql(u8, section_name, "output"))
                    .output
                else
                    .unknown;
            },
            .key_value => |kv| {
                switch (current_section) {
                    .project => {
                        if (std.mem.eql(u8, kv.key, "name")) {
                            config.project_name = try parseString(kv.value);
                        }
                    },
                    .dialect => {
                        if (std.mem.eql(u8, kv.key, "default")) {
                            config.dialect = try parseString(kv.value);
                        }
                    },
                    .output => {
                        if (std.mem.eql(u8, kv.key, "color")) {
                            config.color = try parseString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "quiet")) {
                            config.quiet = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "json_errors")) {
                            config.json_errors = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "stats")) {
                            config.stats = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "strict")) {
                            config.strict = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "verbose_passes")) {
                            config.verbose_passes = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "stream")) {
                            config.stream = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "parallel")) {
                            config.parallel = try parseBool(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "target")) {
                            config.target = try parseString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "format")) {
                            config.format = try parseString(kv.value);
                        }
                    },
                    .unknown => {},
                }
            },
            .empty => {},
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
    if (cfg.target) |t| {
        if (!isValidTarget(t)) return error.InvalidTarget;
    }
    if (cfg.format) |f| {
        if (!isValidFormat(f)) return error.InvalidFormat;
    }
}

fn isValidDialect(s: []const u8) bool {
    _ = dialect_enum.parseDialect(s) catch return false;
    return true;
}

fn isValidColor(s: []const u8) bool {
    return std.mem.eql(u8, s, "auto") or std.mem.eql(u8, s, "always") or std.mem.eql(u8, s, "never");
}

fn isValidTarget(s: []const u8) bool {
    return std.mem.eql(u8, s, "sql") or std.mem.eql(u8, s, "json-schema") or std.mem.eql(u8, s, "json_schema");
}

fn isValidFormat(s: []const u8) bool {
    return std.mem.eql(u8, s, "text") or std.mem.eql(u8, s, "json") or std.mem.eql(u8, s, "sarif") or std.mem.eql(u8, s, "markdown");
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
const VALID_OUTPUT_KEYS = [_][]const u8{ "color", "quiet", "json_errors", "stats", "strict", "verbose_passes", "stream", "parallel", "target", "format" };

/// Check a TOML string for unknown sections or keys.
/// Prints warnings to stderr when emit_warnings is true.
/// Called after parseConfig to alert users about typos.
pub fn warnUnknownKeys(data: []const u8, emit_warnings: bool) void {
    var current_section: Section = .unknown;
    var iter = TomlLineIterator.init(data);

    while (iter.next()) |line| {
        switch (line) {
            .section => |section_name| {
                current_section = if (std.mem.eql(u8, section_name, "project"))
                    .project
                else if (std.mem.eql(u8, section_name, "dialect"))
                    .dialect
                else if (std.mem.eql(u8, section_name, "output"))
                    .output
                else blk: {
                    if (emit_warnings) {
                        fmt.printWarn("unknown config section [note: valid sections are [project], [dialect], [output]]");
                    }
                    break :blk .unknown;
                };
            },
            .key_value => |kv| {
                var found = false;
                switch (current_section) {
                    .project => {
                        for (VALID_PROJECT_KEYS) |vk| {
                            if (std.mem.eql(u8, kv.key, vk)) found = true;
                        }
                    },
                    .dialect => {
                        for (VALID_DIALECT_KEYS) |vk| {
                            if (std.mem.eql(u8, kv.key, vk)) found = true;
                        }
                    },
                    .output => {
                        for (VALID_OUTPUT_KEYS) |vk| {
                            if (std.mem.eql(u8, kv.key, vk)) found = true;
                        }
                    },
                    .unknown => {},
                }
                if (!found and current_section != .unknown) {
                    if (emit_warnings) {
                        fmt.printWarn("unknown config key");
                    }
                }
            },
            .empty => {},
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

test "parse config with new output keys" {
    const toml =
        \\[output]
        \\stream = true
        \\parallel = true
        \\target = "json-schema"
        \\format = "sarif"
    ;
    const result = try parseConfig(std.testing.allocator, toml);
    try std.testing.expectEqual(true, result.stream.?);
    try std.testing.expectEqual(true, result.parallel.?);
    try std.testing.expectEqualStrings("json-schema", result.target.?);
    try std.testing.expectEqualStrings("sarif", result.format.?);
}

test "validate valid target" {
    const cfg = Config{ .target = "json-schema" };
    try validateConfig(cfg);
}

test "validate invalid target" {
    const cfg = Config{ .target = "xml" };
    try std.testing.expectError(error.InvalidTarget, validateConfig(cfg));
}

test "validate valid format" {
    const cfg = Config{ .format = "sarif" };
    try validateConfig(cfg);
}

test "validate invalid format" {
    const cfg = Config{ .format = "csv" };
    try std.testing.expectError(error.InvalidFormat, validateConfig(cfg));
}
