const dialect_enum = @import("../dialect/enum.zig");
const enums = @import("../types/enums.zig");
const color_mod = @import("../color.zig");

// ─── Command Types ─────────────────────────────────────────────

pub const Target = enums.Target;
pub const DiffFormat = enums.DiffFormat;
pub const StatsFormat = enums.StatsFormat;
pub const ColorMode = enums.ColorMode;

pub const LintFormat = enum { text, json, sarif };

pub const Command = union(enum) {
    compile: struct { input: ?[]const u8, output: ?[]const u8, trace: bool, stats: bool, check: bool, verbose_passes: bool, stream: bool = false, parallel: bool = false },
    validate: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    check: struct { input: ?[]const u8, stats: bool, verbose_passes: bool },
    stats: struct { input: ?[]const u8, format: StatsFormat = .text },
    diff: struct { old: []const u8, new: []const u8, trace: bool, stats: bool, format: DiffFormat, check: bool, summary: bool = false, from_sql: ?[]const u8 = null },
    migrate: struct { old: []const u8, new: []const u8, output: ?[]const u8, trace: bool, rollback: bool, stats: bool, dry_run: bool, format: DiffFormat, check: bool, name: ?[]const u8, dir: ?[]const u8, incremental: bool, summary: bool = false, graph: bool = false },
    migrate_status: struct { dir: ?[]const u8, json_errors: bool = false },
    reverse: struct { input: ?[]const u8, output: ?[]const u8, with_templates: bool, trace: bool, stats: bool, validate_only: bool, format: DiffFormat },
    docs: struct { input: ?[]const u8, output: ?[]const u8 },
    format_cmd: struct { input: ?[]const u8, output: ?[]const u8 },
    generate: struct { generator: []const u8, generators_str: ?[]const u8 = null, input: ?[]const u8, output: ?[]const u8, list: bool },
    init: struct { name: ?[]const u8, output: ?[]const u8 },
    completions: struct { shell: []const u8 },
    hooks: struct { hook_type: []const u8 },
    lint: struct { input: ?[]const u8 = null, input2: ?[]const u8 = null, json_errors: bool = false, strict: bool = false, format: LintFormat = .text, rules: ?[]const u8 = null },
    watch: struct { input: []const u8, interval_ms: u64 = 1000, output: ?[]const u8 = null, parallel: bool = false, trace: bool = false, stats: bool = false, json_errors: bool = false },
    version,
    help: struct { subcommand: ?[]const u8 = null },
};

pub const ParsedArgs = struct {
    dialect: dialect_enum.Dialect,
    dialect_was_explicit: bool = false,
    target: Target,
    command: Command,
    quiet: bool,
    strict: bool,
    json_errors: bool = false,
    import_paths: []const []const u8 = &.{},
    color: ColorMode = .auto,
    init_flag: bool = false,
    config_path: ?[]const u8 = null,
};

pub const ArgError = error{
    UnknownDialect,
    MissingDialectValue,
    UnknownTarget,
    MissingTargetValue,
    UnknownFormat,
    MissingFormatValue,
    MissingConfigValue,
    MissingImportPathValue,
    UnknownCommand,
    UnknownFlag,
    UnknownGenerator,
    UnknownShell,
    UnknownHookType,
    DiffMissingArgs,
    MigrateMissingArgs,
    MissingArgs,
};

/// Flags extracted from the global pass (shared by all subcommands).
pub const GlobalFlags = struct {
    dialect_was_explicit: bool,
    stats: bool,
    check: bool,
    dry_run: bool,
    strict: bool,
    verbose_passes: bool,
    json_errors: bool,
    color: ColorMode,
    format: DiffFormat,
    validate_only: bool,
    quiet: bool,
    import_paths: []const []const u8,
    summary: bool = false,
    config_path: ?[]const u8 = null,
};

// ─── Command Registry ─────────────────────────────────────────

pub const CommandInfo = struct {
    name: []const u8,
    args: []const u8,
    description: []const u8,
};

pub const COMMAND_REGISTRY = [_]CommandInfo{
    .{ .name = "validate", .args = "[input.ss]", .description = "Validate .ss schema (no output)" },
    .{ .name = "check", .args = "[input.ss]", .description = "Check schema validity (exit 1 on error)" },
    .{ .name = "stats", .args = "[input.ss]", .description = "Print schema statistics (table/field/view counts)" },
    .{ .name = "diff", .args = "<old.ss> <new.ss>", .description = "Show schema differences" },
    .{ .name = "migrate", .args = "<old.ss> <new.ss> [--name <label>] [--dir <path>] [--incremental] [--graph]", .description = "Generate ALTER TABLE migration SQL" },
    .{ .name = "reverse", .args = "[input.sql]", .description = "Reverse SQL DDL to .ss schema" },
    .{ .name = "docs", .args = "[input.ss]", .description = "Generate Markdown documentation" },
    .{ .name = "format", .args = "[input.ss]", .description = "Auto-format .ss schema file" },
    .{ .name = "generate", .args = "<generator> [input.ss]", .description = "Generate output in specified format" },
    .{ .name = "init", .args = "[name]", .description = "Create a starter .ss schema file" },
    .{ .name = "completions", .args = "<shell>", .description = "Generate shell completions (bash|zsh|fish|powershell)" },
    .{ .name = "hooks", .args = "<type>", .description = "Generate git hooks (pre-commit)" },
    .{ .name = "lint", .args = "[input.ss]", .description = "Lint schema for quality issues (missing PK, naming, etc.)" },
    .{ .name = "watch", .args = "<input.ss> [--interval <ms>] [--parallel]", .description = "Watch file and recompile on change" },
};

/// Known long flags for edit-distance suggestions.
pub const KNOWN_FLAGS = [_][]const u8{
    "--version",        "--help",        "--stats",       "--quiet",         "--check",    "--dry-run",
    "--dialect",        "--target",      "--format",      "--validate-only", "--strict",   "--json-errors",
    "--verbose-passes", "--import-path", "--trace",       "--rollback",      "--output",   "--list",
    "--name",           "--dir",         "--incremental", "--color",         "--init",     "--summary",
    "--config",         "--template",    "--graph",       "--stream",        "--interval", "--parallel",
    "--generators",     "--from-sql",
};
