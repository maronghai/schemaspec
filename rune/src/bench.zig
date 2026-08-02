const std = @import("std");
const tokenizer = @import("parser/tokenizer.zig");
const parser = @import("parser/parser.zig");
const ast_mod = @import("types/ast.zig");
const semantic = @import("semantic/analyzer.zig");
const codegen = @import("codegen/codegen.zig");
const typed_ast = @import("types/typed_ast.zig");
const TypeResolver = @import("types/type_resolver.zig").TypeResolver;
const diag = @import("semantic/diagnostic.zig");
const dialect_enum = @import("dialect/enum.zig");

// ─── Rune Benchmark ─────────────────────────────────────────
// Measures per-stage latency for the forward pipeline.
// Usage:
//   zig build bench                          — run benchmark, output JSON
//   zig build bench -- --save                — run & save as baseline
//   zig build bench -- --check               — run & compare against baseline
//   zig build bench -- <file> [iterations]   — custom file/iterations

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    const args = try parseBenchArgs(init.minimal.args);

    if (args.help) {
        printUsage();
        return;
    }

    if (args.mode == .list) {
        listStages();
        return;
    }

    // Read file
    const file_data = try std.Io.Dir.cwd().readFileAlloc(init.io, args.file_path, alloc, .unlimited);
    defer alloc.free(file_data);

    // Warm up (3 iterations to stabilize CPU cache)
    {
        var w: usize = 0;
        while (w < args.warmup) : (w += 1) {
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();
            const a = arena.allocator();
            _ = try runPipeline(a, file_data, args.dialect);
        }
    }

    // Benchmark
    var times = StageTimes{};

    var i: usize = 0;
    while (i < args.iterations) : (i += 1) {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        var t = try runPipelineTimed(init.io, a, file_data, args.dialect);
        times.add(&t);
    }

    const avg = times.avg(args.iterations);

    switch (args.mode) {
        .run => {
            printJson(args.file_path, args.iterations, avg, args.dialect);
        },
        .save => {
            printJson(args.file_path, args.iterations, avg, args.dialect);
            try saveBaseline(init.io, alloc, args.file_path, avg, args.dialect);
            std.debug.print("\nBaseline saved to bench/baseline-{s}.json\n", .{@tagName(args.dialect)});
        },
        .check => {
            const baseline = loadBaseline(init.io, alloc, args.dialect) catch |err| {
                std.debug.print("error: cannot load bench/baseline-{s}.json: {s}\n", .{ @tagName(args.dialect), @errorName(err) });
                std.debug.print("Run 'zig build bench -- --save --dialect {s}' first to create baseline.\n", .{@tagName(args.dialect)});
                return error.BaselineNotFound;
            };
            const regressions = checkRegressions(avg, baseline);
            if (regressions > 0) {
                std.debug.print("\nBENCHMARK REGRESSION DETECTED ({d} stage(s))\n", .{regressions});
                printRegressionDetails(avg, baseline);
                std.process.exit(1);
            } else {
                std.debug.print("Benchmark OK — no regressions (threshold: 10%)\n", .{});
            }
        },
        .diff => {
            const baseline = loadBaseline(init.io, alloc, args.dialect) catch |err| {
                std.debug.print("error: cannot load bench/baseline-{s}.json: {s}\n", .{ @tagName(args.dialect), @errorName(err) });
                std.debug.print("Run 'zig build bench -- --save --dialect {s}' first to create baseline.\n", .{@tagName(args.dialect)});
                return error.BaselineNotFound;
            };
            printDiff(avg, baseline);
        },
    }
}

const BenchArgs = struct {
    file_path: []const u8 = "bench/small.ss",
    iterations: usize = 50,
    warmup: usize = 3,
    mode: enum { run, save, check, diff, list } = .run,
    dialect: dialect_enum.Dialect = .mysql,
    help: bool = false,
};

fn parseBenchArgs(minimal_args: anytype) !BenchArgs {
    var args = BenchArgs{};

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal_args, std.heap.page_allocator);
    defer arg_it.deinit();
    _ = arg_it.next(); // skip program name
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--save")) {
            args.mode = .save;
        } else if (std.mem.eql(u8, arg, "--check")) {
            args.mode = .check;
        } else if (std.mem.eql(u8, arg, "--diff")) {
            args.mode = .diff;
        } else if (std.mem.eql(u8, arg, "--list")) {
            args.mode = .list;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.help = true;
        } else if (std.mem.eql(u8, arg, "--dialect") or std.mem.eql(u8, arg, "-d")) {
            if (arg_it.next()) |d| {
                args.dialect = parseDialect(d) catch {
                    std.debug.print("error: unknown dialect '{s}'. Expected: mysql, pg, sqlite, mssql, oracle, db2\n", .{d});
                    return error.UnknownDialect;
                };
            } else {
                std.debug.print("error: --dialect requires a value\n", .{});
                return error.MissingDialectValue;
            }
        } else {
            args.file_path = arg;
            if (arg_it.next()) |n_str| args.iterations = std.fmt.parseInt(usize, n_str, 10) catch 50;
        }
    }
    return args;
}

fn printUsage() void {
    std.debug.print("Usage: bench [--save|--check|--diff|--list] [--dialect <d>] [file] [iterations]\n", .{});
    std.debug.print("  --save      Save current run as baseline\n", .{});
    std.debug.print("  --check     Check for regressions vs baseline (>10% = exit 1)\n", .{});
    std.debug.print("  --diff      Show per-stage comparison with baseline\n", .{});
    std.debug.print("  --list      Show available benchmark stages\n", .{});
    std.debug.print("  --dialect   SQL dialect: mysql (default), pg, sqlite, mssql, oracle, db2\n", .{});
}

fn listStages() void {
    std.debug.print("Benchmark stages:\n", .{});
    std.debug.print("  tokenize     Tokenize .ss source into lines\n", .{});
    std.debug.print("  parse        Parse tokens into AST\n", .{});
    std.debug.print("  semantic     Run semantic analysis passes\n", .{});
    std.debug.print("  type_resolve Resolve SS types to SQL types\n", .{});
    std.debug.print("  codegen      Generate SQL DDL from TypedAst\n", .{});
    std.debug.print("\nModes: --save (save baseline), --check (regression gate), --diff (compare)\n", .{});
}

pub const StageTimes = struct {
    tokenize: f64 = 0,
    parse: f64 = 0,
    semantic: f64 = 0,
    type_resolve: f64 = 0,
    codegen: f64 = 0,

    pub fn add(self: *StageTimes, other: *const StageTimes) void {
        self.tokenize += other.tokenize;
        self.parse += other.parse;
        self.semantic += other.semantic;
        self.type_resolve += other.type_resolve;
        self.codegen += other.codegen;
    }

    pub fn avg(self: StageTimes, n: usize) StageTimes {
        const f: f64 = @floatFromInt(n);
        return .{
            .tokenize = self.tokenize / f,
            .parse = self.parse / f,
            .semantic = self.semantic / f,
            .type_resolve = self.type_resolve / f,
            .codegen = self.codegen / f,
        };
    }

    pub fn total(self: StageTimes) f64 {
        return self.tokenize + self.parse + self.semantic + self.type_resolve + self.codegen;
    }
};

fn nsToMs(ns: i96) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn printJson(file_path: []const u8, iterations: usize, avg: StageTimes, dialect: dialect_enum.Dialect) void {
    std.debug.print(
        \\{{
        \\  "file": "{s}",
        \\  "dialect": "{s}",
        \\  "iterations": {d},
        \\  "stages": {{
        \\    "tokenize": {d:.2},
        \\    "parse": {d:.2},
        \\    "semantic": {d:.2},
        \\    "type_resolve": {d:.2},
        \\    "codegen": {d:.2}
        \\  }},
        \\  "total_ms": {d:.2}
        \\}}
        \\
    , .{
        file_path,
        @tagName(dialect),
        iterations,
        avg.tokenize,
        avg.parse,
        avg.semantic,
        avg.type_resolve,
        avg.codegen,
        avg.total(),
    });
}

pub const Baseline = struct {
    tokenize: f64,
    parse: f64,
    semantic: f64,
    type_resolve: f64,
    codegen: f64,

    pub fn total(self: Baseline) f64 {
        return self.tokenize + self.parse + self.semantic + self.type_resolve + self.codegen;
    }
};

fn saveBaseline(io: std.Io, alloc: std.mem.Allocator, file_path: []const u8, avg: StageTimes, dialect: dialect_enum.Dialect) !void {
    const json = try std.fmt.allocPrint(alloc,
        \\{{
        \\  "file": "{s}",
        \\  "dialect": "{s}",
        \\  "stages": {{
        \\    "tokenize": {d:.2},
        \\    "parse": {d:.2},
        \\    "semantic": {d:.2},
        \\    "type_resolve": {d:.2},
        \\    "codegen": {d:.2}
        \\  }}
        \\}}
        \\
    , .{
        file_path,
        @tagName(dialect),
        avg.tokenize,
        avg.parse,
        avg.semantic,
        avg.type_resolve,
        avg.codegen,
    });
    defer alloc.free(json);

    const path = try std.fmt.allocPrint(alloc, "bench/baseline-{s}.json", .{@tagName(dialect)});
    defer alloc.free(path);

    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = json,
    }) catch |err| {
        std.debug.print("error: cannot write {s}: {s}\n", .{ path, @errorName(err) });
        std.debug.print("Make sure the bench/ directory exists: mkdir -p bench\n", .{});
        return err;
    };
}

fn loadBaseline(io: std.Io, alloc: std.mem.Allocator, dialect: dialect_enum.Dialect) !Baseline {
    const path = try std.fmt.allocPrint(alloc, "bench/baseline-{s}.json", .{@tagName(dialect)});
    defer alloc.free(path);

    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(data);

    // Simple JSON parsing — extract stage values
    var baseline: Baseline = .{
        .tokenize = 0,
        .parse = 0,
        .semantic = 0,
        .type_resolve = 0,
        .codegen = 0,
    };

    const fields = [_]struct { name: []const u8, ptr: *f64 }{
        .{ .name = "\"tokenize\":", .ptr = &baseline.tokenize },
        .{ .name = "\"parse\":", .ptr = &baseline.parse },
        .{ .name = "\"semantic\":", .ptr = &baseline.semantic },
        .{ .name = "\"type_resolve\":", .ptr = &baseline.type_resolve },
        .{ .name = "\"codegen\":", .ptr = &baseline.codegen },
    };

    for (fields) |f| {
        if (std.mem.indexOf(u8, data, f.name)) |pos| {
            const start = pos + f.name.len;
            // Skip whitespace
            var i = start;
            while (i < data.len and data[i] == ' ') i += 1;
            // Parse number
            const num_start = i;
            while (i < data.len and (data[i] >= '0' and data[i] <= '9' or data[i] == '.')) i += 1;
            f.ptr.* = std.fmt.parseFloat(f64, data[num_start..i]) catch 0;
        }
    }

    return baseline;
}

pub fn checkRegressions(current: StageTimes, baseline: Baseline) usize {
    const threshold = 1.10; // 10% regression threshold
    var count: usize = 0;
    const stages = stagePairs(current, baseline);
    for (stages) |s| {
        if (s.baseline > 0 and s.current / s.baseline > threshold) count += 1;
    }
    return count;
}

fn printRegressionDetails(current: StageTimes, baseline: Baseline) void {
    const threshold = 1.10;
    const stages = stagePairs(current, baseline);

    std.debug.print("\nStage Details (baseline → current, threshold: 10%):\n", .{});
    for (stages) |s| {
        if (s.baseline > 0) {
            const change = ((s.current - s.baseline) / s.baseline) * 100.0;
            const sign: []const u8 = if (change >= 0) "+" else "";
            const marker: []const u8 = if (s.current / s.baseline > threshold) " REGRESSION" else "";
            std.debug.print("  {s: <15} {d:.2}ms → {d:.2}ms ({s}{d:.1}%){s}\n", .{ s.name, s.baseline, s.current, sign, change, marker });
        }
    }

    const cur_total = current.total();
    const bas_total = baseline.total();
    if (bas_total > 0) {
        const change = ((cur_total - bas_total) / bas_total) * 100.0;
        const sign: []const u8 = if (change >= 0) "+" else "";
        std.debug.print("  {s: <15} {d:.2}ms → {d:.2}ms ({s}{d:.1}%)\n", .{ "TOTAL", bas_total, cur_total, sign, change });
    }
}

fn printDiff(current: StageTimes, baseline: Baseline) void {
    const stages = stagePairs(current, baseline);

    std.debug.print("\nStage Comparison (current vs baseline):\n", .{});
    std.debug.print("  {s: <15} {s: >10} {s: >10} {s: >10}\n", .{ "Stage", "Baseline", "Current", "Change" });
    std.debug.print("  {s: <15} {s: >10} {s: >10} {s: >10}\n", .{ "---", "---", "---", "---" });

    for (stages) |s| {
        if (s.baseline > 0) {
            const change = ((s.current - s.baseline) / s.baseline) * 100.0;
            const sign: []const u8 = if (change >= 0) "+" else "";
            std.debug.print("  {s: <15} {d:>9.2}ms {d:>9.2}ms {s}{d:.1}%\n", .{ s.name, s.baseline, s.current, sign, change });
        } else {
            std.debug.print("  {s: <15} {s:>10} {d:>9.2}ms {s:>10}\n", .{ s.name, "N/A", s.current, "new" });
        }
    }

    const cur_total = current.total();
    const bas_total = baseline.total();
    if (bas_total > 0) {
        const change = ((cur_total - bas_total) / bas_total) * 100.0;
        const sign: []const u8 = if (change >= 0) "+" else "";
        std.debug.print("  {s: <15} {d:>9.2}ms {d:>9.2}ms {s}{d:.1}%\n", .{ "TOTAL", bas_total, cur_total, sign, change });
    }
}

pub const StagePair = struct { name: []const u8, current: f64, baseline: f64 };

pub fn stagePairs(current: StageTimes, baseline: Baseline) [5]StagePair {
    return .{
        .{ .name = "tokenize", .current = current.tokenize, .baseline = baseline.tokenize },
        .{ .name = "parse", .current = current.parse, .baseline = baseline.parse },
        .{ .name = "semantic", .current = current.semantic, .baseline = baseline.semantic },
        .{ .name = "type_resolve", .current = current.type_resolve, .baseline = baseline.type_resolve },
        .{ .name = "codegen", .current = current.codegen, .baseline = baseline.codegen },
    };
}

/// Shared pipeline initialization: tokenize → parse. Returns the parsed AST.
fn parseFileTimed(alloc: std.mem.Allocator, file_data: []const u8, times: *StageTimes, io: std.Io) !ast_mod.Ast {
    // Tokenize
    var sw_start = std.Io.Clock.Timestamp.now(io, .awake);
    var lines = try std.ArrayList([]const u8).initCapacity(alloc, 256);
    var line_it = std.mem.splitScalar(u8, file_data, '\n');
    while (line_it.next()) |line| {
        try lines.append(alloc, std.mem.trimEnd(u8, line, "\r"));
    }
    const tok = tokenizer.Tokenizer.init(try lines.toOwnedSlice(alloc));
    const tokenized = try tok.tokenizeAll(alloc);
    times.tokenize = nsToMs(std.Io.Clock.Timestamp.now(io, .awake).raw.nanoseconds - sw_start.raw.nanoseconds);

    // Parse
    sw_start = std.Io.Clock.Timestamp.now(io, .awake);
    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    const tree = try p.parse(tokenized);
    times.parse = nsToMs(std.Io.Clock.Timestamp.now(io, .awake).raw.nanoseconds - sw_start.raw.nanoseconds);

    return tree;
}

fn runPipelineTimed(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, dialect: dialect_enum.Dialect) !StageTimes {
    var times = StageTimes{};

    // Stage 1: Tokenize + Parse (separate timing)
    const tree = try parseFileTimed(alloc, file_data, &times, io);

    // Stage 2: Semantic
    var sw_start = std.Io.Clock.Timestamp.now(io, .awake);
    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = try sa.analyze(tree);
    times.semantic = nsToMs(std.Io.Clock.Timestamp.now(io, .awake).raw.nanoseconds - sw_start.raw.nanoseconds);

    // Stage 3: Type Resolve
    sw_start = std.Io.Clock.Timestamp.now(io, .awake);
    const typed = try TypeResolver.resolve(alloc, resolved, dialect);
    times.type_resolve = nsToMs(std.Io.Clock.Timestamp.now(io, .awake).raw.nanoseconds - sw_start.raw.nanoseconds);

    // Stage 4: Codegen
    sw_start = std.Io.Clock.Timestamp.now(io, .awake);
    var cg = codegen.Codegen.init(alloc, dialect);
    _ = try cg.generateFromTypedAst(typed);
    times.codegen = nsToMs(std.Io.Clock.Timestamp.now(io, .awake).raw.nanoseconds - sw_start.raw.nanoseconds);

    return times;
}

/// Shared pipeline initialization: tokenize → parse (no timing). Returns the parsed AST.
fn parseFile(alloc: std.mem.Allocator, file_data: []const u8) !ast_mod.Ast {
    var lines = try std.ArrayList([]const u8).initCapacity(alloc, 256);
    var line_it = std.mem.splitScalar(u8, file_data, '\n');
    while (line_it.next()) |line| {
        try lines.append(alloc, std.mem.trimEnd(u8, line, "\r"));
    }
    const tok = tokenizer.Tokenizer.init(try lines.toOwnedSlice(alloc));
    const tokenized = try tok.tokenizeAll(alloc);

    var diagnostics = try diag.DiagnosticCollector.init(alloc);
    var p = parser.Parser.initWithDiagnostics(alloc, &diagnostics);
    return try p.parse(tokenized);
}

fn runPipeline(alloc: std.mem.Allocator, file_data: []const u8, dialect: dialect_enum.Dialect) ![]const u8 {
    const tree = try parseFile(alloc, file_data);

    var sa = semantic.SemanticAnalyzer.init(alloc);
    const resolved = try sa.analyze(tree);

    const typed = try TypeResolver.resolve(alloc, resolved, dialect);

    var cg = codegen.Codegen.init(alloc, dialect);
    return try cg.generateFromTypedAst(typed);
}

pub fn parseDialect(s: []const u8) !dialect_enum.Dialect {
    if (std.mem.eql(u8, s, "mysql")) return .mysql;
    if (std.mem.eql(u8, s, "pg") or std.mem.eql(u8, s, "postgres")) return .pg;
    if (std.mem.eql(u8, s, "sqlite")) return .sqlite;
    if (std.mem.eql(u8, s, "mssql") or std.mem.eql(u8, s, "sqlserver")) return .mssql;
    if (std.mem.eql(u8, s, "oracle") or std.mem.eql(u8, s, "ora")) return .oracle;
    if (std.mem.eql(u8, s, "db2") or std.mem.eql(u8, s, "idb2")) return .db2;
    return error.UnknownDialect;
}
