const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");

// ─── Schema Statistics ────────────────────────────────────────
//
// Computes field-level statistics from a ResolvedAst.
// Extracted from forward.zig for single-responsibility.

/// Per-table statistics.
pub const TableStats = struct {
    name: []const u8,
    fields: usize,
    not_null_fields: usize,
    numeric_fields: usize,
    string_fields: usize,
    datetime_fields: usize,
    boolean_fields: usize,
    other_fields: usize,
    foreign_keys: usize,
    indexes: usize,
    check_constraints: usize,
};

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
    foreign_keys: usize,
    indexes: usize,
    check_constraints: usize,
    custom_types: usize,
};

/// Classify a field's type_info into a stat category.
fn classifyFieldType(type_info: ast_mod.TypeInfo) enum { numeric, string, datetime, boolean, other } {
    if (type_info.isNumeric()) return .numeric;
    if (type_info.isString()) return .string;
    if (type_info.isDatetime()) return .datetime;
    if (type_info.isBoolean()) return .boolean;
    return .other;
}

/// Compute per-table statistics from a ResolvedAst.
pub fn computePerTableStats(resolved: resolved_ast.ResolvedAst) []TableStats {
    var stats = std.ArrayList(TableStats).initCapacity(std.heap.page_allocator, resolved.tables.len) catch return &.{};
    for (resolved.tables) |table| {
        var field_count: usize = 0;
        var not_null: usize = 0;
        var numeric: usize = 0;
        var string: usize = 0;
        var datetime: usize = 0;
        var boolean: usize = 0;
        var other: usize = 0;
        var check_count: usize = 0;
        for (table.fields) |field| {
            field_count += 1;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .nullable) {
                    has_nullable = true;
                    break;
                }
            }
            if (!has_nullable) not_null += 1;
            switch (classifyFieldType(field.type_info)) {
                .numeric => numeric += 1,
                .string => string += 1,
                .datetime => datetime += 1,
                .boolean => boolean += 1,
                .other => other += 1,
            }
            if (field.check != null) check_count += 1;
        }
        stats.append(std.heap.page_allocator, .{
            .name = table.name,
            .fields = field_count,
            .not_null_fields = not_null,
            .numeric_fields = numeric,
            .string_fields = string,
            .datetime_fields = datetime,
            .boolean_fields = boolean,
            .other_fields = other,
            .foreign_keys = table.fks.len,
            .indexes = table.indexes.len,
            .check_constraints = check_count,
        }) catch {};
    }
    return stats.toOwnedSlice(std.heap.page_allocator) catch return &.{};
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
    var fk_count: usize = 0;
    var idx_count: usize = 0;
    var check_count: usize = 0;
    for (resolved.tables) |table| {
        for (table.fields) |field| {
            field_count += 1;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .nullable) {
                    has_nullable = true;
                    break;
                }
            }
            if (!has_nullable) not_null += 1;
            switch (classifyFieldType(field.type_info)) {
                .numeric => numeric += 1,
                .string => string += 1,
                .datetime => datetime += 1,
                .boolean => boolean += 1,
                .other => other += 1,
            }
            if (field.check != null) check_count += 1;
        }
        fk_count += table.fks.len;
        idx_count += table.indexes.len;
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
        .foreign_keys = fk_count,
        .indexes = idx_count,
        .check_constraints = check_count,
        .custom_types = resolved.custom_types.len,
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
    std.debug.print("foreign_keys:     {d}\n", .{stats.foreign_keys});
    std.debug.print("indexes:          {d}\n", .{stats.indexes});
    std.debug.print("check_constraints:{d}\n", .{stats.check_constraints});
    std.debug.print("custom_types:    {d}\n", .{stats.custom_types});
}

/// Format stats as a JSON string.
pub fn formatStatsJson(alloc: std.mem.Allocator, stats: Stats) ![]const u8 {
    return std.fmt.allocPrint(alloc,
        \\{{"tables":{d},"fields":{d},"not_null":{d},"numeric":{d},"string":{d},"datetime":{d},"boolean":{d},"other":{d},"views":{d},"foreign_keys":{d},"indexes":{d},"check_constraints":{d},"custom_types":{d}}}
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
        stats.foreign_keys,
        stats.indexes,
        stats.check_constraints,
        stats.custom_types,
    });
}

/// Format stats as a compact one-line summary.
pub fn formatSummary(stats: Stats) ![]const u8 {
    return std.fmt.allocPrint(std.heap.page_allocator,
        "{d} table(s), {d} field(s), {d} view(s), {d} FK(s), {d} index(es), {d} check(s), {d} type(s)",
        .{ stats.tables, stats.fields, stats.views, stats.foreign_keys, stats.indexes, stats.check_constraints, stats.custom_types },
    );
}

/// Format stats as a Markdown table.
pub fn formatStatsMarkdown(alloc: std.mem.Allocator, stats: Stats) ![]const u8 {
    return std.fmt.allocPrint(alloc,
        \\## Schema Statistics
        \\
        \\| Metric | Count |
        \\|--------|-------|
        \\| Tables | {d} |
        \\| Fields | {d} |
        \\| Non-null fields | {d} |
        \\| Numeric fields | {d} |
        \\| String fields | {d} |
        \\| Datetime fields | {d} |
        \\| Boolean fields | {d} |
        \\| Other fields | {d} |
        \\| Views | {d} |
        \\| Foreign keys | {d} |
        \\| Indexes | {d} |
        \\| Check constraints | {d} |
        \\| Custom types | {d} |
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
        stats.foreign_keys,
        stats.indexes,
        stats.check_constraints,
        stats.custom_types,
    });
}

// ─── Per-Table Output ──────────────────────────────────────────

/// Print per-table stats to stderr.
pub fn printPerTableStats(table_stats: []const TableStats) void {
    for (table_stats) |ts| {
        std.debug.print("\n{s}:\n", .{ts.name});
        std.debug.print("  fields:         {d}\n", .{ts.fields});
        std.debug.print("  non-null:       {d}\n", .{ts.not_null_fields});
        std.debug.print("  numeric:        {d}\n", .{ts.numeric_fields});
        std.debug.print("  string:         {d}\n", .{ts.string_fields});
        std.debug.print("  datetime:       {d}\n", .{ts.datetime_fields});
        std.debug.print("  boolean:        {d}\n", .{ts.boolean_fields});
        std.debug.print("  other:          {d}\n", .{ts.other_fields});
        std.debug.print("  foreign_keys:   {d}\n", .{ts.foreign_keys});
        std.debug.print("  indexes:        {d}\n", .{ts.indexes});
        std.debug.print("  check_constraints: {d}\n", .{ts.check_constraints});
    }
}

/// Format per-table stats as JSON.
pub fn formatPerTableStatsJson(alloc: std.mem.Allocator, table_stats: []const TableStats) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 1024);
    try buf.appendSlice(alloc, "[");
    for (table_stats, 0..) |ts, i| {
        if (i > 0) try buf.appendSlice(alloc, ",");
        const entry = try std.fmt.allocPrint(alloc,
            \\{{"name":"{s}","fields":{d},"not_null":{d},"numeric":{d},"string":{d},"datetime":{d},"boolean":{d},"other":{d},"foreign_keys":{d},"indexes":{d},"check_constraints":{d}}}
        , .{
            ts.name,
            ts.fields,
            ts.not_null_fields,
            ts.numeric_fields,
            ts.string_fields,
            ts.datetime_fields,
            ts.boolean_fields,
            ts.other_fields,
            ts.foreign_keys,
            ts.indexes,
            ts.check_constraints,
        });
        try buf.appendSlice(alloc, entry);
    }
    try buf.appendSlice(alloc, "]");
    return try buf.toOwnedSlice(alloc);
}

/// Format per-table stats as a Markdown table.
pub fn formatPerTableStatsMarkdown(alloc: std.mem.Allocator, table_stats: []const TableStats) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 1024);
    try buf.appendSlice(alloc,
        \\## Per-Table Statistics
        \\
        \\| Table | Fields | Non-null | Numeric | String | Datetime | Boolean | Other | FKs | Indexes | Checks |
        \\|-------|--------|----------|---------|--------|----------|---------|-------|-----|---------|--------|
    );
    for (table_stats) |ts| {
        const row = try std.fmt.allocPrint(alloc,
            \\| {s} | {d} | {d} | {d} | {d} | {d} | {d} | {d} | {d} | {d} | {d} |
        , .{
            ts.name,
            ts.fields,
            ts.not_null_fields,
            ts.numeric_fields,
            ts.string_fields,
            ts.datetime_fields,
            ts.boolean_fields,
            ts.other_fields,
            ts.foreign_keys,
            ts.indexes,
            ts.check_constraints,
        });
        try buf.appendSlice(alloc, row);
    }
    return try buf.toOwnedSlice(alloc);
}
