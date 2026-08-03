const std = @import("std");

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

    /// Merge CLI args over config values. CLI non-null wins.
    pub fn mergeWithArgs(self: Config, args: anytype) Config {
        var result = self;
        if (args.dialect) |d| result.dialect = d;
        if (args.color) |c| result.color = c;
        if (args.quiet) |q| result.quiet = q;
        if (args.json_errors) |j| result.json_errors = j;
        if (args.stats) |s| result.stats = s;
        return result;
    }
};

pub const ParseError = error{
    InvalidSyntax,
    UnexpectedEof,
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
                    }
                },
                .unknown => {},
            }
        }
    }

    return config;
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
