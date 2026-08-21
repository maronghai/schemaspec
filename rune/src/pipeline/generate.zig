const std = @import("std");
const compile_helper = @import("compile_helper.zig");
const compileToTypedAst = compile_helper.compileToTypedAst;
const io_mod = @import("../io.zig");
const dialect_enum = @import("../dialect/enum.zig");
const generator = @import("../generator.zig");
const fmt = @import("../diagnostic/format.zig");
const template_override = @import("../generators/template_override.zig");

// ─── Generate Handlers ──────────────────────────────────────────
// Schema generation: compile → resolve → generate → write output.
// Extracted from handlers.zig for single-responsibility.

/// Configuration for `generateFromSchema` and `generateFromSchemaBatch`.
/// Replaces 8 positional parameters with a named struct.
pub const GenerateConfig = struct {
    /// Generator name (for single generation) or comma-separated list (for batch).
    generators: []const u8,
    /// Output file path or directory for batch mode. null = stdout.
    output: ?[]const u8 = null,
    /// Target dialect for dialect-specific output.
    dialect: dialect_enum.Dialect = .mysql,
    /// Suppress non-error output.
    quiet: bool = false,
    /// Preview output without writing to files.
    dry_run: bool = false,
    /// List available generators and exit.
    list: bool = false,
    /// Run generator health check and exit.
    check: bool = false,
    /// Explicit template-override directory (--template-dir). null = default
    /// discovery (./.rune/templates/ then ~/.rune/templates/).
    template_dir: ?[]const u8 = null,
};

/// Compile a schema and run a named generator on it. Handles the full pipeline:
/// read input → compile → resolve types → lookup generator → generate → write output.
/// Used by both `rune generate <name>` and `rune docs` (which delegates to the "docs" generator).
/// When dry_run is true, output is written to stdout instead of the output file.
fn generateFromSchema(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generator_name: []const u8,
    dialect: dialect_enum.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
    dry_run: bool,
    template_dir: ?[]const u8,
    environ_map: *const std.process.Environ.Map,
) !void {
    const typed = try compileToTypedAst(alloc, file_data, dialect);

    // Use plugin-aware lookup (checks WASM plugins first, then builtin)
    if (generator.getGeneratorWithPlugins(generator_name)) |gen| {
        var output_text = try gen.generate(alloc, typed, dialect);
        // Template override: if a `.rune-template` file exists for this
        // generator, its rendered content replaces the built-in output.
        if (try applyTemplateOverride(io, alloc, output_text, generator_name, typed, dialect, template_dir, environ_map)) |rendered| {
            output_text = rendered;
        }
        if (dry_run) {
            // Dry run: output to stdout without writing to file
            try io_mod.writeOutput(io, output_text, null, quiet);
        } else {
            try io_mod.writeOutput(io, output_text, output_path, quiet);
        }
    } else {
        return error.UnknownGenerator;
    }
}

/// Check for a `.rune-template` override for `generator_name` and render it.
/// Returns null when no override exists (caller keeps the built-in output).
pub fn applyTemplateOverride(
    io: std.Io,
    alloc: std.mem.Allocator,
    builtin_output: []const u8,
    generator_name: []const u8,
    typed: anytype,
    dialect: dialect_enum.Dialect,
    explicit_dir: ?[]const u8,
    environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    _ = builtin_output;
    const tmpl = (try template_override.load(io, alloc, generator_name, explicit_dir, environ_map)) orelse return null;
    const table_names = try alloc.alloc([]const u8, typed.tables.len);
    for (typed.tables, 0..) |table, i| table_names[i] = table.name;
    const ctx: template_override.RenderContext = .{
        .schema_name = typed.schema_name orelse "",
        .dialect_name = @tagName(dialect),
        .tables = table_names,
    };
    return try template_override.render(alloc, tmpl, ctx);
}

/// Batch generation: run multiple generators from a single compilation.
/// `generators_str` is a comma-separated list of generator names (e.g. "prisma,drizzle,openapi").
/// Each generator's output is written to a separate file: `<output_dir>/<generator_name>.<ext>`.
/// When output_path is null, outputs are written to stdout separated by headers.
/// When dry_run is true, all outputs are written to stdout instead of files.
fn generateFromSchemaBatch(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: []const u8,
    generators_str: []const u8,
    dialect: dialect_enum.Dialect,
    output_path: ?[]const u8,
    quiet: bool,
    dry_run: bool,
    template_dir: ?[]const u8,
    environ_map: *const std.process.Environ.Map,
) !void {
    const typed = try compileToTypedAst(alloc, file_data, dialect);

    // Split comma-separated generator names
    var gen_names = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    defer gen_names.deinit(alloc);

    var start: usize = 0;
    for (generators_str, 0..) |ch, i| {
        if (ch == ',' or i == generators_str.len - 1) {
            const end = if (ch == ',') i else i + 1;
            const name = std.mem.trim(u8, generators_str[start..end], " ");
            if (name.len > 0) {
                if (generator.getGeneratorWithPlugins(name) == null) {
                    return error.UnknownGenerator;
                }
                try gen_names.append(alloc, name);
            }
            start = i + 1;
        }
    }

    if (gen_names.items.len == 0) {
        return error.UnknownGenerator;
    }

    // Generate each output
    for (gen_names.items) |gen_name| {
        if (generator.getGeneratorWithPlugins(gen_name)) |gen| {
            var output_text = try gen.generate(alloc, typed, dialect);
            // Template override: rendered `.rune-template` replaces built-in output.
            if (try applyTemplateOverride(io, alloc, output_text, gen_name, typed, dialect, template_dir, environ_map)) |rendered| {
                output_text = rendered;
            }

            if (dry_run) {
                // Dry run: output to stdout with header
                if (!quiet) {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "--- {s} ---\n", .{gen_name}), null, quiet);
                }
                try io_mod.writeOutput(io, output_text, null, quiet);
            } else {
                // Determine output path
                const file_out = if (output_path) |base_path| blk: {
                    // Write to <base_path>/<generator_name><extension>
                    break :blk try std.fmt.allocPrint(alloc, "{s}/{s}{s}", .{ base_path, gen_name, gen.extension });
                } else null;

                if (file_out) |path| {
                    // Write to file
                    try std.Io.Dir.cwd().writeFile(io, .{
                        .sub_path = path,
                        .data = output_text,
                    });
                    if (!quiet) {
                        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Written to {s}\n", .{path}), null, quiet);
                    }
                } else {
                    // Write to stdout with header
                    if (!quiet) {
                        try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "--- {s} ---\n", .{gen_name}), null, quiet);
                    }
                    try io_mod.writeOutput(io, output_text, null, quiet);
                }
            }
        }
    }
}

/// Unified generate handler using GenerateConfig struct.
/// Handles list, check, and generation modes.
pub fn handleGenerate(
    io: std.Io,
    alloc: std.mem.Allocator,
    file_data: ?[]const u8,
    cfg: GenerateConfig,
    environ_map: *const std.process.Environ.Map,
) !void {
    // Initialize WASM plugin system
    _ = try generator.loadWasmPlugins(alloc);
    defer generator.deinitWasmPlugins(alloc);

    if (cfg.list) {
        // Use plugin-aware listing (builtin + WASM plugins)
        var buf: [8192]u8 = undefined;
        const stdout_file = std.Io.File.stdout();
        var stdout_writer = stdout_file.writer(io, &buf);
        try generator.listAllGeneratorsWithPlugins(&stdout_writer.interface);
        return;
    }
    if (cfg.check) {
        // Check both builtin and plugin generators
        if (generator.check(alloc)) |err_msg| {
            try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "Builtin generator health check failed: {s}\n", .{err_msg}), null, false);
            return error.GeneratorHealthCheckFailed;
        }
        // TODO: Add plugin generator health check
        try io_mod.writeOutput(io, "All generators OK\n", null, false);
        return;
    }
    const data = file_data orelse return error.NoInput;
    const is_batch = std.mem.indexOf(u8, cfg.generators, ",") != null;
    if (is_batch) {
        try generateFromSchemaBatch(io, alloc, data, cfg.generators, cfg.dialect, cfg.output, cfg.quiet, cfg.dry_run, cfg.template_dir, environ_map);
    } else {
        try generateFromSchema(io, alloc, data, cfg.generators, cfg.dialect, cfg.output, cfg.quiet, cfg.dry_run, cfg.template_dir, environ_map);
    }
}

// ─── Tests ──────────────────────────────────────────────────────

test "GenerateConfig defaults" {
    const cfg = GenerateConfig{ .generators = "prisma" };
    try std.testing.expectEqualStrings("prisma", cfg.generators);
    try std.testing.expectEqual(@as(?[]const u8, null), cfg.output);
    try std.testing.expectEqual(dialect_enum.Dialect.mysql, cfg.dialect);
    try std.testing.expectEqual(false, cfg.quiet);
    try std.testing.expectEqual(false, cfg.dry_run);
    try std.testing.expectEqual(false, cfg.list);
    try std.testing.expectEqual(false, cfg.check);
}

test "GenerateConfig with all options" {
    const cfg = GenerateConfig{
        .generators = "prisma,drizzle",
        .output = "out/",
        .dialect = .pg,
        .quiet = true,
        .dry_run = true,
        .list = true,
        .check = true,
    };
    try std.testing.expectEqualStrings("prisma,drizzle", cfg.generators);
    try std.testing.expectEqualStrings("out/", cfg.output.?);
    try std.testing.expectEqual(dialect_enum.Dialect.pg, cfg.dialect);
    try std.testing.expectEqual(true, cfg.quiet);
    try std.testing.expectEqual(true, cfg.dry_run);
    try std.testing.expectEqual(true, cfg.list);
    try std.testing.expectEqual(true, cfg.check);
}

test "GenerateConfig batch detection" {
    const single = GenerateConfig{ .generators = "prisma" };
    const batch = GenerateConfig{ .generators = "prisma,drizzle" };
    try std.testing.expectEqual(@as(?usize, null), std.mem.indexOf(u8, single.generators, ","));
    try std.testing.expectEqual(@as(?usize, 6), std.mem.indexOf(u8, batch.generators, ","));
}
