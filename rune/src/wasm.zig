const std = @import("std");

// ─── WASM Library Entry Point ──────────────────────────────────
// Compile-time entry point for wasm32-wasi target. Re-exports all sub-modules
// so their `export fn` declarations are visible to the linker.
// Each sub-module defines its own export functions — this file is the compilation unit
// that brings them together for the wasm32-wasi target.
comptime {
    _ = @import("wasm/error.zig");
    _ = @import("wasm/compile.zig");
    _ = @import("wasm/diff.zig");
    _ = @import("wasm/reverse.zig");
    _ = @import("wasm/lint.zig");
    _ = @import("wasm/format.zig");
    _ = @import("wasm/generate.zig");
    _ = @import("wasm/export.zig");
    _ = @import("wasm/docs.zig");
}

// All wasm tests live in wasm_test.zig — single location for wasm test coverage.
