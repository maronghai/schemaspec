const std = @import("std");
const forward = @import("forward.zig");
const compilePipeline = forward.compilePipeline;
const Stats = forward.Stats;
const computeStats = forward.computeStats;
const printStats = forward.printStats;
const io_mod = @import("../io.zig");
const stats_mod = @import("stats.zig");
const StatsFormat = @import("../types/enums.zig").StatsFormat;
const fmt = @import("../diagnostic/format.zig");
const lint_mod = @import("../lint.zig");
pub const formatValidateResult = @import("export.zig").formatValidateResult;
pub const formatValidateSarif = @import("export.zig").formatValidateSarif;

// ─── Validation Handlers ─────────────────────────────────────
// Handles `rune validate` and `rune check` CLI commands.
// Extracted from handlers.zig for single-responsibility.

/// Configuration for `handleValidate` and `handleCheck`.
/// Replaces 9 positional parameters with a named struct.
pub const ValidateConfig = struct {
    stats: bool = false,
    verbose_passes: bool = false,
    json_errors: bool = false,
    strict: bool = false,
    format: StatsFormat = .text,
    per_table: bool = false,
    /// Apply lint auto-fixes to the source file.
    fix: bool = false,
    /// Input file path (needed for --fix to write back).
    input: ?[]const u8 = null,
};

/// Validate a .ss file — runs the full semantic pipeline and reports diagnostics.
/// With strict=false (default validate): always succeeds (exit 0), prints errors but doesn't fail.
/// With strict=true (check mode): returns error.DiagnosticsError on errors (exit 1).
/// With json_errors=true or format=.json: outputs JSON result instead of text.
/// With format=.sarif: outputs SARIF result for CI/CD integration.
pub fn handleValidate(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ValidateConfig) !void {
    const result = compilePipeline(alloc, file_data, .{ .verbose_passes = cfg.verbose_passes, .json_errors = cfg.json_errors }) catch |err| {
        if (err == error.DiagnosticsError or err == error.SemanticError) {
            if (cfg.json_errors or cfg.format == .json) {
                const json = try formatValidateResult(alloc, false, Stats.zero, 1);
                try io_mod.writeOutput(io, json, null, false);
            } else if (cfg.format == .sarif) {
                const sarif = try formatValidateSarif(alloc, false, 1);
                try io_mod.writeOutput(io, sarif, null, false);
            } else {
                fmt.printError("schema", "has errors");
            }
            if (cfg.strict) return err;
            return;
        }
        return err;
    };
    const s = computeStats(result.resolved);
    if (cfg.json_errors or cfg.format == .json) {
        const json = try formatValidateResult(alloc, !result.partial, s, if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0);
        try io_mod.writeOutput(io, json, null, false);
    } else if (cfg.format == .sarif) {
        const error_count: u32 = if (result.partial) @min(result.tree.error_count, std.math.maxInt(u32)) else 0;
        const sarif = try formatValidateSarif(alloc, !result.partial, error_count);
        try io_mod.writeOutput(io, sarif, null, false);
    } else {
        if (cfg.stats or cfg.per_table) {
            printStats(s);
        }
        if (cfg.per_table) {
            const table_stats = stats_mod.computePerTableStats(result.resolved);
            stats_mod.printPerTableStats(table_stats);
        }
        // Show summary line for text output
        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Tables: {d}, Fields: {d}, Views: {d}, Indexes: {d}, FKs: {d}\n", .{
            s.tables, s.fields, s.views, s.indexes, s.foreign_keys,
        }), null, false);

        if (result.partial) {
            fmt.printError("schema", "has errors (partial)");
            if (cfg.strict) return error.DiagnosticsError;
            return;
        }
        // In strict mode, also run lint and fail on warnings
        if (cfg.strict) {
            const lint_results = try lint_mod.lintSchema(alloc, result.resolved, .{});
            for (lint_results.items) |r| {
                if (r.severity == .warning) return error.StrictWarnings;
            }
        }
        // Apply lint auto-fixes when --fix is active
        if (cfg.fix and cfg.input != null) {
            const lint_results = try lint_mod.lintSchema(alloc, result.resolved, .{});
            if (lint_results.items.len > 0) {
                const fixed = try lint_mod.lintFix(alloc, file_data, lint_results.items);
                if (cfg.input) |input_path| {
                    std.Io.Dir.cwd().writeFile(io, .{
                        .sub_path = input_path,
                        .data = fixed.source,
                    }) catch return error.AccessDenied;
                }
                for (fixed.fixes) |fix| {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "fixed: [{s}] {s} — {s}\n", .{ fix.rule, fix.table, fix.description }), null, false);
                }
                if (!cfg.json_errors and cfg.format != .json and cfg.format != .sarif) {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Applied {d} fix(es)\n", .{fixed.fixes.len}), null, false);
                }
            } else {
                if (!cfg.json_errors and cfg.format != .json and cfg.format != .sarif) {
                    fmt.printOk("schema is valid (no fixes needed)");
                }
            }
        } else {
            fmt.printOk("schema is valid");
        }
    }
}

/// Check a .ss file — CI gate mode. Fails on any schema error.
pub fn handleCheck(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ValidateConfig) !void {
    return handleValidate(io, alloc, file_data, .{ .stats = cfg.stats, .verbose_passes = cfg.verbose_passes, .json_errors = cfg.json_errors, .strict = true, .format = cfg.format, .per_table = false });
}

// ─── Tests ───────────────────────────────────────────────────

test "ValidateConfig: defaults" {
    const cfg = ValidateConfig{};
    try std.testing.expect(!cfg.stats);
    try std.testing.expect(!cfg.verbose_passes);
    try std.testing.expect(!cfg.json_errors);
    try std.testing.expect(!cfg.strict);
    try std.testing.expect(cfg.format == .text);
    try std.testing.expect(!cfg.per_table);
    try std.testing.expect(!cfg.fix);
    try std.testing.expect(cfg.input == null);
}

test "ValidateConfig: custom values" {
    const cfg = ValidateConfig{
        .stats = true,
        .strict = true,
        .json_errors = true,
        .per_table = true,
        .fix = true,
    };
    try std.testing.expect(cfg.stats);
    try std.testing.expect(cfg.strict);
    try std.testing.expect(cfg.json_errors);
    try std.testing.expect(cfg.per_table);
    try std.testing.expect(cfg.fix);
}
