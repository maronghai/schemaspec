const std = @import("std");
const pass_manager = @import("../pass_manager.zig");
const PassContext = pass_manager.PassContext;

// ─── Validate Views ──────────────────────────────────────────
// Semantic pass that validates view definitions:
// 1. No duplicate view names
// 2. View queries reference tables that exist in the schema

pub fn run(ctx: *PassContext) !void {
    // Collect table names for reference checking
    var table_names = std.StringHashMap(void).init(ctx.alloc);
    defer table_names.deinit();
    for (ctx.tables.items) |table| {
        try table_names.put(table.name, {});
    }

    // Check for duplicate view names and validate references
    var seen_views = std.StringHashMap(void).init(ctx.alloc);
    defer seen_views.deinit();

    for (ctx.views) |view| {
        // Check for duplicate view names
        if (seen_views.contains(view.name)) {
            ctx.diagnostics.record(.{
                .severity = .@"error",
                .line_no = view.line_no,
                .col = 0,
                .message = "duplicate view name",
                .actual = view.name,
            });
            continue;
        }
        try seen_views.put(view.name, {});

        // Check that view query references existing tables (basic heuristic)
        // Look for FROM <table> and JOIN <table> patterns
        if (view.query.len > 0) {
            try checkQueryReferences(ctx, &table_names, view.query, view.name, view.line_no);
        }
    }
}

/// Check that table references in a view query exist in the schema.
/// Uses a simple heuristic: looks for FROM <word> and JOIN <word> patterns.
fn checkQueryReferences(
    ctx: *PassContext,
    table_names: *const std.StringHashMap(void),
    query: []const u8,
    view_name: []const u8,
    line_no: usize,
) !void {
    var upper_query = try ctx.alloc.alloc(u8, query.len);
    defer ctx.alloc.free(upper_query);
    for (query, 0..) |c, i| {
        upper_query[i] = std.ascii.toUpper(c);
    }

    // Simple state machine to find table references after FROM/JOIN keywords
    var i: usize = 0;
    while (i < upper_query.len) {
        // Look for FROM keyword
        if (i + 4 < upper_query.len and std.mem.eql(u8, upper_query[i .. i + 4], "FROM")) {
            i += 4;
            // Skip whitespace
            while (i < upper_query.len and upper_query[i] == ' ') : (i += 1) {}
            // Extract table name (until space, comma, newline, or end)
            const start = i;
            while (i < upper_query.len and upper_query[i] != ' ' and upper_query[i] != ',' and upper_query[i] != '\n') : (i += 1) {}
            if (i > start) {
                const table_ref = query[start..i];
                // Skip subquery markers and quoted identifiers
                if (table_ref[0] != '(' and table_ref[0] != '"' and table_ref[0] != '`' and table_ref[0] != '\'') {
                    if (!table_names.contains(table_ref)) {
                        const msg = try std.fmt.allocPrint(ctx.alloc, "view '{s}' references unknown table '{s}'", .{ view_name, table_ref });
                        ctx.diagnostics.record(.{
                            .severity = .warning,
                            .line_no = line_no,
                            .col = 0,
                            .message = msg,
                        });
                    }
                }
            }
            continue;
        }

        // Look for JOIN keyword
        if (i + 4 < upper_query.len and std.mem.eql(u8, upper_query[i .. i + 4], "JOIN")) {
            i += 4;
            // Skip whitespace
            while (i < upper_query.len and upper_query[i] == ' ') : (i += 1) {}
            // Extract table name
            const start = i;
            while (i < upper_query.len and upper_query[i] != ' ' and upper_query[i] != ',' and upper_query[i] != '\n') : (i += 1) {}
            if (i > start) {
                const table_ref = query[start..i];
                if (table_ref[0] != '(' and table_ref[0] != '"' and table_ref[0] != '`' and table_ref[0] != '\'') {
                    if (!table_names.contains(table_ref)) {
                        const msg = try std.fmt.allocPrint(ctx.alloc, "view '{s}' references unknown table '{s}'", .{ view_name, table_ref });
                        ctx.diagnostics.record(.{
                            .severity = .warning,
                            .line_no = line_no,
                            .col = 0,
                            .message = msg,
                        });
                    }
                }
            }
            continue;
        }

        i += 1;
    }
}
