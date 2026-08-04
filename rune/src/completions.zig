const std = @import("std");
const io_mod = @import("io.zig");
const dialect_enum = @import("dialect/enum.zig");

// ─── Shell Completions & Init ──────────────────────────────────
// Extracted from main.zig for single-responsibility.
// Contains the starter schema template and shell completion scripts.

// ─── `rune init` ──────────────────────────────────────────────

pub const STARTER_SCHEMA =
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
    \\email    s128
    \\name     s64
    \\role     e(editor,viewer) =viewer
    \\@ email
    \\
    \\; Posts table
    \\# posts
    \\id         n++
    \\title      s256
    \\body       S
    \\author_id  n              ; FK → users.id (auto-inferred from _id suffix)
    \\status     e(draft,published,archived) =draft
    \\@ author_id
    \\@ status
    \\
    \\; Comments table
    \\# comments
    \\id        n++
    \\post_id   n               ; FK → posts.id
    \\author_id n                ; FK → users.id
    \\body      S
    \\@ post_id
    \\
;

pub fn handleInit(io: std.Io, alloc: std.mem.Allocator, name: ?[]const u8, output: ?[]const u8, dialect: dialect_enum.Dialect) !void {
    const filename = name orelse "schema";
    const out_path = output orelse blk: {
        const path = try std.fmt.allocPrint(alloc, "{s}.ss", .{filename});
        break :blk path;
    };
    // Prepend dialect hint comment for the user
    const dialect_name = @tagName(dialect);
    const schema_with_hint = try std.fmt.allocPrint(alloc, "; Target dialect: {s}\n{s}", .{ dialect_name, STARTER_SCHEMA });
    try io_mod.writeOutput(io, schema_with_hint, out_path, false);
    std.debug.print("Created {s} (dialect: {s})\n", .{ out_path, dialect_name });
    std.debug.print("Edit this file, then run: rune {s} -d {s}\n", .{ out_path, dialect_name });
}

// ─── `rune completions` ───────────────────────────────────────

pub fn handleCompletions(io: std.Io, _: std.mem.Allocator, shell: []const u8) !void {
    if (std.mem.eql(u8, shell, "bash")) {
        try io_mod.writeOutput(io, COMPLETIONS_BASH, null, false);
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try io_mod.writeOutput(io, COMPLETIONS_ZSH, null, false);
    } else if (std.mem.eql(u8, shell, "fish")) {
        try io_mod.writeOutput(io, COMPLETIONS_FISH, null, false);
    } else if (std.mem.eql(u8, shell, "powershell")) {
        try io_mod.writeOutput(io, COMPLETIONS_POWERSHELL, null, false);
    } else {
        return error.UnknownShell;
    }
}

// ─── `rune hooks` ────────────────────────────────────────────

pub fn handleHooks(io: std.Io, _: std.mem.Allocator, hook_type: []const u8) !void {
    if (std.mem.eql(u8, hook_type, "pre-commit")) {
        try io_mod.writeOutput(io, HOOK_PRECOMMIT, null, false);
    } else {
        return error.UnknownHookType;
    }
}

pub const HOOK_PRECOMMIT =
    \\#!/usr/bin/env bash
    \\# Pre-commit hook for Rune schema validation
    \\# Install: rune hooks pre-commit > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
    \\
    \\set -euo pipefail
    \\
    \\# Find rune binary — prefer local build, then PATH
    \\RUNE=""
    \\if [ -x "./rune/zig-out/bin/rune" ]; then
    \\    RUNE="./rune/zig-out/bin/rune"
    \\elif command -v rune >/dev/null 2>&1; then
    \\    RUNE="rune"
    \\else
    \\    echo "warning: rune not found, skipping schema validation"
    \\    exit 0
    \\fi
    \\
    \\# Get staged .ss files
    \\SS_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.ss$' || true)
    \\
    \\if [ -z "$SS_FILES" ]; then
    \\    exit 0
    \\fi
    \\
    \\echo "Validating $(echo "$SS_FILES" | wc -l | tr -d ' ') schema file(s)..."
    \\
    \\FAILED=0
    \\for f in $SS_FILES; do
    \\    if ! $RUNE validate "$f" 2>&1; then
    \\        FAILED=1
    \\    fi
    \\done
    \\
    \\if [ "$FAILED" -ne 0 ]; then
    \\    echo ""
    \\    echo "Schema validation failed. Fix errors before committing."
    \\    echo "To skip this check: git commit --no-verify"
    \\    exit 1
    \\fi
    \\
    \\echo "All schemas valid."
    \\
;

pub const COMPLETIONS_BASH =
    \\# Bash completions for rune
    \\# Source this file: source <(rune completions bash)
    \\
    \\_rune_completions() {
    \\    local cur prev commands
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    commands="init validate check stats diff migrate reverse docs format generate completions hooks watch"
    \\
    \\    if [[ ${cur} == -* ]]; then
    \\        COMPREPLY=( $(compgen -W "--help --version --dialect --target --trace --stats --check --quiet --strict --json-errors --verbose-passes --import-path --rollback --output --dry-run --validate-only --format --list --template --color --init" -- ${cur}) )
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
    \\        hooks)
    \\            COMPREPLY=( $(compgen -W "pre-commit" -- ${cur}) )
    \\            ;;
    \\        validate|check|stats|docs|format|init)
    \\            COMPREPLY=( $(compgen -f -X '!*.ss' -- ${cur}) )
    \\            ;;
    \\        watch)
    \\            COMPREPLY=( $(compgen -f -X '!*.ss' -- ${cur}) )
    \\            ;;
    \\    esac
    \\    return 0
    \\}
    \\complete -F _rune_completions rune
    \\
;

pub const COMPLETIONS_ZSH =
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
    \\        'format:Auto-format .ss schema file'
    \\        'generate:Generate output in specified format'
    \\        'completions:Generate shell completions'
    \\        'hooks:Generate git hooks'
    \\        'watch:Watch file and recompile on change'
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
    \\                hooks)
    \\                    _arguments '1:type:(pre-commit)'
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

pub const COMPLETIONS_FISH =
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
    \\complete -c rune -n __fish_use_subcommand -a format -d 'Auto-format .ss schema file'
    \\complete -c rune -n __fish_use_subcommand -a generate -d 'Generate output in specified format'
    \\complete -c rune -n __fish_use_subcommand -a completions -d 'Generate shell completions'
    \\complete -c rune -n __fish_use_subcommand -a hooks -d 'Generate git hooks'
\\complete -c rune -n __fish_use_subcommand -a watch -d 'Watch file and recompile on change'
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
    \\complete -c rune -l format -r -d 'Output format' -xa 'text json sarif markdown'
    \\complete -c rune -l color -r -d 'Color output' -xa 'auto always never'
    \\complete -c rune -l init -d 'Create starter schema (same as init subcommand)'
    \\
    \\# generate subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -a 'json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql' -d 'Generator'
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -F -r
    \\
    \\# completions subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish powershell' -d 'Shell'
    \\
    \\# hooks subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from hooks' -a 'pre-commit' -d 'Hook type'
    \\
    \\# File arguments
    \\complete -c rune -n '__fish_seen_subcommand_from validate check stats docs format init watch' -F -r
    \\complete -c rune -n '__fish_seen_subcommand_from diff migrate' -F -r
    \\complete -c rune -n '__fish_seen_subcommand_from reverse' -F -r
    \\
;

pub const COMPLETIONS_POWERSHELL =
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
    \\        [System.Management.Automation.CompletionResult]::new('format', 'format', 'ParameterValue', 'Auto-format .ss schema file')
    \\        [System.Management.Automation.CompletionResult]::new('generate', 'generate', 'ParameterValue', 'Generate output in specified format')
    \\        [System.Management.Automation.CompletionResult]::new('completions', 'completions', 'ParameterValue', 'Generate shell completions')
    \\        [System.Management.Automation.CompletionResult]::new('hooks', 'hooks', 'ParameterValue', 'Generate git hooks')
    \\        [System.Management.Automation.CompletionResult]::new('watch', 'watch', 'ParameterValue', 'Watch file and recompile on change')
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
    \\    $flags = @('--help', '--version', '--dialect', '--target', '--trace', '--stats', '--check', '--quiet', '--strict', '--json-errors', '--verbose-passes', '--import-path', '--output', '--format', '--rollback', '--dry-run', '--validate-only', '--list', '--template', '--color', '--init', '-h', '-v', '-d', '-t', '-s', '-q')
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
    \\    if ($subcmd -eq 'hooks' -and $tokens.Count -eq 3) {
    \\        return @(
    \\            [System.Management.Automation.CompletionResult]::new('pre-commit', 'pre-commit', 'ParameterValue', 'Pre-commit hook')
    \\        )
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
