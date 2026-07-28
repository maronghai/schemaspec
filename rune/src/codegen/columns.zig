const std = @import("std");
const ast_mod = @import("../types/ast.zig");
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
    const is_sql_keyword = std.mem.eql(u8, value, "CURRENT_TIMESTAMP") or
        std.mem.eql(u8, value, "NULL") or
        std.mem.eql(u8, value, "NOW()");
    if (is_num_val or is_sql_keyword) {
        try w.print(" DEFAULT {s}", .{value});
    } else {
        try w.print(" DEFAULT '{s}'", .{value});
    }
}

pub fn emitColumnDef(backend: dialect_mod.DialectBackend, w: *Writer, col: typed_ast_mod.TypedColumn) !void {
    return emitColumnDefEx(backend, w, col, false);
}

pub fn emitColumnDefEx(backend: dialect_mod.DialectBackend, w: *Writer, col: typed_ast_mod.TypedColumn, skip_name: bool) !void {
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
        try dialect_mod.emitCheckExpr(w, col.name, ck);
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
