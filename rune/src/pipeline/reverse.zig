const std = @import("std");
const diag = @import("../semantic/diagnostic.zig");
const sql_parser = @import("../parser/sql_parser.zig");
const reverse_codegen = @import("../reverse/codegen.zig");
const dialect_detect = @import("../reverse/dialect_detect.zig");
const codegen = @import("../codegen/codegen.zig");
const io_mod = @import("../io.zig");
const cli = @import("../cli.zig");

// ─── Reverse Pipeline: SQL → .ss ─────────────────────────────

/// Configuration for `rune reverse` — replaces 11 positional parameters.
pub const ReverseConfig = struct {
    input_name: []const u8 = "<stdin>",
    output_path: ?[]const u8 = null,
    dialect: codegen.Dialect = .mysql,
    format: cli.DiffFormat = .text,
    with_templates: bool = false,
    trace: bool = false,
    stats: bool = false,
    validate_only: bool = false,
};

/// Handle the `rune reverse` command: parse SQL DDL and generate .ss schema output.
pub fn handleReverse(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, cfg: ReverseConfig) !void {
    // Auto-detect dialect from SQL content when not explicitly specified
    const sql_dialect: sql_parser.Dialect = if (cfg.dialect == .mysql) dialect_detect.detectSqlDialect(file_data) else cfg.dialect;

    // Use DiagnosticCollector for consistent error handling with forward pipeline
    var diagnostics = try diag.DiagnosticCollector.init(alloc);

    var sp_parser = try sql_parser.SqlParser.init(alloc, file_data, sql_dialect);
    const result = sp_parser.parse() catch |err| {
        const lc = sp_parser.lineColAt(sp_parser.pos);
        const src_line = sp_parser.getSourceLine(lc.line);
        diagnostics.record(.{
            .severity = .@"error",
            .line_no = lc.line,
            .col = lc.col,
            .file = cfg.input_name,
            .message = "SQL syntax error",
            .source_line = src_line,
            .actual = @errorName(err),
        });
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.SqlParseError;
    };
    const schema = result.schema;

    for (result.diagnostics) |d| {
        diagnostics.record(.{
            .severity = d.severity,
            .line_no = d.line_no,
            .col = d.col,
            .file = cfg.input_name,
            .message = d.message,
            .source_line = d.source_line,
        });
    }

    if (diagnostics.hasErrors()) {
        diagnostics.printAll();
        diagnostics.printSummary();
        return error.ReverseDiagnosticsError;
    }

    if (schema.tables.len == 0) {
        std.debug.print("warning: no tables found in SQL input\n", .{});
    }

    if (cfg.trace) {
        traceSqlSchema(schema);
    }

    if (cfg.stats) {
        var col_count: usize = 0;
        for (schema.tables) |table| {
            col_count += table.columns.len;
        }
        std.debug.print("tables: {d}  columns: {d}\n", .{ schema.tables.len, col_count });
    }

    if (cfg.validate_only) {
        std.debug.print("SQL is valid\n", .{});
        return;
    }

    switch (cfg.format) {
        .json => {
            const json_text = try generateReverseJson(alloc, schema);
            try io_mod.writeOutput(io, json_text, cfg.output_path, false);
        },
        else => {
            var rcg = reverse_codegen.ReverseCodegen.init(alloc, sql_dialect);
            const ss_text = if (cfg.with_templates)
                try rcg.generateWithTemplates(schema)
            else
                try rcg.generate(schema);

            try io_mod.writeOutput(io, ss_text, cfg.output_path, false);
        },
    }
}

// ─── Reverse JSON Output ──────────────────────────────────────

fn generateReverseJson(alloc: std.mem.Allocator, schema: sql_parser.SqlSchema) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("{\n");
    if (schema.name) |name| {
        try w.print("  \"schema\": \"{s}\",\n", .{name});
    }
    try w.print("  \"tables\": [\n", .{});

    for (schema.tables, 0..) |table, ti| {
        try w.writeAll("    {\n");
        try w.print("      \"name\": \"{s}\",\n", .{table.name});
        if (table.comment) |c| {
            try w.print("      \"comment\": \"{s}\",\n", .{c});
        }
        // Columns
        try w.writeAll("      \"columns\": [\n");
        for (table.columns, 0..) |col, ci| {
            try w.writeAll("        {\n");
            try w.print("          \"name\": \"{s}\",\n", .{col.name});
            try w.print("          \"type\": \"{s}\",\n", .{col.type_sql});
            if (col.primary_key) try w.writeAll("          \"primary_key\": true,\n");
            if (col.auto_increment) try w.writeAll("          \"auto_increment\": true,\n");
            if (col.nullable) try w.writeAll("          \"nullable\": true,\n");
            if (col.default_val) |dv| {
                try w.print("          \"default\": \"{s}\",\n", .{dv});
            }
            // Remove trailing comma from last property
            try w.writeAll("          \"_end\": true\n");
            try w.writeAll("        }");
            if (ci < table.columns.len - 1) try w.writeAll(",");
            try w.writeAll("\n");
        }
        try w.writeAll("      ],\n");
        // Indexes
        if (table.indexes.len > 0) {
            try w.writeAll("      \"indexes\": [\n");
            for (table.indexes, 0..) |idx, ii| {
                try w.writeAll("        {\n");
                try w.print("          \"name\": \"{s}\",\n", .{idx.name});
                try w.print("          \"kind\": \"{s}\",\n", .{@tagName(idx.kind)});
                try w.writeAll("          \"fields\": [");
                for (idx.fields, 0..) |f, fi| {
                    if (fi > 0) try w.writeAll(", ");
                    try w.print("\"{s}\"", .{f});
                }
                try w.writeAll("]\n");
                try w.writeAll("        }");
                if (ii < table.indexes.len - 1) try w.writeAll(",");
                try w.writeAll("\n");
            }
            try w.writeAll("      ],\n");
        }
        // Foreign keys
        if (table.foreign_keys.len > 0) {
            try w.writeAll("      \"foreign_keys\": [\n");
            for (table.foreign_keys, 0..) |fk, fi| {
                try w.writeAll("        {\n");
                try w.writeAll("          \"fields\": [");
                for (fk.fields, 0..) |f, ffi| {
                    if (ffi > 0) try w.writeAll(", ");
                    try w.print("\"{s}\"", .{f});
                }
                try w.writeAll("],\n");
                try w.print("          \"ref_table\": \"{s}\",\n", .{fk.ref_table});
                try w.writeAll("          \"ref_fields\": [");
                for (fk.ref_fields, 0..) |f, rfi| {
                    if (rfi > 0) try w.writeAll(", ");
                    try w.print("\"{s}\"", .{f});
                }
                try w.writeAll("]\n");
                try w.writeAll("        }");
                if (fi < table.foreign_keys.len - 1) try w.writeAll(",");
                try w.writeAll("\n");
            }
            try w.writeAll("      ]\n");
        } else {
            try w.writeAll("      \"_end\": true\n");
        }
        try w.writeAll("    }");
        if (ti < schema.tables.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }
    try w.writeAll("  ]\n");
    try w.writeAll("}\n");

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Trace Helper ──────────────────────────────────────────────

fn traceSqlSchema(schema: sql_parser.SqlSchema) void {
    std.debug.print("=== [Reverse: SqlSchema] ===\n\n", .{});
    std.debug.print("Schema: {?s}\n", .{schema.name});
    std.debug.print("Tables ({d}):\n", .{schema.tables.len});
    for (schema.tables) |table| {
        std.debug.print("  # {s} ({d} columns, {d} indexes, {d} fks)\n", .{ table.name, table.columns.len, table.indexes.len, table.foreign_keys.len });
        for (table.columns) |col| {
            std.debug.print("    {s: <24} {s}", .{ col.name, col.type_sql });
            if (col.primary_key) std.debug.print(" PK", .{});
            if (col.auto_increment) std.debug.print(" AI", .{});
            if (col.nullable) std.debug.print(" NULL", .{});
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n", .{});
}
