const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const codegen_mod = @import("codegen.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const Writer = std.Io.Writer;

pub fn isDominatedByExplicitIndex(col_name: []const u8, explicit_indexes: []const ast_mod.IndexDecl, require_unique: bool) bool {
    for (explicit_indexes) |idx| {
        if (require_unique and idx.kind != .unique and idx.kind != .primary_key) continue;
        for (idx.fields) |f| {
            if (std.mem.eql(u8, f, col_name)) return true;
        }
    }
    return false;
}

pub fn emitDefault(w: *Writer, value: []const u8) !void {
    const is_num_val = blk: {
        _ = std.fmt.parseFloat(f64, value) catch break :blk false;
        break :blk true;
    };
    // Case-insensitive: schemas write `=null`/`=false` in the case the spec
    // examples use, and a quoted 'false' on a boolean column changes
    // semantics (string comparison, never true).
    const is_sql_keyword = std.ascii.eqlIgnoreCase(value, "CURRENT_TIMESTAMP") or
        std.ascii.eqlIgnoreCase(value, "NULL") or
        std.ascii.eqlIgnoreCase(value, "NOW()") or
        std.ascii.eqlIgnoreCase(value, "TRUE") or
        std.ascii.eqlIgnoreCase(value, "FALSE");
    if (is_num_val or is_sql_keyword) {
        try w.print(" DEFAULT {s}", .{value});
    } else if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
        // Quoted literal `='x'` — strip the outer quotes; SQL re-quotes below
        // (same convention as the CHECK in-list path). Without this the
        // quotes double: DEFAULT ''x''.
        try w.print(" DEFAULT '{s}'", .{value[1 .. value.len - 1]});
    } else {
        try w.print(" DEFAULT '{s}'", .{value});
    }
}

pub fn emitColumnDef(backend: *const dialect_mod.DialectBackend, w: *Writer, col: typed_ast_mod.TypedColumn) !void {
    return emitColumnDefEx(backend, w, col, false);
}

pub fn emitColumnDefEx(backend: *const dialect_mod.DialectBackend, w: *Writer, col: typed_ast_mod.TypedColumn, skip_name: bool) !void {
    if (!skip_name) {
        try backend.quoteIdent(w, col.name);
        try w.writeAll(" ");
    }
    try backend.renderType(w, col.sql_type);

    if (col.flags.unsigned) {
        try backend.emitUnsigned(w);
    }

    if (!col.flags.nullable) try w.writeAll(" NOT NULL");

    if (col.flags.auto_increment) {
        try backend.emitAutoIncrement(w);
    }

    if (col.flags.has_timestamp_default) {
        try backend.emitTimestampModifier(w, col.flags.on_update_current_timestamp);
    }

    if (col.flags.primary_key) {
        try backend.emitPrimaryKey(w, col.flags.auto_increment);
    }

    if (col.default) |dv| try emitDefault(w, dv);
    if (col.check) |ck| {
        try w.writeAll(" CHECK (");
        try emitCheckExpr(w, col.name, ck);
        try w.writeAll(")");
    }
    if (col.comment) |c| {
        try backend.emitInlineColumnComment(w, c);
    }
    if (col.flags.is_enum) {
        try backend.emitEnumTypeCheck(w, col.name, col.enum_values);
    }
    // Generated columns: type + GENERATED ALWAYS AS (expr) VIRTUAL/STORED
    if (col.generated_expr) |expr| {
        try w.writeAll(" ");
        try backend.emitGeneratedColumn(w, expr, col.flags.is_stored);
    }
}

/// Render a CHECK constraint expression from a field name and CheckConstraint.
/// Handles range, in_list, and comparison expressions.
pub fn emitCheckExpr(w: *Writer, field_name: []const u8, ck: ast_mod.CheckConstraint) !void {
    switch (ck.kind) {
        .range => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} BETWEEN {s} AND {s}", .{ field_name, low, high });
        },
        .range_upper_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} >= {s} AND {s} < {s}", .{ field_name, low, field_name, high });
        },
        .range_lower_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} > {s} AND {s} <= {s}", .{ field_name, low, field_name, high });
        },
        .range_both_exclusive => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            const low = std.mem.trim(u8, parts.next() orelse "", " ");
            const high = std.mem.trim(u8, parts.next() orelse "", " ");
            try w.print("{s} > {s} AND {s} < {s}", .{ field_name, low, field_name, high });
        },
        .in_list => {
            try w.print("{s} IN (", .{field_name});
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            var first = true;
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len == 0) continue;
                if (!first) try w.writeAll(", ");
                first = false;
                const is_num = blk: {
                    _ = std.fmt.parseFloat(f64, trimmed) catch break :blk false;
                    break :blk true;
                };
                if (is_num) {
                    try w.print("{s}", .{trimmed});
                } else {
                    const val = if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'')
                        trimmed[1 .. trimmed.len - 1]
                    else
                        trimmed;
                    try w.print("'{s}'", .{val});
                }
            }
            try w.writeAll(")");
        },
        .comparison => {
            var parts = std.mem.splitScalar(u8, ck.expr, ',');
            var first = true;
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len == 0) continue;
                if (!first) try w.writeAll(" AND ");
                first = false;
                if (trimmed[0] == '>' and trimmed.len > 1 and trimmed[1] == '=') {
                    try w.print("{s} >= {s}", .{ field_name, trimmed[2..] });
                } else if (trimmed[0] == '<' and trimmed.len > 1 and trimmed[1] == '=') {
                    try w.print("{s} <= {s}", .{ field_name, trimmed[2..] });
                } else if (trimmed[0] == '>') {
                    try w.print("{s} > {s}", .{ field_name, trimmed[1..] });
                } else if (trimmed[0] == '<') {
                    try w.print("{s} < {s}", .{ field_name, trimmed[1..] });
                } else if (trimmed[0] == '=') {
                    try w.print("{s} = {s}", .{ field_name, trimmed[1..] });
                } else {
                    try w.print("{s} = {s}", .{ field_name, trimmed });
                }
            }
        },
    }
}
