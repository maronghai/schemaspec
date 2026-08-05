const std = @import("std");
const io_mod = @import("../io.zig");

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
