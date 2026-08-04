const std = @import("std");

// ─── IR Version ──────────────────────────────────────────────
// Versioning for intermediate representations (ResolvedAst, TypedAst).
// When the IR format changes across Rune versions, this constant is bumped
// to enable detection and handling of incompatibility.

/// Current IR format version. Bump when ResolvedAst or TypedAst fields change.
pub const CURRENT_IR_VERSION: u32 = 1;

/// Errors for IR version validation.
pub const IrVersionError = error{UnsupportedIrVersion};

/// Validate that an IR version is supported by this Rune build.
/// Returns error.UnsupportedIrVersion for major version mismatches.
pub fn validateIrVersion(version: u32) IrVersionError!void {
    if (version == 0 or version > CURRENT_IR_VERSION) {
        return error.UnsupportedIrVersion;
    }
}

test "current IR version is positive" {
    try std.testing.expect(CURRENT_IR_VERSION > 0);
}

test "validate accepts current version" {
    try validateIrVersion(CURRENT_IR_VERSION);
}

test "validate rejects zero version" {
    try std.testing.expectError(error.UnsupportedIrVersion, validateIrVersion(0));
}

test "validate rejects future version" {
    try std.testing.expectError(error.UnsupportedIrVersion, validateIrVersion(CURRENT_IR_VERSION + 1));
}
