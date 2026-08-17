const std = @import("std");
const generator = @import("../generator.zig");
const fmt = @import("../diagnostic/format.zig");

// ─── WASM Plugin System (Stub for Zig 0.16) ──────────────────────
// Zig 0.16 std library does not include a WASM runtime.
// This module provides the API surface for future implementation
// when a WASM runtime (e.g., wasmtime, wasmer, or custom) is integrated.

/// Loaded WASM plugin state (stub).
pub const WasmPlugin = struct {
    name: []const u8,
    path: []const u8,
    gen_count: i32,
};

/// Plugin registry — stores loaded WASM plugins and their generators.
pub var wasm_plugin_registry: std.ArrayList(WasmPlugin) = std.ArrayList(WasmPlugin).empty;

/// Plugin generators — generators registered by WASM plugins.
var wasm_plugin_generators: std.ArrayList(generator.Generator) = std.ArrayList(generator.Generator).empty;

/// Initialize the WASM plugin system. Call once at startup.
/// Currently a no-op; WASM plugin loading not yet implemented for Zig 0.16.
pub fn init(alloc: std.mem.Allocator) !void {
    wasm_plugin_generators = try std.ArrayList(generator.Generator).initCapacity(alloc, 0);
    wasm_plugin_registry = try std.ArrayList(WasmPlugin).initCapacity(alloc, 0);
}

/// Load a single WASM plugin from the given path (.wasm).
/// Returns error.NotImplemented — WASM plugin loading not yet implemented.
pub fn loadWasmPlugin(alloc: std.mem.Allocator, path: []const u8) !i32 {
    _ = alloc;
    fmt.printWarn("wasm-plugin", "WASM plugin loading not yet implemented (Zig 0.16 std has no WASM runtime); skipping {s}", .{path});
    return error.NotImplemented;
}

/// Load all WASM plugins from a directory (non-recursive, .wasm extension).
/// Returns 0 — WASM plugin loading not yet implemented.
pub fn loadWasmPluginsFromDir(alloc: std.mem.Allocator, dir_path: []const u8) !usize {
    _ = alloc;
    fmt.printWarn("wasm-plugin", "WASM plugin loading not yet implemented (Zig 0.16 std has no WASM runtime); skipping directory {s}", .{dir_path});
    return 0;
}

/// Get all WASM plugin-registered generators (currently always empty).
pub fn getWasmPluginGenerators() []const generator.Generator {
    return wasm_plugin_generators.items;
}

/// Find a generator by name, checking WASM plugins first then builtin.
pub fn getGenerator(name: []const u8) ?generator.Generator {
    // Check WASM plugins first (currently always empty)
    for (wasm_plugin_generators.items) |gen| {
        if (std.mem.eql(u8, gen.name, name)) return gen;
    }
    // Fall back to builtin
    return generator.get(name);
}

/// List all generators (builtin + WASM plugins) to a writer.
pub fn listAllGenerators(writer: anytype) !void {
    // Builtin
    try std.Io.Writer.print(writer, "Builtin generators:\n", .{});
    for (generator.REGISTRY) |gen| {
        try std.Io.Writer.print(writer, "  {s:<16} {s} (builtin)\n", .{ gen.name, gen.description });
    }
    // WASM Plugins (currently always empty)
    if (wasm_plugin_generators.items.len > 0) {
        try std.Io.Writer.print(writer, "\nWASM plugin generators:\n", .{});
        for (wasm_plugin_generators.items) |gen| {
            try std.Io.Writer.print(writer, "  {s:<16} {s} (wasm-plugin)\n", .{ gen.name, gen.description });
        }
    }
}

/// Cleanup: free memory.
pub fn deinit(alloc: std.mem.Allocator) void {
    for (wasm_plugin_registry.items) |plugin| {
        alloc.free(plugin.name);
        alloc.free(plugin.path);
    }
    wasm_plugin_registry.deinit(alloc);
    wasm_plugin_generators.deinit(alloc);
}

// ─── Tests ──────────────────────────────────────────────────────

test "wasm-plugin: init and deinit" {
    const alloc = std.testing.allocator;
    try init(alloc);
    try std.testing.expect(wasm_plugin_generators.items.len == 0);
    deinit(alloc);
}

test "wasm-plugin: getGenerator falls back to builtin" {
    const alloc = std.testing.allocator;
    try init(alloc);
    defer deinit(alloc);

    const gen = getGenerator("json-schema");
    try std.testing.expect(gen != null);
    try std.testing.expectEqualStrings("json-schema", gen.?.name);

    const unknown = getGenerator("nonexistent");
    try std.testing.expect(unknown == null);
}

test "wasm-plugin: loadWasmPlugin returns NotImplemented" {
    const alloc = std.testing.allocator;
    try init(alloc);
    defer deinit(alloc);

    const result = loadWasmPlugin(alloc, "dummy.wasm");
    try std.testing.expectError(error.NotImplemented, result);
}
