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
        try initLintConfig(io);
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
    }) catch {
        fmt.printError("schema", "failed to compile schema");
        std.process.exit(1);
    };
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
            }) catch {
                fmt.printError("schema", "failed to compile schema");
                std.process.exit(1);
            };
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
                    if (r.severity == .warning) std.process.exit(1);
                }
            }
        } else {
            for (results.items) |r| {
                if (r.severity == .warning) std.process.exit(1);
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
            }) catch {
                fmt.printError("io", "failed to write fixed file");
                std.process.exit(1);
            };
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
    const lint_mod = @import("../lint.zig");
    const LintRule = lint_mod.LintConfig; // We need the rule enum
    _ = alloc;

    var buf = std.Io.Writer.Allocating.init(alloc);
    const w = &buf.writer;

    try w.writeAll("Available lint rules:\n\n");
    try w.writeAll("Rule                       Fixable  Description\n");
    try w.writeAll("─────────────────────────  ───────  ─────────────────────────────────────\n");

    const rules_info = [_]struct { name: []const u8, fixable: bool, desc: []const u8 }{
        .{ .name = "no-pk", .fixable = true, .desc = "Table has no primary key" },
        .{ .name = "naming", .fixable = false, .desc = "Table names should be singular (CamelCase → snake_case)" },
        .{ .name = "no-index-fk", .fixable = false, .desc = "Foreign key columns without an index" },
        .{ .name = "no-timestamps", .fixable = true, .desc = "Table missing create_at/update_at timestamps" },
        .{ .name = "wide-table", .fixable = false, .desc = "Table has more than 30 columns" },
        .{ .name = "enum-case", .fixable = false, .desc = "Custom type enum values should be UPPER_CASE" },
        .{ .name = "count", .fixable = false, .desc = "Table has more than 50 columns" },
        .{ .name = "fk-cascade", .fixable = false, .desc = "Foreign key without explicit ON DELETE/UPDATE actions" },
        .{ .name = "nullable-pk", .fixable = false, .desc = "Primary key column is nullable" },
        .{ .name = "orphan-type", .fixable = false, .desc = "Custom type defined but not used by any table" },
        .{ .name = "index-unused", .fixable = false, .desc = "Index on column not used in any FK" },
        .{ .name = "circular-fk", .fixable = false, .desc = "Circular foreign key dependency between tables" },
        .{ .name = "duplicate-index", .fixable = true, .desc = "Duplicate index on the same column(s)" },
        .{ .name = "empty-table", .fixable = true, .desc = "Table has no columns" },
        .{ .name = "table-comment", .fixable = false, .desc = "Table missing comment/description" },
        .{ .name = "serial-type", .fixable = false, .desc = "PostgreSQL-specific serial type (use n++ for portability)" },
        .{ .name = "table-name-length", .fixable = false, .desc = "Table name exceeds max length (default: 64)" },
        .{ .name = "column-length", .fixable = false, .desc = "String column without explicit length" },
        .{ .name = "index-column-missing", .fixable = false, .desc = "Index references column not in table" },
        .{ .name = "naming-prefix", .fixable = false, .desc = "Table name uses anti-pattern prefix (tbl_, t_, tb_)" },
        .{ .name = "fk-naming", .fixable = false, .desc = "FK column doesn't follow <table>_id convention" },
        .{ .name = "bool-default", .fixable = false, .desc = "Boolean column without explicit default" },
        .{ .name = "view-no-select", .fixable = false, .desc = "View has no SELECT statement" },
        .{ .name = "column-default-required", .fixable = false, .desc = "Non-PK non-nullable column without DEFAULT" },
        .{ .name = "index-naming", .fixable = false, .desc = "Index name doesn't follow <table>_<columns> convention" },
        .{ .name = "nullable-column-default", .fixable = false, .desc = "Nullable non-PK column without DEFAULT" },
        .{ .name = "timestamp-naming", .fixable = false, .desc = "Datetime column should be created_at/updated_at" },
        .{ .name = "enum-value-naming", .fixable = false, .desc = "Enum values should be UPPER_CASE" },
        .{ .name = "fk-null", .fixable = false, .desc = "Foreign key column is nullable" },
        .{ .name = "cross-dialect-types", .fixable = false, .desc = "MySQL-specific types not portable to other dialects" },
    };

    for (rules_info) |r| {
        try w.print("  {s:<26} {s:<9} {s}\n", .{ r.name, if (r.fixable) "yes" else "no", r.desc });
    }

    try w.print("\n{d} rules available. Use --rules <file> to customize.\n", .{rules_info.len});

    try w.flush();
    const output = try buf.toOwnedSlice();
    try io_mod.writeOutput(io, output, null, quiet);
}

// ─── --init: Generate starter .rune-lint.toml config ────────

fn initLintConfig(io: std.Io) !void {
    const config_content =
        \\# Rune lint configuration
        \\# All rules enabled by default. Disable specific rules below.
        \\# Use: rune lint schema.ss --rules .rune-lint.toml
        \\
        \\[rules]
        \\no-pk = true
        \\naming = true
        \\no-index-fk = true
        \\no-timestamps = true
        \\wide-table = true
        \\enum-case = true
        \\count = true
        \\fk-cascade = true
        \\nullable-pk = true
        \\orphan-type = true
        \\index-unused = true
        \\circular-fk = true
        \\duplicate-index = true
        \\empty-table = true
        \\table-comment = true
        \\serial-type = true
        \\table-name-length = true
        \\column-length = true
        \\index-column-missing = true
        \\naming-prefix = true
        \\fk-naming = true
        \\bool-default = true
        \\view-no-select = true
        \\column-default-required = true
        \\index-naming = true
        \\nullable-column-default = true
        \\timestamp-naming = true
        \\enum-value-naming = true
        \\fk-null = true
        \\cross-dialect-types = true
        \\
        \\# Set to false to disable a rule
        \\# Example: no-pk = false
        \\
    ;

    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = ".rune-lint.toml",
        .data = config_content,
    }) catch {
        fmt.printError("io", "failed to write .rune-lint.toml");
        std.process.exit(1);
    };
    std.debug.print("Created .rune-lint.toml\n", .{});
}
