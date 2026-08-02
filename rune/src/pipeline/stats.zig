const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");

// ─── Schema Statistics ────────────────────────────────────────
//
// Computes field-level statistics from a ResolvedAst.
// Extracted from forward.zig for single-responsibility.

/// Compilation statistics.
pub const Stats = struct {
    tables: usize,
    fields: usize,
    views: usize,
    not_null_fields: usize,
    numeric_fields: usize,
    string_fields: usize,
    datetime_fields: usize,
    boolean_fields: usize,
    other_fields: usize,
};

/// Classify a field's type_info into a stat category.
fn classifyFieldType(type_info: ast_mod.TypeInfo) enum { numeric, string, datetime, boolean, other } {
    if (type_info.isNumeric()) return .numeric;
    if (type_info.isString()) return .string;
    if (type_info.isDatetime()) return .datetime;
    if (type_info.isBoolean()) return .boolean;
    return .other;
}

/// Compute stats from a ResolvedAst.
pub fn computeStats(resolved: resolved_ast.ResolvedAst) Stats {
    var field_count: usize = 0;
    var not_null: usize = 0;
    var numeric: usize = 0;
    var string: usize = 0;
    var datetime: usize = 0;
    var boolean: usize = 0;
    var other: usize = 0;
    for (resolved.tables) |table| {
        for (table.fields) |field| {
            field_count += 1;
            var has_not_null = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .not_null) {
                    has_not_null = true;
                    break;
                }
            }
            if (has_not_null) not_null += 1;
            switch (classifyFieldType(field.type_info)) {
                .numeric => numeric += 1,
                .string => string += 1,
                .datetime => datetime += 1,
                .boolean => boolean += 1,
                .other => other += 1,
            }
        }
    }
    return .{
        .tables = resolved.tables.len,
        .fields = field_count,
        .views = resolved.views.len,
        .not_null_fields = not_null,
        .numeric_fields = numeric,
        .string_fields = string,
        .datetime_fields = datetime,
        .boolean_fields = boolean,
        .other_fields = other,
    };
}

/// Print stats to stderr.
pub fn printStats(stats: Stats) void {
    std.debug.print("tables:           {d}\n", .{stats.tables});
    std.debug.print("fields:           {d}\n", .{stats.fields});
    std.debug.print("  non-null:       {d}\n", .{stats.not_null_fields});
    std.debug.print("  numeric:        {d}\n", .{stats.numeric_fields});
    std.debug.print("  string:         {d}\n", .{stats.string_fields});
    std.debug.print("  datetime:       {d}\n", .{stats.datetime_fields});
    std.debug.print("  boolean:        {d}\n", .{stats.boolean_fields});
    std.debug.print("  other:          {d}\n", .{stats.other_fields});
    std.debug.print("views:            {d}\n", .{stats.views});
}

/// Format stats as a JSON string.
pub fn formatStatsJson(alloc: std.mem.Allocator, stats: Stats) ![]const u8 {
    return std.fmt.allocPrint(alloc,
        \\{{"tables":{d},"fields":{d},"not_null":{d},"numeric":{d},"string":{d},"datetime":{d},"boolean":{d},"other":{d},"views":{d}}}
    , .{
        stats.tables,
        stats.fields,
        stats.not_null_fields,
        stats.numeric_fields,
        stats.string_fields,
        stats.datetime_fields,
        stats.boolean_fields,
        stats.other_fields,
        stats.views,
    });
}
