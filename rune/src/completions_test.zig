const std = @import("std");
const completions = @import("completions.zig");
const init_mod = @import("cli/init.zig");

test "STARTER_SCHEMA is non-empty" {
    try std.testing.expect(init_mod.STARTER_SCHEMA.len > 0);
}

test "STARTER_SCHEMA contains expected table definitions" {
    const schema = init_mod.STARTER_SCHEMA;
    // Should define users, posts, comments tables
    try std.testing.expect(std.mem.indexOf(u8, schema, "# users") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "# posts") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "# comments") != null);
}

test "STARTER_SCHEMA contains schema declaration" {
    try std.testing.expect(std.mem.indexOf(u8, init_mod.STARTER_SCHEMA, "$ mydb") != null);
}

test "STARTER_SCHEMA contains field types" {
    const schema = init_mod.STARTER_SCHEMA;
    // Should use SS type symbols
    try std.testing.expect(std.mem.indexOf(u8, schema, "n++") != null); // auto-increment
    try std.testing.expect(std.mem.indexOf(u8, schema, "s128") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "S") != null); // text
    try std.testing.expect(std.mem.indexOf(u8, schema, "e(") != null); // enum
}

test "Bash completions contain all subcommands" {
    const bash = completions.COMPLETIONS_BASH;
    const subcommands = [_][]const u8{
        "init",        "validate", "check", "stats",  "diff",
        "migrate",     "reverse",  "docs",  "format", "generate",
        "completions",
    };
    for (subcommands) |cmd| {
        // Check it's present in bash completions
        if (std.mem.indexOf(u8, bash, cmd) == null) {
            return error.TestExpectedEqual;
        }
    }
}

test "Bash completions contain global flags" {
    const bash = completions.COMPLETIONS_BASH;
    const flags = [_][]const u8{ "--help", "--version", "--dialect", "--trace", "--strict", "--json-errors" };
    for (flags) |flag| {
        if (std.mem.indexOf(u8, bash, flag) == null) {
            return error.TestExpectedEqual;
        }
    }
}

test "Bash completions contain generator names" {
    const bash = completions.COMPLETIONS_BASH;
    const generators = [_][]const u8{
        "json-schema", "sql-ddl", "prisma",  "drizzle", "typeorm",
        "sqlalchemy",  "knex",    "openapi", "graphql",
    };
    for (generators) |gen| {
        if (std.mem.indexOf(u8, bash, gen) == null) {
            return error.TestExpectedEqual;
        }
    }
}

test "Zsh completions contain all subcommands" {
    const zsh = completions.COMPLETIONS_ZSH;
    try std.testing.expect(std.mem.indexOf(u8, zsh, "init") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh, "validate") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh, "generate") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh, "completions") != null);
}

test "Zsh completions have compdef directive" {
    try std.testing.expect(std.mem.indexOf(u8, completions.COMPLETIONS_ZSH, "#compdef rune") != null);
}

test "Fish completions contain all subcommands" {
    const fish = completions.COMPLETIONS_FISH;
    try std.testing.expect(std.mem.indexOf(u8, fish, "complete -c rune") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish, "-a init") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish, "-a validate") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish, "-a generate") != null);
}

test "Fish completions contain generator completions" {
    const fish = completions.COMPLETIONS_FISH;
    try std.testing.expect(std.mem.indexOf(u8, fish, "__fish_seen_subcommand_from generate") != null);
}

test "PowerShell completions contain Register-ArgumentCompleter" {
    const ps = completions.COMPLETIONS_POWERSHELL;
    try std.testing.expect(std.mem.indexOf(u8, ps, "Register-ArgumentCompleter") != null);
}

test "PowerShell completions contain all subcommands" {
    const ps = completions.COMPLETIONS_POWERSHELL;
    const subcommands = [_][]const u8{ "init", "validate", "check", "stats", "diff", "migrate", "reverse", "docs", "format", "generate", "completions" };
    for (subcommands) |cmd| {
        if (std.mem.indexOf(u8, ps, cmd) == null) {
            return error.TestExpectedEqual;
        }
    }
}

test "PowerShell completions contain generator names" {
    const ps = completions.COMPLETIONS_POWERSHELL;
    try std.testing.expect(std.mem.indexOf(u8, ps, "json-schema") != null);
    try std.testing.expect(std.mem.indexOf(u8, ps, "sql-ddl") != null);
    try std.testing.expect(std.mem.indexOf(u8, ps, "prisma") != null);
}

test "All completion scripts reference shell name" {
    // Each script should mention its own shell
    try std.testing.expect(std.mem.indexOf(u8, completions.COMPLETIONS_BASH, "Bash") != null);
    try std.testing.expect(std.mem.indexOf(u8, completions.COMPLETIONS_ZSH, "Zsh") != null);
    try std.testing.expect(std.mem.indexOf(u8, completions.COMPLETIONS_FISH, "Fish") != null);
    try std.testing.expect(std.mem.indexOf(u8, completions.COMPLETIONS_POWERSHELL, "PowerShell") != null);
}
