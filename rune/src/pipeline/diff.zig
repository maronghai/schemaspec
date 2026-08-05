const std = @import("std");
const codegen = @import("../codegen/codegen.zig");
const diff = @import("../diff/engine.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");
const migrate = @import("../diff/migrate.zig");
const migrate_json = @import("../diff/migrate_json.zig");
const migrate_graph = @import("../diff/migrate_graph.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const typed_ast = @import("../types/typed_ast.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const pipeline_forward = @import("../pipeline/forward.zig");
const io_mod = @import("../io.zig");
const enums = @import("../types/enums.zig");
const utils = @import("../utils.zig");

// ─── Diff/Migrate Pipeline ────────────────────────────────────

/// Configuration for `rune diff` — replaces 8-9 positional parameters.
pub const DiffConfig = struct {
    old_path: []const u8,
    new_path: []const u8,
    dialect: codegen.Dialect = .mysql,
    format: enums.DiffFormat = .text,
    output_path: ?[]const u8 = null,
    trace: bool = false,
    stats: bool = false,
    check: bool = false,
    color: enums.ColorMode = .auto,
    summary: bool = false,
};

/// Configuration for `rune migrate` — replaces 10 positional parameters.
pub const MigrateConfig = struct {
    old_path: []const u8,
    new_path: []const u8,
    dialect: codegen.Dialect = .mysql,
    format: enums.DiffFormat = .text,
    output_path: ?[]const u8 = null,
    trace: bool = false,
    stats: bool = false,
    rollback: bool = false,
    dry_run: bool = false,
    check: bool = false,
    name: ?[]const u8 = null,
    dir: ?[]const u8 = null,
    incremental: bool = false,
    summary: bool = false,
    color: enums.ColorMode = .auto,
    graph: bool = false,
};

const DiffResult = struct {
    old_ast: resolved_ast.ResolvedAst,
    new_ast: resolved_ast.ResolvedAst,
    schema_diff: diff_types.SchemaDiff,
};

/// Compile both schemas and compute their diff. Shared by all diff/migrate handlers.
fn prepareDiff(io: std.Io, alloc: std.mem.Allocator, old_path: []const u8, new_path: []const u8) !DiffResult {
    const old_ast = try pipeline_forward.compileToAst(io, alloc, old_path);
    const new_ast = try pipeline_forward.compileToAst(io, alloc, new_path);
    const schema_diff = try diff.diff(old_ast, new_ast, alloc);
    return .{ .old_ast = old_ast, .new_ast = new_ast, .schema_diff = schema_diff };
}

/// Handle `rune diff`: output schema differences between two .ss files.
/// Supports text, JSON, and SARIF output formats via DiffConfig.format.
/// With summary=true, outputs only the summary line without full diff.
pub fn handleDiff(io: std.Io, alloc: std.mem.Allocator, cfg: DiffConfig) !void {
    const result = try prepareDiff(io, alloc, cfg.old_path, cfg.new_path);
    emitTraceAndStats(result, cfg.trace, cfg.stats);

    if (cfg.check) {
        if (result.schema_diff.hasChanges()) {
            // Text format writes the diff before failing (useful for CI output)
            if (cfg.format == .text) {
                const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, cfg.dialect, cfg.color, io);
                try io_mod.writeOutput(io, diff_text, null, false);
            }
            return error.CheckFailed;
        }
        return;
    }

    if (cfg.summary) {
        const summary_text = try diff_format.formatDiffSummary(alloc, result.schema_diff, cfg.color, io);
        try io_mod.writeOutput(io, summary_text, null, false);
        return;
    }

    switch (cfg.format) {
        .text => {
            const diff_text = try diff_format.formatDiff(alloc, result.schema_diff, cfg.dialect, cfg.color, io);
            try io_mod.writeOutput(io, diff_text, null, false);
        },
        .json => {
            const json_text = try diff_format.formatDiffJson(alloc, result.schema_diff);
            try io_mod.writeOutput(io, json_text, cfg.output_path, false);
        },
        .sarif => {
            const sarif_text = try diff_format.formatDiffSarif(alloc, result.schema_diff, cfg.dialect);
            try io_mod.writeOutput(io, sarif_text, null, false);
        },
        .markdown => {
            const md_text = try diff_format.formatDiffMarkdown(alloc, result.schema_diff, cfg.dialect);
            try io_mod.writeOutput(io, md_text, cfg.output_path, false);
        },
    }
}

/// Handle `rune migrate`: generate ALTER TABLE migration SQL (or rollback SQL with --rollback).
/// Supports text and JSON output formats via MigrateConfig.format.
pub fn handleMigrate(io: std.Io, alloc: std.mem.Allocator, cfg: MigrateConfig) !void {
    // Handle --graph flag: show migration dependency graph
    if (cfg.graph) {
        const dir_path = cfg.dir orelse ".";
        var graph = try migrate_graph.buildGraph(io, alloc, dir_path);
        defer graph.deinit();

        var cycles = try migrate_graph.detectCycles(&graph);
        defer {
            for (cycles.items) |cycle| alloc.free(cycle);
            cycles.deinit(alloc);
        }

        if (cycles.items.len > 0) {
            try io_mod.writeOutput(io, "error: circular dependencies detected:\n", null, false);
            for (cycles.items) |cycle| {
                try io_mod.writeOutput(io, cycle, null, false);
                try io_mod.writeOutput(io, "\n", null, false);
            }
            return error.CircularDependency;
        }

        const output = try migrate_graph.formatGraph(alloc, &graph);
        try io_mod.writeOutput(io, output, null, false);
        return;
    }

    const result = try prepareDiff(io, alloc, cfg.old_path, cfg.new_path);
    emitTraceAndStats(result, cfg.trace, cfg.stats);

    if (cfg.check) {
        if (result.schema_diff.hasChanges()) {
            return error.CheckFailed;
        }
        return;
    }

    if (cfg.summary) {
        const summary_text = try diff_format.formatDiffSummary(alloc, result.schema_diff, cfg.color, io);
        try io_mod.writeOutput(io, summary_text, null, false);
        return;
    }

    var output_path = cfg.output_path;
    var generated_name: ?[]const u8 = null;

    // Auto-generate output path from --name or --dir
    if (cfg.dir) |dir| {
        const name_val = cfg.name orelse "migration";
        const next_num = try findNextSequenceNumber(io, alloc, dir);
        generated_name = try formatMigrationFileName(alloc, next_num, name_val);
        output_path = try std.fs.path.join(alloc, &.{ dir, generated_name.? });
    } else if (cfg.name) |name_val| {
        // If --name is provided without --dir, treat output_path as a directory
        // and generate a file inside it, or if no output_path, use current directory
        const target_dir = cfg.output_path orelse ".";
        const next_num = try findNextSequenceNumber(io, alloc, target_dir);
        generated_name = try formatMigrationFileName(alloc, next_num, name_val);
        output_path = try std.fs.path.join(alloc, &.{ target_dir, generated_name.? });
    }

    // Filter incremental changes if --incremental is set
    var filtered_diff = result.schema_diff;
    if (cfg.incremental) {
        filtered_diff = try filterIncrementalChanges(alloc, result.schema_diff);
    }

    switch (cfg.format) {
        .json => {
            const json_text = try migrate_json.generateMigrationJson(alloc, filtered_diff, cfg.dialect);
            try io_mod.writeOutput(io, json_text, output_path, false);
        },
        .text, .sarif, .markdown => {
            // Both text and SARIF produce the same migration SQL; SARIF is diff-only
            if (cfg.rollback) {
                const old_typed = try TypeResolver.resolve(alloc, result.old_ast, cfg.dialect);
                const rollback_sql = try migrate.generateRollback(alloc, filtered_diff, old_typed, result.old_ast, cfg.dialect);
                try io_mod.writeOutput(io, rollback_sql, if (cfg.dry_run) null else output_path, false);
            } else {
                const new_typed = try TypeResolver.resolve(alloc, result.new_ast, cfg.dialect);
                const migration_sql = try migrate.generateFromDiff(alloc, filtered_diff, new_typed, result.new_ast, cfg.dialect);
                try io_mod.writeOutput(io, migration_sql, if (cfg.dry_run) null else output_path, false);
            }
        },
    }
}

/// A parsed migration file entry.
const MigrateFile = struct {
    name: []const u8,
    seq: []const u8,
    label: []const u8,
};

/// Collect migration files from a directory, sorted by sequence number.
fn collectMigrateFiles(io: std.Io, alloc: std.mem.Allocator, dir_path: []const u8) ![]MigrateFile {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| {
        const msg = try std.fmt.allocPrint(alloc, "error: cannot open directory '{s}': {}\n", .{ dir_path, err });
        try io_mod.writeOutput(io, msg, null, false);
        return error.MigrationDirectoryError;
    };
    defer dir.close(io);

    var entries = try std.ArrayList(MigrateFile).initCapacity(alloc, 16);
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (name.len > 4 and std.mem.eql(u8, name[name.len - 4 ..], ".sql")) {
            const base = name[0 .. name.len - 4];
            if (std.mem.indexOfScalar(u8, base, '_')) |underscore_pos| {
                const digits = base[0..underscore_pos];
                if (digits.len > 0) {
                    if (std.fmt.parseInt(u32, digits, 10)) |_| {
                        const owned_name = try alloc.dupe(u8, name);
                        try entries.append(alloc, .{
                            .name = owned_name,
                            .seq = base[0..underscore_pos],
                            .label = base[underscore_pos + 1 ..],
                        });
                    } else |_| {}
                }
            }
        }
    }

    std.mem.sort(MigrateFile, entries.items, {}, struct {
        fn lessThan(_: void, a: MigrateFile, b: MigrateFile) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    return try entries.toOwnedSlice(alloc);
}

/// Handle `rune migrate status`: list migration files in a directory.
/// Supports both 3-digit (legacy) and 4-digit (current) sequence prefixes.
/// With json_errors=true, outputs JSON for CI tooling.
pub fn handleMigrateStatus(io: std.Io, alloc: std.mem.Allocator, dir_path: ?[]const u8, json_errors: bool) !void {
    const target_dir = dir_path orelse ".";
    const files = collectMigrateFiles(io, alloc, target_dir) catch return;

    if (json_errors) {
        if (files.len == 0) {
            try io_mod.writeOutput(io, "{\"files\":[],\"count\":0}", null, false);
            return;
        }
        var aw = std.Io.Writer.Allocating.init(alloc);
        const w = &aw.writer;
        try w.writeAll("{\"files\":[");
        for (files, 0..) |f, idx| {
            if (idx > 0) try w.writeAll(",");
            try w.writeAll("{\"name\":\"");
            try utils.jsonEscapeString(w, f.name);
            try w.writeAll("\",\"label\":\"");
            try utils.jsonEscapeString(w, f.label);
            try w.writeAll("\"}");
        }
        try w.print("],\"count\":{d}}}", .{files.len});
        try w.flush();
        const json = try aw.toOwnedSlice();
        try io_mod.writeOutput(io, json, null, false);
        return;
    }

    if (files.len == 0) {
        const msg = try std.fmt.allocPrint(alloc, "No migration files found in '{s}'\n", .{target_dir});
        try io_mod.writeOutput(io, msg, null, false);
        return;
    }

    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;
    try w.print("Migration files in '{s}':\n", .{target_dir});
    for (files) |f| {
        try w.print("  {s} — {s}\n", .{ f.seq, f.label });
    }
    try w.flush();
    const output = try aw.toOwnedSlice();
    try io_mod.writeOutput(io, output, null, false);
}

/// Find the next sequence number for migration files in a directory.
/// Scans for NNNN_*.sql files and returns max(NNNN) + 1, or 1 if none found.
fn findNextSequenceNumber(io: std.Io, alloc: std.mem.Allocator, dir_path: []const u8) !u32 {
    var max_num: u32 = 0;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return 1;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (name.len > 4 and std.mem.eql(u8, name[name.len - 4 ..], ".sql")) {
            const base = name[0 .. name.len - 4];
            // Find the first underscore separator — supports both 3-digit (legacy) and 4-digit sequences
            if (std.mem.indexOfScalar(u8, base, '_')) |underscore_pos| {
                const digits = base[0..underscore_pos];
                if (std.fmt.parseInt(u32, digits, 10)) |num| {
                    if (num > max_num) max_num = num;
                } else |_| {}
            }
        }
    }
    _ = alloc;
    return max_num + 1;
}

/// Format a migration file name: "0001_name.sql"
fn formatMigrationFileName(alloc: std.mem.Allocator, seq: u32, name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d:0>4}_{s}.sql", .{ seq, name });
}

/// Filter incremental changes: remove pure comment/metadata diffs.
fn filterIncrementalChanges(alloc: std.mem.Allocator, sd: diff_types.SchemaDiff) !diff_types.SchemaDiff {
    var result = sd;
    // Filter table_diffs: remove tables with only metadata (comment/engine) changes
    var filtered_tables = try std.ArrayList(diff_types.TableDiff).initCapacity(alloc, result.table_diffs.len);
    for (result.table_diffs) |td| {
        const has_structural = td.field_diffs.len > 0 or td.index_diffs.len > 0 or td.fk_diffs.len > 0;
        const is_action = td.action == .create;
        if (has_structural or is_action) {
            try filtered_tables.append(alloc, td);
        }
    }
    result.table_diffs = try filtered_tables.toOwnedSlice(alloc);
    return result;
}

/// Emit trace and stats for a diff result — extracted to eliminate 4x duplication.
fn emitTraceAndStats(result: DiffResult, trace: bool, stats: bool) void {
    if (trace) traceDiffResult(result);
    if (stats) {
        const old_s = pipeline_forward.computeStats(result.old_ast);
        const new_s = pipeline_forward.computeStats(result.new_ast);
        std.debug.print("old: tables={d} fields={d} views={d}\n", .{ old_s.tables, old_s.fields, old_s.views });
        std.debug.print("new: tables={d} fields={d} views={d}\n", .{ new_s.tables, new_s.fields, new_s.views });
    }
}

// ─── Trace Helpers ──────────────────────────────────────────────

fn traceDiffResult(result: DiffResult) void {
    traceResolvedAst("old", result.old_ast);
    traceResolvedAst("new", result.new_ast);
    traceSchemaDiff(result.schema_diff);
}

fn traceResolvedAst(label: []const u8, ast: resolved_ast.ResolvedAst) void {
    std.debug.print("=== [{s} ResolvedAst] ===\n\n", .{label});
    std.debug.print("Schema: {?s}\n", .{ast.schema_name});
    std.debug.print("Tables ({d}):\n", .{ast.tables.len});
    for (ast.tables) |table| {
        std.debug.print("  # {s} ({d} fields, {d} fks, {d} indexes)\n", .{ table.name, table.fields.len, table.fks.len, table.indexes.len });
    }
    std.debug.print("\n", .{});
}

fn traceSchemaDiff(sd: diff_types.SchemaDiff) void {
    std.debug.print("=== [SchemaDiff] ===\n\n", .{});
    if (sd.dropped_tables.len > 0) {
        std.debug.print("Dropped tables ({d}):\n", .{sd.dropped_tables.len});
        for (sd.dropped_tables) |tname| {
            std.debug.print("  - {s}\n", .{tname});
        }
    }
    for (sd.table_diffs) |td| {
        std.debug.print("Table {s}: {s}\n", .{ td.name, @tagName(td.action) });
        for (td.field_diffs) |fd| {
            std.debug.print("  field {s}: {s}", .{ fd.name, @tagName(fd.action) });
            if (fd.rename_from) |rf| std.debug.print(" from {s}", .{rf});
            std.debug.print("\n", .{});
        }
        for (td.index_diffs) |idx| {
            std.debug.print("  index {s}: {s}\n", .{ idx.name, @tagName(idx.action) });
        }
    }
    std.debug.print("\n", .{});
}
