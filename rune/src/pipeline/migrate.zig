const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const diff_types = @import("../diff/types.zig");
const diff_format = @import("../diff/format.zig");
const migrate = @import("../diff/migrate.zig");
const migrate_json = @import("../diff/migrate_json.zig");
const migrate_graph = @import("../diff/migrate_graph.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const pipeline_forward = @import("../pipeline/forward.zig");
const io_mod = @import("../io.zig");
const enums = @import("../types/enums.zig");
const utils = @import("../utils.zig");
const diff_pipe = @import("diff.zig");

// ─── Migrate Pipeline ─────────────────────────────────────────

/// Configuration for `rune migrate` — replaces 10 positional parameters.
pub const MigrateConfig = struct {
    old_path: []const u8,
    new_path: []const u8,
    dialect: dialect_enum.Dialect = .mysql,
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
    /// When true (default), auto-lint and fix the new schema before migration.
    /// Set to false with --no-lint to skip auto-fix.
    auto_lint: bool = true,
};

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

    // Auto-lint: apply lint fixes to the new schema before migration
    var actual_new_path = cfg.new_path;
    if (cfg.auto_lint) {
        const lint_mod = @import("../lint.zig");
        const lint_config = @import("../lint/config.zig");
        const new_source = try io_mod.readFileOrStdin(io, alloc, cfg.new_path);
        const new_ast = try pipeline_forward.compileToAstWithDialect(io, alloc, cfg.new_path, cfg.dialect);
        const lint_results = try lint_mod.lintSchema(alloc, new_ast, .{});

        // Check if any fixable issues exist
        var has_fixable = false;
        for (lint_results.items) |r| {
            if (lint_config.LintRule.fromName(r.rule)) |rule| {
                if (rule.isFixable()) {
                    has_fixable = true;
                    break;
                }
            }
        }

        if (has_fixable) {
            const fix_result = try lint_mod.lintFix(alloc, new_source, lint_results.items);
            if (fix_result.fixes.len > 0) {
                // Write fixed source to a temp file and use it for migration.
                // Deleted after the diff completes so no `.lint-fixed.ss`
                // litter is left in the user's schema directory.
                const tmp_path = try std.fmt.allocPrint(alloc, "{s}.lint-fixed.ss", .{cfg.new_path});
                var tmp_used = false;
                defer if (tmp_used) std.Io.Dir.cwd().deleteFile(io, tmp_path) catch {};
                errdefer {
                    tmp_used = false;
                }
                try io_mod.writeOutput(io, fix_result.source, tmp_path, true);
                actual_new_path = tmp_path;
                tmp_used = true;
                // Report fixes to stderr
                for (fix_result.fixes) |fx| {
                    try io_mod.writeOutput(io, try std.fmt.allocPrint(alloc, "fixed: [{s}] {s} — {s}\n", .{ fx.rule, fx.table, fx.description }), null, true);
                }
            }
        }
    }

    const result = try diff_pipe.prepareDiffWithDialect(io, alloc, cfg.old_path, actual_new_path, cfg.dialect);
    diff_pipe.emitTraceAndStats(result, cfg.trace, cfg.stats);

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
                        // seq/label must be duped too: entry.name is an iterator-reused
                        // buffer, so slices into it are overwritten by the next iteration.
                        const owned_name = try alloc.dupe(u8, name);
                        const owned_base = try alloc.dupe(u8, base);
                        try entries.append(alloc, .{
                            .name = owned_name,
                            .seq = owned_base[0..underscore_pos],
                            .label = owned_base[underscore_pos + 1 ..],
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
pub fn formatMigrationFileName(alloc: std.mem.Allocator, seq: u32, name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d:0>4}_{s}.sql", .{ seq, name });
}

/// Filter incremental changes: remove pure comment/metadata diffs.
pub fn filterIncrementalChanges(alloc: std.mem.Allocator, sd: diff_types.SchemaDiff) !diff_types.SchemaDiff {
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
