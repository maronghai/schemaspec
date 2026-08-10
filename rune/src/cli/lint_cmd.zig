const std = @import("std");
const cli = @import("../cli.zig");
const forward = @import("../pipeline/forward.zig");
const io_mod = @import("../io.zig");
const version = @import("../version.zig");
const fmt = @import("../diagnostic/format.zig");
const LintFormat = @import("../cli/types.zig").LintFormat;

// ─── Lint Command Handler ────────────────────────────────────
// Extracted from main.zig to keep the dispatch table lean.
// Handles `rune lint` with all flags: --fix, --dry-run, --strict,
// --format, --json-errors, --rules, --show-rules, --init,
// diff-aware lint.

pub const LintCmd = struct {
    input: ?[]const u8 = null,
    input2: ?[]const u8 = null,
    json_errors: bool = false,
    strict: bool = false,
    format: LintFormat = .text,
    rules: ?[]const u8 = null,
    fix: bool = false,
    dry_run: bool = false,
    show_rules: bool = false,
    init_config: bool = false,
};

/// Format and output lint results in the requested format (sarif/json/text).
fn lintOutput(
    io: std.Io,
    alloc: std.mem.Allocator,
    results: anytype,
    format: LintFormat,
    json_errors: bool,
    input_path: ?[]const u8,
    use_color: bool,
    quiet: bool,
) !void {
    const lint_mod = @import("../lint.zig");
    if (format == .sarif) {
        const sarif = try lint_mod.formatLintSarif(alloc, results, version.VERSION, input_path);
        try io_mod.writeOutput(io, sarif, null, quiet);
    } else if (json_errors or format == .json) {
        const json = try lint_mod.formatLintJson(alloc, results);
        try io_mod.writeOutput(io, json, null, quiet);
    } else {
        const text = try lint_mod.formatLintResults(alloc, results, use_color);
        try io_mod.writeOutput(io, text, null, quiet);
    }
}

pub fn handleLint(io: std.Io, alloc: std.mem.Allocator, cmd: LintCmd, parsed: cli.ParsedArgs) !void {
    const lint_mod = @import("../lint.zig");

    // --show-rules: list all available rules and exit
    if (cmd.show_rules) {
        try showAllRules(alloc, io, parsed.quiet);
        return;
    }

    // --init: generate starter .rune-lint.toml config and exit
    if (cmd.init_config) {
        try initLintConfig(io, alloc);
        return;
    }

    // Load lint rules config if --rules specified
    var lint_cfg = lint_mod.LintConfig{};
    if (cmd.rules) |rules_path| {
        if (std.Io.Dir.cwd().readFileAlloc(io, rules_path, alloc, .unlimited)) |rules_data| {
            const rules_cfg = try lint_mod.parseLintRules(alloc, rules_data);
            lint_cfg = lint_mod.applyLintRules(lint_cfg, rules_cfg);
        } else |err| {
            fmt.printWarn("failed to load rules file");
            std.debug.print("  {s}: {s}\n", .{ rules_path, @errorName(err) });
        }
    }

    // Compile first schema
    const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse io_mod.STDIN_PATH);
    const pipeline = forward.compilePipeline(alloc, file_data, .{
        .io = io,
        .dialect = parsed.dialect,
        .json_errors = false,
    }) catch return error.DiagnosticsError;
    const results = try lint_mod.lintSchema(alloc, pipeline.resolved, lint_cfg);

    // When --fix is active, skip normal output (fix summary goes to stderr)
    if (!cmd.fix) {
        const use_color = parsed.color.shouldUseColor(io);
        // Diff-aware lint: if second file provided, compare results
        if (cmd.input2) |input2_path| {
            const file_data2 = try io_mod.readFileOrStdin(io, alloc, input2_path);
            const pipeline2 = forward.compilePipeline(alloc, file_data2, .{
                .io = io,
                .dialect = parsed.dialect,
                .json_errors = false,
            }) catch return error.DiagnosticsError;
            const results2 = try lint_mod.lintSchema(alloc, pipeline2.resolved, lint_cfg);
            const diff = try lint_mod.lintDiff(results.items, results2.items, alloc);
            try lintOutput(io, alloc, diff.added, cmd.format, cmd.json_errors, cmd.input2, use_color, parsed.quiet);
        } else {
            try lintOutput(io, alloc, results.items, cmd.format, cmd.json_errors, cmd.input, use_color, parsed.quiet);
        }
    }

    // Strict mode: exit 1 on any warnings
    if (cmd.strict) {
        if (cmd.input2) |input2_path| {
            const file_data2_s = try io_mod.readFileOrStdin(io, alloc, input2_path);
            const pipeline2_s = forward.compilePipeline(alloc, file_data2_s, .{
                .io = io,
                .dialect = parsed.dialect,
                .json_errors = false,
            }) catch null;
            if (pipeline2_s) |p2| {
                const results2_s = try lint_mod.lintSchema(alloc, p2.resolved, lint_cfg);
                const diff_s = try lint_mod.lintDiff(results.items, results2_s.items, alloc);
                for (diff_s.added) |r| {
                    if (r.severity == .warning) return error.StrictWarnings;
                }
            }
        } else {
            for (results.items) |r| {
                if (r.severity == .warning) return error.StrictWarnings;
            }
        }
    }

    // Lint auto-fix: apply fixes to source text
    if (cmd.fix and results.items.len > 0) {
        const fixed = try lint_mod.lintFix(alloc, file_data, results.items);
        if (cmd.dry_run) {
            try io_mod.writeOutput(io, fixed.source, null, parsed.quiet);
        } else if (cmd.input) |input_path| {
            std.Io.Dir.cwd().writeFile(io, .{
                .sub_path = input_path,
                .data = fixed.source,
            }) catch return error.AccessDenied;
        }
        for (fixed.fixes) |fix| {
            std.debug.print("fixed: [{s}] {s} — {s}\n", .{ fix.rule, fix.table, fix.description });
        }
        if (!parsed.quiet) {
            std.debug.print("Applied {d} fix(es)\n", .{fixed.fixes.len});
        }
    }
}

// ─── --show-rules: List all available lint rules ─────────────

fn showAllRules(alloc: std.mem.Allocator, io: std.Io, quiet: bool) !void {
    const rules_mod = @import("../lint/rules.zig");

    var buf = std.Io.Writer.Allocating.init(alloc);
    const w = &buf.writer;

    try w.writeAll("Available lint rules:\n\n");
    try w.writeAll("Rule                       Fixable  Description\n");
    try w.writeAll("─────────────────────────  ───────  ─────────────────────────────────────\n");

    for (rules_mod.RULE_INFO) |r| {
        try w.print("  {s:<26} {s:<9} {s}\n", .{ r.rule.name(), if (r.fixable) "yes" else "no", r.description });
    }

    try w.print("\n{d} rules available. Use --rules <file> to customize.\n", .{rules_mod.RULE_INFO.len});

    try w.flush();
    const output = try buf.toOwnedSlice();
    try io_mod.writeOutput(io, output, null, quiet);
}

// ─── --init: Generate starter .rune-lint.toml config ────────

fn initLintConfig(io: std.Io, alloc: std.mem.Allocator) !void {
    const rules_mod = @import("../lint/rules.zig");

    var buf = std.Io.Writer.Allocating.init(alloc);
    defer buf.deinit();
    const w = &buf.writer;

    try w.writeAll("# Rune lint configuration\n");
    try w.writeAll("# All rules enabled by default. Disable specific rules below.\n");
    try w.writeAll("# Use: rune lint schema.ss --rules .rune-lint.toml\n\n");
    try w.writeAll("[rules]\n");
    for (rules_mod.RULE_INFO) |r| {
        try w.print("{s} = true\n", .{r.rule.name()});
    }
    try w.writeAll("\n# Set to false to disable a rule\n");
    try w.writeAll("# Example: no-pk = false\n\n");

    const content = try buf.toOwnedSlice();
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = ".rune-lint.toml",
        .data = content,
    }) catch return error.AccessDenied;
    std.debug.print("Created .rune-lint.toml\n", .{});
}
