const std = @import("std");
const forward = @import("forward.zig");
const Stats = forward.Stats;
const io_mod = @import("../io.zig");
const fmt = @import("../diagnostic/format.zig");

// ─── Export & Validation Output Formatters ───────────────────
// Extracted from handlers.zig for single-responsibility.
// These functions handle structured output for export, validate, and check commands.

pub const ExportFormat = enum { json, text, markdown };

// ─── Validation Output ──────────────────────────────────────

/// Format validate/check result as JSON.
pub fn formatValidateResult(alloc: std.mem.Allocator, valid: bool, s: Stats, error_count: u32) ![]const u8 {
    return std.fmt.allocPrint(alloc,
        \\{{"valid":{},"errors":{d},"tables":{d},"fields":{d},"views":{d}}}
    , .{
        valid,
        error_count,
        s.tables,
        s.fields,
        s.views,
    });
}

/// Format validate/check result as SARIF (Static Analysis Results Interchange Format).
pub fn formatValidateSarif(alloc: std.mem.Allocator, valid: bool, error_count: u32) ![]const u8 {
    const version = @import("../version.zig");
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");
    try w.writeAll("  \"$schema\": \"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\n");
    try w.writeAll("  \"version\": \"2.1.0\",\n");
    try w.writeAll("  \"runs\": [{\n");
    try w.writeAll("    \"tool\": {\n");
    try w.writeAll("      \"driver\": {\n");
    try w.writeAll("        \"name\": \"rune\",\n");
    try w.writeAll("        \"informationUri\": \"https://github.com/rune-lang/rune\",\n");
    try w.print("        \"version\": \"{s}\"\n", .{version.VERSION});
    try w.writeAll("      }\n");
    try w.writeAll("    },\n");
    try w.writeAll("    \"results\": [");

    if (!valid and error_count > 0) {
        try w.writeAll("\n      {\n");
        try w.writeAll("        \"ruleId\": \"schema/validation-error\",\n");
        try w.writeAll("        \"level\": \"error\",\n");
        try w.writeAll("        \"message\": {\n");
        try w.writeAll("          \"text\": \"Schema validation failed\"\n");
        try w.writeAll("        },\n");
        try w.writeAll("        \"locations\": [{\"physicalLocation\": {\"artifactLocation\": {\"uri\": \"schema.ss\"}}}]\n");
        try w.writeAll("      }\n");
    }

    try w.writeAll("    ],\n");
    try w.writeAll("    \"invocations\": [{\n");
    try w.writeAll("      \"executionSuccessful\": true,\n");
    try w.writeAll("      \"toolExecutionNotifications\": [");
    if (!valid) {
        try w.writeAll("\n        {\n");
        try w.writeAll("          \"level\": \"error\",\n");
        try w.print("          \"text\": \"Schema has {d} error(s)\"\n", .{error_count});
        try w.writeAll("        }\n");
    }
    try w.writeAll("      ]\n");
    try w.writeAll("    }]\n");
    try w.writeAll("  }]\n");
    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Export Output ──────────────────────────────────────────

/// Export schema as structured data for tooling integration.
pub fn exportSchema(
    io: std.Io,
    alloc: std.mem.Allocator,
    pipeline: forward.PipelineResult,
    output_path: ?[]const u8,
    export_format: ExportFormat,
    quiet: bool,
) !void {
    const output_text = switch (export_format) {
        .json => try exportAsJson(alloc, pipeline),
        .text => try exportAsText(alloc, pipeline),
        .markdown => try exportAsMarkdown(alloc, pipeline),
    };
    try io_mod.writeOutput(io, output_text, output_path, quiet);
}

fn exportAsJson(alloc: std.mem.Allocator, pipeline: forward.PipelineResult) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    const w = &aw.writer;

    try w.writeAll("{\n");

    // Schema info
    if (pipeline.resolved.schema_name) |name| {
        try w.print("  \"schema\": {{\n", .{});
        try w.print("    \"name\": \"{s}\"\n", .{name});
        try w.print("  }},\n", .{});
    }

    // Tables
    try w.print("  \"tables\": [\n", .{});
    for (pipeline.resolved.tables, 0..) |table, i| {
        if (i > 0) try w.writeAll(",\n");
        try w.print("    {{\n", .{});
        try w.print("      \"name\": \"{s}\",\n", .{table.name});
        if (table.template_ref) |tref| {
            try w.print("      \"template\": \"{s}\",\n", .{tref});
        }
        try w.print("      \"fields\": {d},\n", .{table.fields.len});
        try w.print("      \"indexes\": {d},\n", .{table.indexes.len});
        try w.print("      \"foreign_keys\": {d}\n", .{table.fks.len});
        try w.print("    }}", .{});
    }
    try w.writeAll("\n  ]\n");

    try w.writeAll("}\n");

    const result = try aw.toOwnedSlice();
    return result;
}

fn exportAsText(alloc: std.mem.Allocator, pipeline: forward.PipelineResult) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    const w = &aw.writer;

    if (pipeline.resolved.schema_name) |name| {
        try w.print("Schema: {s}\n\n", .{name});
    }

    // Tables
    try w.writeAll("Tables:\n");
    for (pipeline.resolved.tables) |table| {
        try w.print("  # {s}", .{table.name});
        if (table.template_ref) |tref| {
            try w.print(" ({s})", .{tref});
        }
        try w.print(" — {d} fields, {d} indexes, {d} FKs\n", .{ table.fields.len, table.indexes.len, table.fks.len });
    }

    const result = try aw.toOwnedSlice();
    return result;
}

fn exportAsMarkdown(alloc: std.mem.Allocator, pipeline: forward.PipelineResult) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    const w = &aw.writer;

    if (pipeline.resolved.schema_name) |name| {
        try w.print("# Schema: {s}\n\n", .{name});
    }

    // Tables
    try w.writeAll("## Tables\n\n");
    for (pipeline.resolved.tables) |table| {
        try w.print("### `{s}`\n\n", .{table.name});
        if (table.template_ref) |tref| {
            try w.print("Extends: `%{s}`\n\n", .{tref});
        }
        try w.print("| Field | Type |\n|-------|------|\n", .{});
        for (table.fields) |field| {
            try w.print("| `{s}` | {s} |\n", .{ field.name, @tagName(field.type_info) });
        }
        try w.writeAll("\n");
    }

    const result = try aw.toOwnedSlice();
    return result;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;
const test_helpers = @import("../semantic/test_helpers.zig");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const ResolvedTable = resolved_ast.ResolvedTable;

fn makeTestPipeline(alloc: std.mem.Allocator) forward.PipelineResult {
    var tables = std.ArrayList(ResolvedTable).initCapacity(alloc, 2) catch unreachable;
    tables.append(alloc, .{
        .name = "users",
        .comment = null,
        .doc = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .conditional_blocks = &.{},
        .line_no = 1,
    }) catch {};
    tables.append(alloc, .{
        .name = "posts",
        .comment = null,
        .doc = null,
        .engine = null,
        .fields = &.{},
        .fks = &.{},
        .indexes = &.{},
        .conditional_blocks = &.{},
        .line_no = 10,
    }) catch {};

    return .{
        .tree = .{
            .schema = .{ .name = "test_db", .charset = null, .autofk = false, .custom_types = &.{}, .line_no = 1 },
            .templates = &.{},
            .tables = &.{},
            .views = &.{},
            .sql_comments = &.{},
        },
        .resolved = .{
            .schema_name = "test_db",
            .schema_charset = "utf8mb4",
            .custom_types = &.{},
            .tables = tables.items,
            .views = &.{},
            .sql_comments = &.{},
        },
        .lines = &.{},
        .partial = false,
        .skipped_tables = 0,
    };
}

test "formatValidateResult: valid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const s = Stats{ .tables = 5, .fields = 20, .views = 1, .not_null_fields = 15, .numeric_fields = 8, .string_fields = 10, .datetime_fields = 1, .boolean_fields = 1, .other_fields = 0, .foreign_keys = 3, .indexes = 4, .check_constraints = 1, .custom_types = 0 };
    const json = try formatValidateResult(alloc, true, s, 0);
    try testing.expect(std.mem.indexOf(u8, json, "\"valid\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"tables\":5") != null);
}

test "formatValidateResult: invalid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const json = try formatValidateResult(alloc, false, Stats.zero, 3);
    try testing.expect(std.mem.indexOf(u8, json, "\"valid\":false") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"errors\":3") != null);
}

test "formatValidateSarif: valid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const sarif = try formatValidateSarif(alloc, true, 0);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"version\": \"2.1.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"name\": \"rune\"") != null);
}

test "formatValidateSarif: invalid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const sarif = try formatValidateSarif(alloc, false, 2);
    try testing.expect(std.mem.indexOf(u8, sarif, "\"level\": \"error\"") != null);
}

test "exportAsJson: produces valid JSON structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const pipeline = makeTestPipeline(alloc);
    const json = try exportAsJson(alloc, pipeline);
    try testing.expect(std.mem.indexOf(u8, json, "\"schema\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"tables\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"users\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"posts\"") != null);
}

test "exportAsText: produces readable text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const pipeline = makeTestPipeline(alloc);
    const text = try exportAsText(alloc, pipeline);
    try testing.expect(std.mem.indexOf(u8, text, "Schema: test_db") != null);
    try testing.expect(std.mem.indexOf(u8, text, "# users") != null);
    try testing.expect(std.mem.indexOf(u8, text, "# posts") != null);
}

test "exportAsMarkdown: produces markdown tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const pipeline = makeTestPipeline(alloc);
    const md = try exportAsMarkdown(alloc, pipeline);
    try testing.expect(std.mem.indexOf(u8, md, "# Schema: test_db") != null);
    try testing.expect(std.mem.indexOf(u8, md, "## Tables") != null);
    try testing.expect(std.mem.indexOf(u8, md, "`users`") != null);
}
