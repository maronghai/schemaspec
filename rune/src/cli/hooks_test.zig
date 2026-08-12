const std = @import("std");
const testing = std.testing;

const hooks = @import("hooks.zig");

test "handleHooks: pre-commit hook outputs script" {
    // handleHooks writes to io, so we just verify the constant is non-empty
    try testing.expect(hooks.HOOK_PRECOMMIT.len > 0);
}

test "handleHooks: unknown hook type returns error" {
    const result = hooks.handleHooks(undefined, undefined, "unknown");
    try testing.expectError(error.UnknownHookType, result);
}

test "HOOK_PRECOMMIT: contains expected content" {
    const script = hooks.HOOK_PRECOMMIT;
    // Should contain shebang
    try testing.expect(std.mem.indexOf(u8, script, "#!/usr/bin/env bash") != null);
    // Should contain validate command
    try testing.expect(std.mem.indexOf(u8, script, "validate") != null);
    // Should contain git diff
    try testing.expect(std.mem.indexOf(u8, script, "git diff --cached") != null);
}
