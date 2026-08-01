const std = @import("std");
const cli = @import("cli.zig");
const forward = @import("pipeline/forward.zig");
const diff_pipe = @import("pipeline/diff.zig");
const reverse_pipe = @import("pipeline/reverse.zig");
const io_mod = @import("io.zig");
const version = @import("version.zig");
const docs = @import("docs.zig");
const generator = @import("generator.zig");

// ─── Entry Point ───────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var args = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer arg_it.deinit();
    while (arg_it.next()) |arg| {
        try args.append(alloc, arg);
    }
    const arg_list = try args.toOwnedSlice(alloc);

    // No args: check stdin pipe vs interactive terminal
    if (arg_list.len < 2) {
        const is_tty = std.Io.File.stdin().isTty(init.io) catch true;
        if (is_tty) {
            cli.printUsage();
            std.process.exit(1);
        }
        return forward.handleCompileRequest(init.io, alloc, .{});
    }

    const parsed = cli.parseArgs(alloc, arg_list) catch |err| {
        if (err == error.OutOfMemory) {
            std.debug.print("error: out of memory\n", .{});
        } else if (err == error.UnknownFlag) {
            if (cli.last_unknown_flag) |flag| {
                std.debug.print("error: unknown flag '{s}'. Run 'rune --help' for usage.\n", .{flag});
            } else {
                std.debug.print("error: unknown flag. Run 'rune --help' for usage.\n", .{});
            }
        } else {
            const cli_err: cli.ArgError = @errorCast(err);
            std.debug.print("error: {s}\n", .{cliArgErrorMessage(cli_err)});
        }
        std.process.exit(1);
    };
    return dispatch(init.io, alloc, parsed) catch |err| {
        switch (err) {
            error.DiagnosticsError, error.SemanticError, error.SqlParseError, error.ReverseDiagnosticsError => {
                // Error already printed by the compiler module
            },
            error.CheckFailed => {
                if (!parsed.quiet) {
                    std.debug.print("check failed: schema has differences\n", .{});
                }
                std.process.exit(1);
            },
            else => {
                switch (err) {
                    error.OutOfMemory => std.debug.print("error: out of memory\n", .{}),
                    error.FileNotFound => std.debug.print("error: file not found\n", .{}),
                    error.AccessDenied => std.debug.print("error: access denied\n", .{}),
                    error.IsDir => std.debug.print("error: expected a file, got a directory\n", .{}),
                    error.NotDir => std.debug.print("error: expected a directory, got a file\n", .{}),
                    else => std.debug.print("error: {s}\n", .{@errorName(err)}),
                }
            },
        }
        std.process.exit(1);
    };
}

// ─── Command Dispatch ──────────────────────────────────────────

fn dispatch(io: std.Io, alloc: std.mem.Allocator, parsed: cli.ParsedArgs) !void {
    switch (parsed.command) {
        .version => {
            version.printVersion();
            return;
        },
        .help => {
            cli.printUsage();
            return;
        },
        .compile => |cmd| {
            // Determine input path (null = stdin, "-" = stdin, else = file)
            const input_path = if (cmd.input) |path|
                if (std.mem.eql(u8, path, "-")) null else path
            else
                null;

            // Determine output format
            const format: forward.OutputFormat = switch (parsed.target) {
                .sql => .sql,
                .json_schema => .json_schema,
            };

            return forward.handleCompileRequest(io, alloc, .{
                .input = input_path,
                .output_path = cmd.output,
                .trace = cmd.trace,
                .dialect = parsed.dialect,
                .format = format,
                .stats = cmd.stats,
                .check = cmd.check,
                .quiet = parsed.quiet,
                .verbose_passes = cmd.verbose_passes,
                .json_errors = parsed.json_errors,
                .import_paths = parsed.import_paths,
            });
        },
        .validate => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleValidate(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors, parsed.strict);
        },
        .check => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleCheck(io, alloc, file_data, cmd.stats, cmd.verbose_passes, parsed.json_errors);
        },
        .stats => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            return forward.handleStats(io, alloc, file_data);
        },
        .diff => |cmd| {
            return switch (cmd.format) {
                .text => diff_pipe.handleDiff(io, alloc, cmd.old, cmd.new, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
                .json => diff_pipe.handleDiffJson(io, alloc, cmd.old, cmd.new, null, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
                .sarif => diff_pipe.handleDiffSarif(io, alloc, cmd.old, cmd.new, parsed.dialect, cmd.trace, cmd.stats, cmd.check),
            };
        },
        .migrate => |cmd| {
            return switch (cmd.format) {
                .text => diff_pipe.handleMigrate(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.rollback, cmd.stats, cmd.dry_run),
                .json => diff_pipe.handleMigrateDiffJson(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.stats),
                .sarif => diff_pipe.handleMigrate(io, alloc, cmd.old, cmd.new, cmd.output, parsed.dialect, cmd.trace, cmd.rollback, cmd.stats, cmd.dry_run),
            };
        },
        .reverse => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            const name = cmd.input orelse "<stdin>";
            return reverse_pipe.handleReverse(io, alloc, file_data, name, cmd.output, cmd.with_templates, parsed.dialect, cmd.trace, cmd.stats, cmd.validate_only, cmd.format);
        },
        .docs => |cmd| {
            const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
            const pipeline = try forward.compilePipeline(alloc, file_data);
            const markdown = try docs.generate(alloc, pipeline.resolved);
            try io_mod.writeOutput(io, markdown, cmd.output, parsed.quiet);
        },
        .generate => |cmd| {
            if (cmd.list) {
                generator.listAll();
                return;
            }
            if (generator.get(cmd.generator)) |gen| {
                const file_data = try io_mod.readFileOrStdin(io, alloc, cmd.input orelse "-");
                const pipeline = try forward.compilePipeline(alloc, file_data);
                const typed = try @import("types/type_resolver.zig").TypeResolver.resolve(alloc, pipeline.resolved, parsed.dialect);
                const output_text = try gen.generate(alloc, typed, parsed.dialect);
                try io_mod.writeOutput(io, output_text, cmd.output, parsed.quiet);
            } else {
                std.debug.print("error: unknown generator '{s}'. Run 'rune generate --list' for available generators.\n", .{cmd.generator});
                std.process.exit(1);
            }
        },
        .init => |cmd| {
            return handleInit(io, alloc, cmd.name, cmd.output);
        },
        .completions => |cmd| {
            return handleCompletions(io, alloc, cmd.shell);
        },
    }
}

// ─── Error Messages ───────────────────────────────────────────

/// Map CLI argument errors to human-readable messages.
fn cliArgErrorMessage(err: cli.ArgError) []const u8 {
    return switch (err) {
        error.UnknownDialect => "unknown dialect, expected one of: mysql, pg, postgres, sqlite, mssql, oracle",
        error.MissingDialectValue => "--dialect requires a value, expected one of: mysql, pg, postgres, sqlite, mssql, oracle",
        error.UnknownTarget => "unknown target, expected one of: sql, json-schema",
        error.MissingTargetValue => "--target requires a value, expected one of: sql, json-schema",
        error.UnknownFormat => "unknown format, expected one of: text, json, sarif",
        error.DiffMissingArgs => "diff requires two arguments: <old.ss> <new.ss>",
        error.MigrateMissingArgs => "migrate requires two arguments: <old.ss> <new.ss>",
        error.UnknownCommand => "unknown command. Run 'rune --help' for usage.",
        error.UnknownFlag => "unknown flag. Run 'rune --help' for usage.",
    };
}

// ─── `rune init` ──────────────────────────────────────────────

const STARTER_SCHEMA =
    \\; Starter schema — edit this file to define your database
    \\
    \\; ── Schema ─────────────────────────────────────────────
    \\
    \\$ mydb
    \\
    \\; ── Tables ─────────────────────────────────────────────
    \\
    \\; Users table
    \\# users
    \\id       n++
    \\email    s128 *
    \\name     s64
    \\role     e(editor,viewer) =viewer
    \\@ email
    \\
    \\; Posts table
    \\# posts
    \\id         n++
    \\title      s256 *
    \\body       S
    \\author_id  n *            ; FK → users.id (auto-inferred from _id suffix)
    \\status     e(draft,published,archived) =draft
    \\@ author_id
    \\@ status
    \\
    \\; Comments table
    \\# comments
    \\id        n++
    \\post_id   n *              ; FK → posts.id
    \\author_id n                ; FK → users.id
    \\body      S *
    \\@ post_id
    \\
;

fn handleInit(io: std.Io, alloc: std.mem.Allocator, name: ?[]const u8, output: ?[]const u8) !void {
    const filename = name orelse "schema";
    const out_path = output orelse blk: {
        // Build path: <name>.ss
        const path = try std.fmt.allocPrint(alloc, "{s}.ss", .{filename});
        break :blk path;
    };
    try io_mod.writeOutput(io, STARTER_SCHEMA, out_path, false);
    std.debug.print("Created {s}\n", .{out_path});
    std.debug.print("Edit this file, then run: rune {s}\n", .{out_path});
}

// ─── `rune completions` ───────────────────────────────────────

fn handleCompletions(io: std.Io, _: std.mem.Allocator, shell: []const u8) !void {
    if (std.mem.eql(u8, shell, "bash")) {
        try io_mod.writeOutput(io, COMPLETIONS_BASH, null, false);
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try io_mod.writeOutput(io, COMPLETIONS_ZSH, null, false);
    } else if (std.mem.eql(u8, shell, "fish")) {
        try io_mod.writeOutput(io, COMPLETIONS_FISH, null, false);
    } else if (std.mem.eql(u8, shell, "powershell")) {
        try io_mod.writeOutput(io, COMPLETIONS_POWERSHELL, null, false);
    } else {
        std.debug.print("error: unknown shell '{s}', expected: bash, zsh, fish, powershell\n", .{shell});
        std.process.exit(1);
    }
}

const COMPLETIONS_BASH =
    \\# Bash completions for rune
    \\# Source this file: source <(rune completions bash)
    \\
    \\_rune_completions() {
    \\    local cur prev commands
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    commands="init validate check stats diff migrate reverse docs generate completions"
    \\
    \\    if [[ ${cur} == -* ]]; then
    \\        COMPREPLY=( $(compgen -W "--help --version --dialect --target --trace --stats --check --quiet --strict --json-errors --verbose-passes --import-path --rollback --output --dry-run --validate-only --format --list --template" -- ${cur}) )
    \\        return 0
    \\    fi
    \\
    \\    if [[ ${COMP_CWORD} -eq 1 ]]; then
    \\        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
    \\        return 0
    \\    fi
    \\
    \\    case "${COMP_WORDS[1]}" in
    \\        generate)
    \\            if [[ ${COMP_CWORD} -eq 2 ]]; then
    \\                COMPREPLY=( $(compgen -W "json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql" -- ${cur}) )
    \\            elif [[ ${COMP_CWORD} -eq 3 ]]; then
    \\                COMPREPLY=( $(compgen -f -X '!*.ss' -- ${cur}) )
    \\            fi
    \\            ;;
    \\        diff|migrate)
    \\            COMPREPLY=( $(compgen -f -X '!*.ss' -- ${cur}) )
    \\            ;;
    \\        reverse)
    \\            COMPREPLY=( $(compgen -f -X '!*.sql' -- ${cur}) )
    \\            ;;
    \\        completions)
    \\            COMPREPLY=( $(compgen -W "bash zsh fish powershell" -- ${cur}) )
    \\            ;;
    \\        validate|check|stats|docs|init)
    \\            COMPREPLY=( $(compgen -f -X '!*.ss' -- ${cur}) )
    \\            ;;
    \\    esac
    \\    return 0
    \\}
    \\complete -F _rune_completions rune
    \\
;

const COMPLETIONS_ZSH =
    \\# Zsh completions for rune
    \\# Source this file: source <(rune completions zsh)
    \\# Or add to ~/.zshrc: eval "$(rune completions zsh)"
    \\
    \\#compdef rune
    \\
    \\_rune() {
    \\    local -a commands
    \\    commands=(
    \\        'init:Create a starter .ss schema file'
    \\        'validate:Validate .ss schema (no output)'
    \\        'check:Check schema validity (exit 1 on error)'
    \\        'stats:Print schema statistics'
    \\        'diff:Show schema differences'
    \\        'migrate:Generate ALTER TABLE migration SQL'
    \\        'reverse:Reverse SQL DDL to .ss schema'
    \\        'docs:Generate Markdown documentation'
    \\        'generate:Generate output in specified format'
    \\        'completions:Generate shell completions'
    \\    )
    \\
    \\    _arguments -C \
    \\        '1:command:->command' \
    \\        '*::arg:->args'
    \\
    \\    case $state in
    \\        command)
    \\            _describe 'command' commands
    \\            ;;
    \\        args)
    \\            case ${words[1]} in
    \\                generate)
    \\                    _arguments \
    \\                        '1:generator:->generator' \
    \\                        '2:file:_files -g "*.ss"'
    \\                    case $state in
    \\                        generator)
    \\                            local -a gens
    \\                            gens=(json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql)
    \\                            _describe 'generator' gens
    \\                            ;;
    \\                    esac
    \\                    ;;
    \\                completions)
    \\                    _arguments '1:shell:(bash zsh fish powershell)'
    \\                    ;;
    \\                diff|migrate)
    \\                    _arguments '1:old:_files -g "*.ss"' '2:new:_files -g "*.ss"'
    \\                    ;;
    \\                reverse)
    \\                    _arguments '1:file:_files -g "*.sql"'
    \\                    ;;
    \\                *)
    \\                    _files -g '*.ss'
    \\                    ;;
    \\            esac
    \\            ;;
    \\    esac
    \\}
    \\
    \\_rune "$@"
    \\
;

const COMPLETIONS_FISH =
    \\# Fish completions for rune
    \\# Install: rune completions fish > ~/.config/fish/completions/rune.fish
    \\
    \\# Subcommands
    \\complete -c rune -n __fish_use_subcommand -a init -d 'Create a starter .ss schema file'
    \\complete -c rune -n __fish_use_subcommand -a validate -d 'Validate .ss schema (no output)'
    \\complete -c rune -n __fish_use_subcommand -a check -d 'Check schema validity (exit 1 on error)'
    \\complete -c rune -n __fish_use_subcommand -a stats -d 'Print schema statistics'
    \\complete -c rune -n __fish_use_subcommand -a diff -d 'Show schema differences'
    \\complete -c rune -n __fish_use_subcommand -a migrate -d 'Generate ALTER TABLE migration SQL'
    \\complete -c rune -n __fish_use_subcommand -a reverse -d 'Reverse SQL DDL to .ss schema'
    \\complete -c rune -n __fish_use_subcommand -a docs -d 'Generate Markdown documentation'
    \\complete -c rune -n __fish_use_subcommand -a generate -d 'Generate output in specified format'
    \\complete -c rune -n __fish_use_subcommand -a completions -d 'Generate shell completions'
    \\
    \\# Global flags
    \\complete -c rune -l help -s h -d 'Show help'
    \\complete -c rune -l version -s v -d 'Show version'
    \\complete -c rune -l dialect -s d -r -d 'Target SQL dialect' -xa 'mysql pg postgres sqlite mssql sqlserver oracle ora'
    \\complete -c rune -l target -r -d 'Output format' -xa 'sql json-schema'
    \\complete -c rune -l trace -s t -d 'Print compilation trace'
    \\complete -c rune -l stats -s s -d 'Print compilation stats'
    \\complete -c rune -l check -d 'Check mode (exit 0 if valid)'
    \\complete -c rune -l quiet -s q -d 'Suppress non-error output'
    \\complete -c rune -l strict -d 'Strict mode (exit 1 on errors)'
    \\complete -c rune -l json-errors -d 'Emit diagnostics in JSON format'
    \\complete -c rune -l verbose-passes -d 'Show semantic pass details'
    \\complete -c rune -l import-path -r -d 'Additional search path for @import'
    \\complete -c rune -l output -r -d 'Output file path'
    \\complete -c rune -l format -r -d 'Output format' -xa 'text json sarif'
    \\
    \\# generate subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -a 'json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql' -d 'Generator'
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -F -r
    \\
    \\# completions subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish powershell' -d 'Shell'
    \\
    \\# File arguments
    \\complete -c rune -n '__fish_seen_subcommand_from validate check stats docs init' -F -r
    \\complete -c rune -n '__fish_seen_subcommand_from diff migrate' -F -r
    \\complete -c rune -n '__fish_seen_subcommand_from reverse' -F -r
    \\
;

const COMPLETIONS_POWERSHELL =
    \\# PowerShell completions for rune
    \\# Install: rune completions powershell > $(rune_root)/rune.psm1
    \\# Or: . $(rune completions powershell)
    \\
    \\Register-ArgumentCompleter -Native -CommandName 'rune' -ScriptBlock {
    \\    param($wordToComplete, $commandAst, $cursorPosition)
    \\
    \\    $commands = @(
    \\        [System.Management.Automation.CompletionResult]::new('init', 'init', 'ParameterValue', 'Create a starter .ss schema file')
    \\        [System.Management.Automation.CompletionResult]::new('validate', 'validate', 'ParameterValue', 'Validate .ss schema (no output)')
    \\        [System.Management.Automation.CompletionResult]::new('check', 'check', 'ParameterValue', 'Check schema validity (exit 1 on error)')
    \\        [System.Management.Automation.CompletionResult]::new('stats', 'stats', 'ParameterValue', 'Print schema statistics')
    \\        [System.Management.Automation.CompletionResult]::new('diff', 'diff', 'ParameterValue', 'Show schema differences')
    \\        [System.Management.Automation.CompletionResult]::new('migrate', 'migrate', 'ParameterValue', 'Generate ALTER TABLE migration SQL')
    \\        [System.Management.Automation.CompletionResult]::new('reverse', 'reverse', 'ParameterValue', 'Reverse SQL DDL to .ss schema')
    \\        [System.Management.Automation.CompletionResult]::new('docs', 'docs', 'ParameterValue', 'Generate Markdown documentation')
    \\        [System.Management.Automation.CompletionResult]::new('generate', 'generate', 'ParameterValue', 'Generate output in specified format')
    \\        [System.Management.Automation.CompletionResult]::new('completions', 'completions', 'ParameterValue', 'Generate shell completions')
    \\    )
    \\
    \\    $generators = @(
    \\        [System.Management.Automation.CompletionResult]::new('json-schema', 'json-schema', 'ParameterValue', 'JSON Schema (draft-07)')
    \\        [System.Management.Automation.CompletionResult]::new('sql-ddl', 'sql-ddl', 'ParameterValue', 'SQL DDL')
    \\        [System.Management.Automation.CompletionResult]::new('prisma', 'prisma', 'ParameterValue', 'Prisma schema')
    \\        [System.Management.Automation.CompletionResult]::new('docs', 'docs', 'ParameterValue', 'Markdown documentation')
    \\        [System.Management.Automation.CompletionResult]::new('drizzle', 'drizzle', 'ParameterValue', 'Drizzle ORM')
    \\        [System.Management.Automation.CompletionResult]::new('typeorm', 'typeorm', 'ParameterValue', 'TypeORM entity')
    \\        [System.Management.Automation.CompletionResult]::new('sqlalchemy', 'sqlalchemy', 'ParameterValue', 'SQLAlchemy model')
    \\        [System.Management.Automation.CompletionResult]::new('knex', 'knex', 'ParameterValue', 'Knex.js migration')
    \\        [System.Management.Automation.CompletionResult]::new('openapi', 'openapi', 'ParameterValue', 'OpenAPI 3.1 spec')
    \\        [System.Management.Automation.CompletionResult]::new('graphql', 'graphql', 'ParameterValue', 'GraphQL types')
    \\    )
    \\
    \\    $shells = @(
    \\        [System.Management.Automation.CompletionResult]::new('bash', 'bash', 'ParameterValue', 'Bash')
    \\        [System.Management.Automation.CompletionResult]::new('zsh', 'zsh', 'ParameterValue', 'Zsh')
    \\        [System.Management.Automation.CompletionResult]::new('fish', 'fish', 'ParameterValue', 'Fish')
    \\        [System.Management.Automation.CompletionResult]::new('powershell', 'powershell', 'ParameterValue', 'PowerShell')
    \\    )
    \\
    \\    $flags = @('--help', '--version', '--dialect', '--target', '--trace', '--stats', '--check', '--quiet', '--strict', '--json-errors', '--verbose-passes', '--import-path', '--output', '--format', '--rollback', '--dry-run', '--validate-only', '--list', '--template', '-h', '-v', '-d', '-t', '-s', '-q')
    \\
    \\    $cursorToken = $commandAst.CommandElements[-1].Value
    \\    $tokens = $commandAst.CommandElements | ForEach-Object { $_.Value }
    \\
    \\    if ($tokens.Count -le 1) {
    \\        return $commands
    \\    }
    \\
    \\    $subcmd = $tokens[1]
    \\    if ($subcmd -eq 'generate' -and $tokens.Count -eq 3) {
    \\        return $generators
    \\    }
    \\    if ($subcmd -eq 'completions' -and $tokens.Count -eq 3) {
    \\        return $shells
    \\    }
    \\
    \\    if ($cursorToken.StartsWith('-')) {
    \\        return $flags | Where-Object { $_ -like "$cursorToken*" } | ForEach-Object {
    \\            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    \\        }
    \\    }
    \\
    \\    return @( | ForEach-Object {
    \\        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    \\    })
    \\}
    \\
;
