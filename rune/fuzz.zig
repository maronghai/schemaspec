const std = @import("std");
const tokenizer_mod = @import("src/tokenizer.zig");
const parser_mod = @import("src/parser.zig");
const semantic_mod = @import("src/semantic.zig");
const typed_ast = @import("src/typed_ast.zig");
const sql_parser_mod = @import("src/sql_parser.zig");
const diag = @import("src/diagnostic.zig");
const reverse_codegen_mod = @import("src/reverse_codegen.zig");
const dialect_enum = @import("src/dialect/enum.zig");

// ─── Fuzz Targets ───────────────────────────────────────────────

fn fuzzForwardPipeline(alloc: std.mem.Allocator, input: []const u8) void {
    var lines = std.ArrayList([]const u8).initCapacity(alloc, 256) catch return;
    defer lines.deinit(alloc);

    var line_it = std.mem.splitScalar(u8, input, '\n');
    while (line_it.next()) |line| {
        lines.append(alloc, std.mem.trimEnd(u8, line, "\r")) catch return;
    }

    const owned_lines = lines.toOwnedSlice(alloc) catch return;
    defer alloc.free(owned_lines);

    const tok = tokenizer_mod.Tokenizer.init(owned_lines);
    const tokenized = tok.tokenizeAll(alloc) catch return;
    defer alloc.free(tokenized);

    var diagnostics = diag.DiagnosticCollector.init(alloc) catch return;
    var p = parser_mod.Parser.initWithDiagnostics(alloc, &diagnostics);
    const tree = p.parse(tokenized) catch return;

    var sa = semantic_mod.SemanticAnalyzer.init(alloc);
    const resolved = sa.analyze(tree) catch return;

    var tr = typed_ast.TypeResolver.init(alloc);
    _ = tr.resolve(resolved, .mysql) catch return;
}

fn fuzzReversePipeline(alloc: std.mem.Allocator, input: []const u8) void {
    // Test all 6 dialects for reverse pipeline
    const dialects = [_]dialect_enum.Dialect{ .mysql, .pg, .sqlite, .mssql, .oracle, .db2 };
    for (dialects) |dialect| {
        var sp_parser = sql_parser_mod.SqlParser.init(alloc, input, dialect) catch continue;
        const result = sp_parser.parse() catch continue;
        if (result.schema.tables.len == 0) continue;

        var rcg = reverse_codegen_mod.ReverseCodegen.init(alloc, dialect);
        _ = rcg.generate(result.schema) catch continue;
    }
}

fn fuzzTokenizer(alloc: std.mem.Allocator, input: []const u8) void {
    var lines = std.ArrayList([]const u8).initCapacity(alloc, 256) catch return;
    defer lines.deinit(alloc);

    var line_it = std.mem.splitScalar(u8, input, '\n');
    while (line_it.next()) |line| {
        lines.append(alloc, std.mem.trimEnd(u8, line, "\r")) catch return;
    }

    const owned_lines = lines.toOwnedSlice(alloc) catch return;
    defer alloc.free(owned_lines);

    const tok = tokenizer_mod.Tokenizer.init(owned_lines);
    const tokenized = tok.tokenizeAll(alloc) catch return;
    defer alloc.free(tokenized);
}

// ─── Mutation Strategies ─────────────────────────────────────────

fn mutateRandom(data: []u8, seed: u64) void {
    const num_mutations: usize = @min(3, @max(1, seed % 4));
    for (0..num_mutations) |m| {
        if (data.len == 0) break;
        const pos = (seed * 7 + m * 13) % data.len;
        data[pos] = @intCast((@as(u16, data[pos]) +% @as(u16, @intCast(seed + m))) & 0xFF);
    }
}

fn mutateBoundary(data: []u8, seed: u64) void {
    if (data.len == 0) return;
    // Insert boundary values at random positions
    const boundary_vals = [_]u8{ 0, 1, 0x7F, 0x80, 0xFF, '\n', '\r', '\t', '"', '\'', '\\', ';', '#', '$', '%', '@', '!' };
    const pos = seed % data.len;
    const val = boundary_vals[seed % boundary_vals.len];
    data[pos] = val;
}

fn mutateTruncate(data: []u8, seed: u64) void {
    if (data.len < 2) return;
    // Truncate to a random length
    const new_len = 1 + (seed % (data.len - 1));
    data[new_len] = 0;
}

fn mutateDuplicate(data: []u8, seed: u64) void {
    if (data.len < 2) return;
    // Duplicate a random substring
    const start = seed % (data.len / 2);
    const len = 1 + (seed % @min(16, data.len / 4));
    const end = @min(start + len, data.len);
    const slice = data[start..end];
    // Write the slice at a random position after the original
    const target = end % data.len;
    for (slice, 0..) |b, i| {
        const idx = (target + i) % data.len;
        data[idx] = b;
    }
}

fn mutateStructural(data: []u8, seed: u64) void {
    if (data.len < 3) return;
    // Insert structural characters that the parser must handle
    const structs = [_][]const u8{ "# ", "$ ", "\\ ", "% ", "@ ", "...", "---", "===", "###", "~~~" };
    const s = structs[seed % structs.len];
    const pos = seed % (data.len - s.len + 1);
    for (s, 0..) |c, i| {
        data[pos + i] = c;
    }
}

// ─── Entry Point ────────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer arg_it.deinit();
    _ = arg_it.next(); // skip program name

    var target_name: []const u8 = "";
    var file_paths = std.ArrayList([]const u8).initCapacity(alloc, 16) catch return;

    while (arg_it.next()) |arg| {
        if (target_name.len == 0) {
            target_name = arg;
        } else {
            file_paths.append(alloc, arg) catch return;
        }
    }

    if (target_name.len == 0) {
        std.debug.print("Usage: fuzz <target> <file1.ss> [file2.ss ...]\n", .{});
        std.debug.print("Targets: forward, reverse, tokenizer\n", .{});
        std.debug.print("Strategies: random (default), boundary, truncate, duplicate, structural, all\n", .{});
        std.process.exit(1);
    }

    const FuzzFn = *const fn (std.mem.Allocator, []const u8) void;
    const fuzz_fn: FuzzFn = if (std.mem.eql(u8, target_name, "forward"))
        fuzzForwardPipeline
    else if (std.mem.eql(u8, target_name, "reverse"))
        fuzzReversePipeline
    else if (std.mem.eql(u8, target_name, "tokenizer"))
        fuzzTokenizer
    else {
        std.debug.print("Unknown target: {s}\n", .{target_name});
        std.process.exit(1);
    };

    std.debug.print("Fuzzing target: {s} with {d} seed files\n", .{ target_name, file_paths.items.len });

    // Read all seed files into memory
    var seeds = std.ArrayList([]const u8).initCapacity(alloc, file_paths.items.len) catch return;
    for (file_paths.items) |fp| {
        const data = std.Io.Dir.cwd().readFileAlloc(io, fp, alloc, .unlimited) catch continue;
        seeds.append(alloc, data) catch continue;
    }

    var iterations: u64 = 0;
    const max_iterations: u64 = 10000;
    var crashes: u64 = 0;

    while (iterations < max_iterations) : (iterations += 1) {
        if (seeds.items.len > 0) {
            const idx = iterations % seeds.items.len;
            const data = seeds.items[idx];

            // Make a mutable copy and apply mutation strategy
            var mutated = alloc.dupe(u8, data) catch continue;
            defer alloc.free(mutated);

            // Cycle through mutation strategies
            const strategy = iterations % 6;
            switch (strategy) {
                0 => mutateRandom(mutated, iterations),
                1 => mutateBoundary(mutated, iterations),
                2 => mutateTruncate(mutated, iterations),
                3 => mutateDuplicate(mutated, iterations),
                4 => mutateStructural(mutated, iterations),
                5 => {
                    // Combine two strategies
                    mutateRandom(mutated, iterations);
                    mutateBoundary(mutated, iterations ^ 0xABCD);
                },
                else => {},
            }

            fuzz_fn(alloc, mutated);
        } else {
            // No seed files — generate random bytes
            const len: usize = @intCast(iterations % 256);
            const data = alloc.alloc(u8, len) catch continue;
            for (data, 0..) |*b, i| {
                b.* = @intCast((@as(u16, @intCast(i + iterations)) & 0xFF));
            }
            fuzz_fn(alloc, data);
        }

        if (iterations % 2000 == 0) {
            std.debug.print("  iterations: {d} (crashes: {d})\n", .{ iterations, crashes });
        }
    }

    std.debug.print("Fuzzing complete: {d} iterations, {d} crashes\n", .{ iterations, crashes });
}
