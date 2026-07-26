const std = @import("std");
const diag = @import("../semantic/diagnostic.zig");
const sql_parser = @import("../parser/sql_parser.zig");
const reverse_codegen = @import("../reverse/codegen.zig");
const dialect_detect = @import("../reverse/dialect_detect.zig");
const codegen = @import("../codegen/codegen.zig");
const io_mod = @import("../io.zig");

// ─── Reverse Pipeline: SQL → .ss ─────────────────────────────

pub fn handleReverse(io: std.Io, alloc: std.mem.Allocator, file_data: []const u8, input_name: []const u8, output_path: ?[]const u8, with_templates: bool, dialect: codegen.Dialect, trace: bool) !void {
    // Auto-detect dialect from SQL content when not explicitly specified
    const sql_dialect: sql_parser.Dialect = if (dialect == .mysql) dialect_detect.detectSqlDialect(file_data) else dialect;

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
            .file = input_name,
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
            .file = input_name,
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

    if (trace) {
        traceSqlSchema(schema);
    }

    var rcg = reverse_codegen.ReverseCodegen.init(alloc, sql_dialect);
    const ss_text = if (with_templates)
        try rcg.generateWithTemplates(schema)
    else
        try rcg.generate(schema);

    try io_mod.writeOutput(io, ss_text, output_path, false);
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
