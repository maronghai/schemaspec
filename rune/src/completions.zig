const std = @import("std");
const io_mod = @import("io.zig");

// ─── Shell Completions ────────────────────────────────────────
// Shell completion scripts for bash, zsh, fish, and powershell.

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

pub const COMPLETIONS_BASH =
    \\# Bash completions for rune
    \\# Source this file: source <(rune completions bash)
    \\
    \\_rune_completions() {
    \\    local cur prev commands
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    commands="init validate check stats diff migrate reverse docs format generate completions hooks lint watch lsp"
    \\
    \\    if [[ ${cur} == -* ]]; then
    \\        COMPREPLY=( $(compgen -W "--help --version --dialect --target --trace --stats --check --quiet --strict --json-errors --verbose-passes --import-path --rollback --output --dry-run --validate-only --format --list --template --color --init --parallel --interval --stream --summary --stat --config --name --dir --incremental --graph --from-sql --generators --write" -- ${cur}) )
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
    \\                COMPREPLY=( $(compgen -W "json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql symbol-index" -- ${cur}) )
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
    \\        validate|check|stats|docs|format|init|lint)
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
    \\        'lint:Lint schema for quality issues'
    \\        'watch:Watch file and recompile on change'
    \\        'lsp:Start LSP language server (stdio)'
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
    \\                            gens=(json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql symbol-index)
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
    \\                    _arguments \
    \\                        '1:file:_files -g "*.ss"' \
    \\                        '--interval[Polling interval in ms]' \
    \\                        '--parallel[Parallel streaming compilation]' \
    \\                        '*/-t[Print compilation trace]' \
    \\                        '*/-s[Print compilation stats]' \
    \\                        '--json-errors[Emit diagnostics in JSON]' \
    \\                        '--summary[Show summary only]' \
    \\                        '--stat[Show summary only (alias for --summary)]' \
    \\                        '*/-d[Target SQL dialect]:dialect:(mysql pg postgres sqlite mssql oracle db2)' \
    \\                        '--target[Output format]:target:(sql json-schema)' \
    \\                        '--generators[Generators to run]' \
    \\                        '*/-o[Output file path]:file:_files'
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
    \\complete -c rune -n __fish_use_subcommand -a lint -d 'Lint schema for quality issues'
    \\complete -c rune -n __fish_use_subcommand -a watch -d 'Watch file and recompile on change'
    \\complete -c rune -n __fish_use_subcommand -a lsp -d 'Start LSP language server (stdio)'
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
    \\complete -c rune -l parallel -d 'Parallel streaming compilation'
    \\complete -c rune -l interval -r -d 'Watch polling interval in ms'
    \\complete -c rune -l stream -d 'Streaming compilation'
    \\complete -c rune -l summary -d 'Show summary only'
    \\complete -c rune -l stat -d 'Show summary only (alias for --summary)'
    \\complete -c rune -l config -r -d 'Path to config file'
    \\complete -c rune -l name -r -d 'Migration label'
    \\complete -c rune -l dir -r -d 'Migration output directory'
    \\complete -c rune -l incremental -d 'Incremental migration'
    \\complete -c rune -l graph -d 'Show migration dependency graph'
    \\complete -c rune -l from-sql -r -d 'Compare against SQL dump file'
    \\complete -c rune -l generators -r -d 'Comma-separated list of generators'
    \\
    \\# generate subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -a 'json-schema sql-ddl prisma docs drizzle typeorm sqlalchemy knex openapi graphql symbol-index' -d 'Generator'
    \\complete -c rune -n '__fish_seen_subcommand_from generate' -F -r
    \\
    \\# completions subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish powershell' -d 'Shell'
    \\
    \\# hooks subcommand
    \\complete -c rune -n '__fish_seen_subcommand_from hooks' -a 'pre-commit' -d 'Hook type'
    \\
    \\# File arguments
    \\complete -c rune -n '__fish_seen_subcommand_from validate check stats docs format init lint watch' -F -r
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
    \\        [System.Management.Automation.CompletionResult]::new('lint', 'lint', 'ParameterValue', 'Lint schema for quality issues')
    \\        [System.Management.Automation.CompletionResult]::new('watch', 'watch', 'ParameterValue', 'Watch file and recompile on change')
    \\        [System.Management.Automation.CompletionResult]::new('lsp', 'lsp', 'ParameterValue', 'Start LSP language server (stdio)')
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
    \\        [System.Management.Automation.CompletionResult]::new('symbol-index', 'symbol-index', 'ParameterValue', 'JSON symbol index')
    \\    )
    \\
    \\    $shells = @(
    \\        [System.Management.Automation.CompletionResult]::new('bash', 'bash', 'ParameterValue', 'Bash')
    \\        [System.Management.Automation.CompletionResult]::new('zsh', 'zsh', 'ParameterValue', 'Zsh')
    \\        [System.Management.Automation.CompletionResult]::new('fish', 'fish', 'ParameterValue', 'Fish')
    \\        [System.Management.Automation.CompletionResult]::new('powershell', 'powershell', 'ParameterValue', 'PowerShell')
    \\    )
    \\
    \\    $flags = @('--help', '--version', '--dialect', '--target', '--trace', '--stats', '--check', '--quiet', '--strict', '--json-errors', '--verbose-passes', '--import-path', '--output', '--format', '--rollback', '--dry-run', '--validate-only', '--list', '--template', '--color', '--init', '--parallel', '--interval', '--stream', '--summary', '--stat', '--config', '--name', '--dir', '--incremental', '--graph', '--from-sql', '--generators', '--write', '-h', '-v', '-d', '-t', '-s', '-q')
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
    \\    return $tokens | Where-Object { $_ -notlike "-*" -and $_ -ne 'rune' } | ForEach-Object {
    \\        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    \\    })
    \\}
    \\
;
