const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const types = @import("types.zig");

const Target = types.Target;
const DiffFormat = types.DiffFormat;
const ColorMode = types.ColorMode;

// ─── Flag Registry ────────────────────────────────────────────
// Data-driven flag definitions. Each global CLI flag is declared once here.
// parseGlobalFlags iterates over this table instead of a long if-else chain.
// Adding a new flag = add one entry to GLOBAL_FLAG_REGISTRY + handle it in
// the parsing loop's value-flag branch (or just set a bool for boolean flags).

pub const FlagKind = enum {
    /// Boolean flag: --flag sets a bool to true. No value consumed.
    boolean,
    /// Value flag: --flag <value> consumes the next argument.
    value,
    /// Value flag with multiple short/long forms (e.g. --dialect/-d).
    value_with_short,
};

pub const FlagEntry = struct {
    /// Long form name (e.g. "--stats").
    long: []const u8,
    /// Optional short form (e.g. "-s"). Null if no short form.
    short: ?[]const u8 = null,
    /// Kind of flag (boolean vs value).
    kind: FlagKind = .boolean,
    /// Description for help text.
    description: []const u8 = "",
};

/// All global flags known to the CLI. parseGlobalFlags uses this table
/// for both parsing and unknown-flag detection.
pub const GLOBAL_FLAG_REGISTRY = [_]FlagEntry{
    .{ .long = "--version", .short = "-v", .description = "Print version" },
    .{ .long = "--stats", .short = "-s", .description = "Print compilation statistics" },
    .{ .long = "--quiet", .short = "-q", .description = "Suppress non-essential output" },
    .{ .long = "--check", .description = "Exit 1 on schema errors" },
    .{ .long = "--dry-run", .description = "Show what would be done" },
    .{ .long = "--dialect", .short = "-d", .kind = .value_with_short, .description = "Target SQL dialect" },
    .{ .long = "--target", .kind = .value, .description = "Output target (sql|json-schema)" },
    .{ .long = "--format", .short = "-f", .kind = .value_with_short, .description = "Output format (text|json|sarif|markdown)" },
    .{ .long = "--validate-only", .description = "Reverse: validate only" },
    .{ .long = "--init", .description = "Create starter schema" },
    .{ .long = "--strict", .description = "Treat warnings as errors" },
    .{ .long = "--json-errors", .description = "Machine-readable error output" },
    .{ .long = "--verbose-passes", .description = "Print semantic pass execution details" },
    .{ .long = "--summary", .description = "Print summary only" },
    .{ .long = "--stat", .description = "Print summary only (alias for --summary)" },
    .{ .long = "--stream", .description = "Streaming compilation" },
    .{ .long = "--parallel", .description = "Parallel table compilation" },
    .{ .long = "--cache", .description = "Enable table-level compilation cache" },
    .{ .long = "--config", .kind = .value, .description = "Path to rune.toml config" },
    .{ .long = "--color", .kind = .value, .description = "Color mode (auto|always|never)" },
    .{ .long = "--import-path", .kind = .value, .description = "Additional import search path" },
    .{ .long = "--output", .short = "-o", .kind = .value_with_short, .description = "Output file path" },
};

/// Check if a flag is a known global flag (for unknown-flag detection).
pub fn isKnownGlobalFlag(flag: []const u8) bool {
    inline for (GLOBAL_FLAG_REGISTRY) |entry| {
        if (std.mem.eql(u8, flag, entry.long)) return true;
        if (entry.short) |short| {
            if (std.mem.eql(u8, flag, short)) return true;
        }
    }
    return false;
}

/// Check if a flag matches a specific registry entry (by long name).
pub fn matchesFlag(arg: []const u8, entry: FlagEntry) bool {
    if (std.mem.eql(u8, arg, entry.long)) return true;
    if (entry.short) |short| {
        if (std.mem.eql(u8, arg, short)) return true;
    }
    return false;
}

// ─── Tests ────────────────────────────────────────────────────

test "isKnownGlobalFlag matches long forms" {
    try std.testing.expect(isKnownGlobalFlag("--stats"));
    try std.testing.expect(isKnownGlobalFlag("--dialect"));
    try std.testing.expect(isKnownGlobalFlag("--output"));
    try std.testing.expect(isKnownGlobalFlag("--stat")); // alias for --summary
    try std.testing.expect(!isKnownGlobalFlag("--unknown-flag"));
}

test "isKnownGlobalFlag matches short forms" {
    try std.testing.expect(isKnownGlobalFlag("-v"));
    try std.testing.expect(isKnownGlobalFlag("-s"));
    try std.testing.expect(isKnownGlobalFlag("-d"));
    try std.testing.expect(isKnownGlobalFlag("-o"));
    try std.testing.expect(!isKnownGlobalFlag("-x"));
}

test "matchesFlag works for both forms" {
    const entry = FlagEntry{ .long = "--dialect", .short = "-d", .kind = .value_with_short };
    try std.testing.expect(matchesFlag("--dialect", entry));
    try std.testing.expect(matchesFlag("-d", entry));
    try std.testing.expect(!matchesFlag("--format", entry));
}
