const dialect_enum = @import("../dialect/enum.zig");
const enums = @import("../types/enums.zig");
const color_mod = @import("../color.zig");

// ─── Command Types ─────────────────────────────────────────────

pub const Target = enums.Target;
pub const DiffFormat = enums.DiffFormat;
pub const StatsFormat = enums.StatsFormat;
pub const ColorMode = enums.ColorMode;

pub const LintFormat = enum { text, json, sarif };
pub const DocsFormat = enum { markdown, json };
pub const ExportFormat = enum { json, text, markdown };

pub const Command = union(enum) {
    compile: struct { input: ?[]const u8, output: ?[]const u8, trace: bool, stats: bool, check: bool, verbose_passes: bool, stream: bool = false, parallel: bool = false, cache: bool = false, cache_dir: ?[]const u8 = null },
    validate: struct { input: ?[]const u8, stats: bool, verbose_passes: bool, format: StatsFormat = .text, per_table: bool = false, fix: bool = false },
    check: struct { input: ?[]const u8, stats: bool, verbose_passes: bool, format: StatsFormat = .text },
    stats: struct { input: ?[]const u8, format: StatsFormat = .text, per_table: bool = false, audit: bool = false, min_score: ?u8 = null },
    diff: struct { old: []const u8, new: []const u8, trace: bool, stats: bool, format: DiffFormat, check: bool, summary: bool = false, from_sql: ?[]const u8 = null },
    migrate: struct { old: []const u8, new: []const u8, output: ?[]const u8, trace: bool, rollback: bool, stats: bool, dry_run: bool, format: DiffFormat, check: bool, name: ?[]const u8, dir: ?[]const u8, incremental: bool, summary: bool = false, graph: bool = false, no_lint: bool = false },
    migrate_status: struct { dir: ?[]const u8, json_errors: bool = false },
    reverse: struct { input: ?[]const u8, output: ?[]const u8, with_templates: bool, trace: bool, stats: bool, validate_only: bool, format: DiffFormat, check: bool = false },
    docs: struct { input: ?[]const u8, output: ?[]const u8, doc_format: DocsFormat = .markdown },
    export_cmd: struct { input: ?[]const u8, output: ?[]const u8, format: ExportFormat = .json },
    format_cmd: struct { input: ?[]const u8, output: ?[]const u8, check: bool = false, diff: bool = false, write: bool = false, dialect: ?dialect_enum.Dialect = null },
    generate: struct { generator: []const u8, generators_str: ?[]const u8 = null, input: ?[]const u8, output: ?[]const u8, list: bool, check: bool = false, dry_run: bool = false },
    init: struct { name: ?[]const u8, output: ?[]const u8, output_dir: ?[]const u8 = null, template: ?[]const u8 = null },
    completions: struct { shell: []const u8 },
    hooks: struct { hook_type: []const u8 },
    lint: struct { input: ?[]const u8 = null, input2: ?[]const u8 = null, json_errors: bool = false, strict: bool = false, format: LintFormat = .text, rules: ?[]const u8 = null, fix: bool = false, dry_run: bool = false, show_rules: bool = false, init_config: bool = false, include_views: bool = false, summary: bool = false },
    watch: struct { input: []const u8, interval_ms: u64 = 1000, output: ?[]const u8 = null, stream: bool = false, parallel: bool = false, trace: bool = false, stats: bool = false, json_errors: bool = false, recursive: bool = false },
    tune: struct { input: ?[]const u8 = null, dry_run: bool = false },
    lsp,
    version: struct { json: bool = false },
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
    .{ .name = "validate", .args = "[input.ss] [--fix]", .description = "Validate .ss schema (no output)" },
    .{ .name = "check", .args = "[input.ss]", .description = "Check schema validity (exit 1 on error)" },
    .{ .name = "stats", .args = "[input.ss]", .description = "Print schema statistics (table/field/view counts)" },
    .{ .name = "diff", .args = "<old.ss> <new.ss>", .description = "Show schema differences" },
    .{ .name = "migrate", .args = "<old.ss> <new.ss> [--name <label>] [--dir <path>] [--incremental] [--graph]", .description = "Generate ALTER TABLE migration SQL" },
    .{ .name = "reverse", .args = "[input.sql]", .description = "Reverse SQL DDL to .ss schema" },
    .{ .name = "docs", .args = "[input.ss]", .description = "Generate Markdown documentation" },
    .{ .name = "export", .args = "[input.ss] [--format json|text|markdown]", .description = "Export schema as structured data" },
    .{ .name = "format", .args = "[input.ss] [--check] [--diff] [--write] [--dialect <d>]", .description = "Auto-format .ss schema file" },
    .{ .name = "generate", .args = "<generator> [input.ss]", .description = "Generate output in specified format" },
    .{ .name = "init", .args = "[name] [--output-dir <dir>] [--template <name>]", .description = "Create a starter .ss schema file" },
    .{ .name = "completions", .args = "<shell>", .description = "Generate shell completions (bash|zsh|fish|powershell)" },
    .{ .name = "hooks", .args = "<type>", .description = "Generate git hooks (pre-commit)" },
    .{ .name = "lint", .args = "[input.ss] [--fix] [--dry-run] [--strict] [--summary] [--format json|sarif] [--rules <file>]", .description = "Lint schema for quality issues (46 rules)" },
    .{ .name = "watch", .args = "<input> [--interval <ms>] [--recursive] [--parallel]", .description = "Watch file/directory and recompile on change" },
    .{ .name = "tune", .args = "[input.ss] [--dry-run]", .description = "Extract common fields into templates" },
    .{ .name = "lsp", .args = "", .description = "Start LSP language server (stdio)" },
};

/// Known long flags for edit-distance suggestions.
pub const KNOWN_FLAGS = [_][]const u8{
    "--version",        "--help",          "--stats",       "--quiet",         "--check",      "--dry-run",
    "--dialect",        "--target",        "--format",      "--validate-only", "--strict",     "--json-errors",
    "--verbose-passes", "--import-path",   "--trace",       "--rollback",      "--output",     "--list",
    "--name",           "--dir",           "--incremental", "--color",         "--init",       "--summary",
    "--config",         "--template",      "--graph",       "--stream",        "--interval",   "--parallel",
    "--generators",     "--from-sql",      "--fix",         "--rules",         "--output-dir", "--recursive",
    "--per-table",      "--include-views", "--diff",        "--write",         "--audit",      "--cache",
    "--cache-dir",
};

// ─── Data-Driven Help System ──────────────────────────────────
// Per-command help details. Adding a new command = add entry to
// COMMAND_REGISTRY + add entry to COMMAND_HELP.

pub const CommandHelp = struct {
    usage: []const u8,
    description: []const u8,
    options: []const []const u8,
    examples: []const []const u8,
};

pub const COMMAND_HELP = [_]CommandHelp{
    .{
        .usage = "<old.ss> <new.ss>",
        .description = "Show schema differences",
        .options = &.{
            "  --format        Output format: text (default), json, sarif, markdown",
            "  -t, --trace     Print intermediate pipeline stages",
            "  -s, --stats     Print compilation statistics",
            "  --check         Exit 1 if there are differences",
            "  --from-sql      Compare against a SQL dump file instead of a .ss file",
            "  --summary, --stat Show summary only (no full diff)",
        },
        .examples = &.{
            "  rune diff old.ss new.ss              # Show schema differences",
            "  rune diff old.ss new.ss --format json # Diff as JSON",
            "  rune diff schema.ss --from-sql live.sql # Drift detection",
        },
    },
    .{
        .usage = "<old.ss> <new.ss> [--name <label>] [--dir <path>] [--incremental] [--graph]",
        .description = "Generate ALTER TABLE migration SQL",
        .options = &.{
            "  --format        Output format: text (default), json, sarif, markdown",
            "  -t, --trace     Print intermediate pipeline stages",
            "  -s, --stats     Print compilation statistics",
            "  --check         Exit 1 if there are differences",
            "  --rollback      Generate rollback SQL instead",
            "  --dry-run       Show SQL without writing to file",
            "  --summary, --stat Show summary only (no full SQL)",
            "  --graph         Show migration dependency graph",
            "  -o, --output    Output file path",
            "  --name          Migration name label",
            "  --dir           Migration output directory",
            "  --incremental   Generate incremental migration",
        },
        .examples = &.{
            "  rune migrate old.ss new.ss -o m.sql  # Generate migration SQL",
            "  rune migrate old.ss new.ss --rollback # Generate rollback SQL",
            "  rune migrate old.ss new.ss --graph    # Show dependency graph",
        },
    },
    .{
        .usage = "[input.sql]",
        .description = "Reverse SQL DDL to .ss schema",
        .options = &.{
            "  -T, --template  Extract shared templates",
            "  --format        Output format: text (default), json",
            "  -t, --trace     Print intermediate pipeline stages",
            "  -o, --output    Output file path",
            "  --validate-only Validate SQL without generating output",
            "  --check         CI gate (exit 1 on errors)",
        },
        .examples = &.{
            "  cat schema.sql | rune reverse -T      # Reverse with templates",
            "  rune reverse schema.sql -o out.ss     # Reverse to file",
        },
    },
    .{
        .usage = "<generator> [input.ss]",
        .description = "Generate output in specified format",
        .options = &.{
            "  --list, -l      List available generators",
            "  -o, --output    Output file path",
            "  --dry-run       Preview output without writing to file",
            "  --generators    Comma-separated list for batch generation",
            "  --check         Generator health validation",
        },
        .examples = &.{
            "  rune generate json-schema schema.ss  # Generate JSON Schema",
            "  rune generate --list                 # Show available generators",
            "  rune generate --generators prisma,drizzle schema.ss  # Batch",
        },
    },
    .{
        .usage = "[input.ss]",
        .description = "Validate .ss schema (no output)",
        .options = &.{
            "  -s, --stats     Print compilation statistics",
            "  --per-table     Show per-table field/constraint breakdown",
            "  --format        Output format: text (default), json, sarif",
            "  --verbose-passes Print semantic pass execution details",
            "  --strict        Treat warnings as errors (for CI/CD)",
        },
        .examples = &.{
            "  rune validate schema.ss              # Validate schema",
            "  rune validate schema.ss -s           # Validate with stats",
            "  rune validate schema.ss --fix        # Validate and auto-fix issues",
            "  rune validate schema.ss --format json # Validate as JSON",
        },
    },
    .{
        .usage = "[input.ss]",
        .description = "Check schema validity (exit 1 on error)",
        .options = &.{
            "  -s, --stats     Print compilation statistics",
            "  --format        Output format: text (default), json",
            "  --verbose-passes Print semantic pass execution details",
        },
        .examples = &.{
            "  rune check schema.ss                 # Check validity",
            "  rune check schema.ss --format json   # Check as JSON",
        },
    },
    .{
        .usage = "[input.ss]",
        .description = "Print schema statistics (table/field/view counts)",
        .options = &.{
            "  --format        Output format: text (default), json, markdown",
            "  --per-table     Show per-table breakdown",
            "  --audit         Run schema health analysis with recommendations",
            "  --min-score N   Exit 1 if health score < N (with --audit, for CI gates)",
        },
        .examples = &.{
            "  rune stats schema.ss                 # Print stats",
            "  rune stats schema.ss --format json   # Stats as JSON",
            "  rune stats schema.ss --per-table     # Per-table breakdown",
            "  rune stats schema.ss --audit         # Schema health audit",
            "  rune stats schema.ss --audit --min-score 80  # CI quality gate",
        },
    },
    .{
        .usage = "[input.ss] [--output-dir <dir>] [--template <name>]",
        .description = "Create a starter .ss schema file",
        .options = &.{
            "  -d, --dialect   Target dialect: mysql (default), pg, sqlite, mssql, oracle, db2",
            "  -o, --output    Output file path",
            "  --output-dir    Output directory (creates if needed)",
            "  --template      Schema template: default (default), blog, ecommerce, rest-api",
        },
        .examples = &.{
            "  rune init myapp                      # Default starter schema",
            "  rune init myapp --template blog      # Blog schema",
            "  rune init myapp --template ecommerce # E-commerce schema",
        },
    },
    .{
        .usage = "<shell>",
        .description = "Generate shell completions (bash|zsh|fish|powershell)",
        .options = &.{},
        .examples = &.{
            "  rune completions bash                # Bash completions",
            "  rune completions zsh                 # Zsh completions",
        },
    },
    .{
        .usage = "<type>",
        .description = "Generate git hooks (pre-commit)",
        .options = &.{
            "  type            Hook type: pre-commit (default)",
        },
        .examples = &.{
            "  rune hooks pre-commit > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit",
        },
    },
    .{
        .usage = "[input.ss] [--fix] [--dry-run] [--strict] [--format json|sarif] [--rules <file>]",
        .description = "Lint schema for quality issues (60 rules)",
        .options = &.{
            "  --json-errors   Output results as JSON (machine-readable)",
            "  --strict        Exit 1 if any warnings found (for CI/CD)",
            "  --format        Output format: text (default), json, sarif",
            "  --summary       Show only summary line (N warning(s), M error(s))",
            "  --rules         Path to rune-lint.toml rules file",
            "  --show-rules    List all available rules with descriptions",
            "  --init          Generate starter .rune-lint.toml config file",
            "  --fix           Auto-fix fixable issues (11 rules)",
            "  --dry-run       Preview fixes without writing (with --fix)",
            "  --include-views Enable view-related lint rules",
        },
        .examples = &.{
            "  rune lint schema.ss                # Lint schema",
            "  rune lint schema.ss --json-errors  # Lint as JSON",
            "  rune lint schema.ss --strict       # Lint, exit 1 on warnings",
            "  rune lint schema.ss --summary      # Show summary only",
            "  rune lint old.ss new.ss            # Diff-aware lint",
            "  rune lint --show-rules             # List all rules",
            "  rune lint --init                   # Generate config",
            "  rune lint schema.ss --fix          # Auto-fix issues",
        },
    },
    .{
        .usage = "<input> [--interval <ms>] [--recursive] [--parallel]",
        .description = "Watch file/directory and recompile on change",
        .options = &.{
            "  --interval      Polling interval in milliseconds (default: 1000)",
            "  --recursive     Watch directory recursively for all .ss files",
            "  --parallel      Parallel streaming compilation",
            "  --stream        Streaming compilation",
            "  -d, --dialect   Target SQL dialect",
            "  --target        Output format: sql (default), json-schema",
            "  -o, --output    Output file path",
            "  -t, --trace     Print intermediate pipeline stages",
            "  -s, --stats     Print compilation statistics",
            "  --json-errors   Output diagnostics as JSON",
        },
        .examples = &.{
            "  rune watch schema.ss                  # Watch with default 1s interval",
            "  rune watch schema.ss --interval 500   # Watch with 500ms interval",
            "  rune watch schema.ss -d pg            # Watch and compile to PostgreSQL",
            "  rune watch ./schemas --recursive      # Watch all .ss files in directory",
        },
    },
    .{
        .usage = "[input.ss] [--dry-run]",
        .description = "Extract common fields into templates",
        .options = &.{
            "  --dry-run       Preview changes without modifying the file",
        },
        .examples = &.{
            "  rune tune schema.ss            # Extract templates, rewrite file",
            "  rune tune schema.ss --dry-run  # Preview changes only",
        },
    },
    .{
        .usage = "[input.ss] [--check] [--diff] [--write] [--dialect <d>]",
        .description = "Auto-format .ss schema file",
        .options = &.{
            "  --check         Exit 1 if formatting changes are needed",
            "  --diff          Show formatting differences without applying",
            "  --write         Format and write back to the input file in-place",
            "  -d, --dialect   Target SQL dialect for dialect-aware formatting",
            "  -o, --output    Output file path (default: stdout)",
        },
        .examples = &.{
            "  rune format schema.ss --write            # Format in-place",
            "  rune format schema.ss --write -d pg      # Format in-place with PostgreSQL keywords",
            "  rune format schema.ss -o out.ss          # Format to file",
            "  rune format schema.ss --check            # Check if formatting needed",
            "  rune format schema.ss --diff             # Show what would change",
        },
    },
    .{
        .usage = "[input.ss] [--format json|text|markdown]",
        .description = "Export schema as structured data",
        .options = &.{
            "  --format        Output format: json (default), text, markdown",
            "  -o, --output    Output file path",
        },
        .examples = &.{
            "  rune export schema.ss                # Export as JSON",
            "  rune export schema.ss --format text  # Export as text summary",
        },
    },
    .{
        .usage = "",
        .description = "Start LSP language server (stdio)",
        .options = &.{},
        .examples = &.{},
    },
    .{
        .usage = "",
        .description = "Print version and exit",
        .options = &.{
            "  --json          Output version as JSON",
        },
        .examples = &.{},
    },
    .{
        .usage = "[subcommand]",
        .description = "Show help for a command",
        .options = &.{},
        .examples = &.{},
    },
};
