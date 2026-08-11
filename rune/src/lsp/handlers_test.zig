const std = @import("std");
const testing = std.testing;

// ─── LSP Handlers Tests ────────────────────────────────────────
// Tests for lsp/handlers.zig helper functions.
// The inline tests in handlers.zig are discovered via this import.

// Import handlers.zig to register inline tests
comptime {
    _ = @import("handlers.zig");
}
