const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const Writer = std.Io.Writer;

// ─── SQLAlchemy Generator ───────────────────────────────────────
// Maps Rune .ss schema to SQLAlchemy ORM models (Python).
// Output: Python with declarative_base, Column, relationship, Index.
//
// Architecture: TypedAst → Python string
//   Each table → class with __tablename__
//   Each column → Column() with type and modifiers
//   FK → ForeignKey('table.column') + relationship()
//   Index → Index('name', 'col')

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Generate imports
    try writeImports(w, typed);

    // Generate Base declaration
    try w.writeAll("Base = declarative_base()\n\n");

    // Generate model classes
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try writeModel(w, table);
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Import Generation ──────────────────────────────────────────

fn writeImports(w: *Writer, typed: typed_ast.TypedAst) !void {
    // Track which column types are needed
    var need_integer = false;
    var need_small_integer = false;
    var need_big_integer = false;
    var need_string = false;
    var need_text = false;
    var need_boolean = false;
    var need_date = false;
    var need_date_time = false;
    var need_numeric = false;
    var need_json = false;
    var need_large_binary = false;
    var need_enum = false;
    var need_index = false;
    var need_unique_constraint = false;
    var need_foreign_key = false;
    var need_relationship = false;

    for (typed.tables) |table| {
        for (table.columns) |col| {
            if (col.flags.is_enum) {
                need_enum = true;
            }
            switch (col.sql_type) {
                .int, .serial => need_integer = true,
                .smallint => need_small_integer = true,
                .bigint => need_big_integer = true,
                .decimal => need_numeric = true,
                .varchar => need_string = true,
                .text => need_text = true,
                .boolean => need_boolean = true,
                .datetime, .timestamptz => need_date_time = true,
                .date => need_date = true,
                .json, .jsonb => need_json = true,
                .blob => need_large_binary = true,
                .uuid => need_string = true,
                .inet => need_string = true,
                .enum_values => need_enum = true,
                .raw_sql, .passthrough => need_string = true,
            }
        }
        for (table.fks) |_| {
            need_foreign_key = true;
            need_relationship = true;
        }
        for (table.indexes) |idx| {
            if (idx.kind == .unique and idx.fields.len > 1) {
                need_unique_constraint = true;
            } else if (idx.kind == .regular or idx.kind == .unique) {
                need_index = true;
            }
        }
    }

    // Column types import
    try w.writeAll("from sqlalchemy import (");
    var first = true;
    const imports = [_]struct { flag: bool, name: []const u8 }{
        .{ .flag = need_integer, .name = "Integer" },
        .{ .flag = need_small_integer, .name = "SmallInteger" },
        .{ .flag = need_big_integer, .name = "BigInteger" },
        .{ .flag = need_string, .name = "String" },
        .{ .flag = need_text, .name = "Text" },
        .{ .flag = need_boolean, .name = "Boolean" },
        .{ .flag = need_date, .name = "Date" },
        .{ .flag = need_date_time, .name = "DateTime" },
        .{ .flag = need_numeric, .name = "Numeric" },
        .{ .flag = need_json, .name = "JSON" },
        .{ .flag = need_large_binary, .name = "LargeBinary" },
        .{ .flag = need_foreign_key, .name = "ForeignKey" },
        .{ .flag = need_index, .name = "Index" },
        .{ .flag = need_unique_constraint, .name = "UniqueConstraint" },
        .{ .flag = need_enum, .name = "Enum" },
    };
    for (imports) |imp| {
        if (imp.flag) {
            if (!first) try w.writeAll(", ");
            try w.writeAll(imp.name);
            first = false;
        }
    }
    try w.writeAll(")\n");
    try w.writeAll("from sqlalchemy.orm import declarative_base, relationship\n\n");
}

// ─── Model Generation ───────────────────────────────────────────

fn writeModel(w: *Writer, table: typed_ast.TypedTable) !void {
    // Comment
    if (table.comment) |comment| {
        if (comment.len > 0) {
            try w.print("# {s}\n", .{comment});
        }
    }

    try w.print("class {s}(Base):\n", .{table.name});
    try w.print("    __tablename__ = '{s}'\n\n", .{table.name});

    // Columns
    for (table.columns) |col| {
        try writeColumn(w, col, table);
    }

    // Composite indexes
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) continue;
        if (idx.fields.len > 1) {
            try w.print("    __table_args__ = (", .{});
            if (idx.kind == .unique) {
                try w.writeAll("UniqueConstraint(");
                for (idx.fields, 0..) |field, fi| {
                    if (fi > 0) try w.writeAll(", ");
                    try w.print("'{s}'", .{field});
                }
                try w.writeAll(")");
            } else {
                try w.print("Index('{s}'", .{idx.name});
                for (idx.fields) |field| {
                    try w.print(", '{s}'", .{field});
                }
                try w.writeAll(")");
            }
            try w.writeAll(",)\n");
        }
    }
}

// ─── Column Generation ──────────────────────────────────────────

fn writeColumn(w: *Writer, col: typed_ast.TypedColumn, table: typed_ast.TypedTable) !void {
    // Comment
    if (col.comment) |comment| {
        if (comment.len > 0) {
            try w.print("    # {s}\n", .{comment});
        }
    }

    // Check if this column is an FK — if so, skip it (handled by relationship)
    for (table.fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col.name)) {
            return; // FK column handled by relationship
        }
    }

    try w.print("    {s} = Column(", .{col.name});
    try writeColumnType(w, col);

    // Primary key
    if (col.flags.primary_key) {
        try w.writeAll(", primary_key=True");
        if (col.flags.auto_increment) {
            try w.writeAll(", autoincrement=True");
        }
    }

    // Not null
    if (!col.flags.nullable and !col.flags.primary_key) {
        try w.writeAll(", nullable=False");
    }

    // Unique
    if (col.flags.inline_unique and !col.flags.primary_key) {
        try w.writeAll(", unique=True");
    }

    // Default value
    if (col.default) |dflt| {
        if (dflt.len > 0 and !std.mem.eql(u8, dflt, "null")) {
            try w.writeAll(", server_default=");
            try writeDefault(w, col, dflt);
        }
    }

    // Index
    if (col.flags.inline_index) {
        try w.writeAll(", index=True");
    }

    try w.writeAll(")\n");
}

fn writeColumnType(w: *Writer, col: typed_ast.TypedColumn) !void {
    if (col.flags.is_enum) {
        try w.writeAll("Enum(");
        for (col.enum_values, 0..) |val, vi| {
            if (vi > 0) try w.writeAll(", ");
            try w.print("'{s}'", .{val});
        }
        try w.writeAll(")");
        return;
    }
    switch (col.sql_type) {
        .int, .serial => try w.writeAll("Integer"),
        .smallint => try w.writeAll("SmallInteger"),
        .bigint => try w.writeAll("BigInteger"),
        .decimal => |ds| try w.print("Numeric(precision={d}, scale={d})", .{ ds.precision, ds.scale }),
        .varchar => |n| {
            if (n > 0) {
                try w.print("String({d})", .{n});
            } else {
                try w.writeAll("String(255)");
            }
        },
        .text => try w.writeAll("Text"),
        .blob => try w.writeAll("LargeBinary"),
        .json, .jsonb => try w.writeAll("JSON"),
        .datetime, .timestamptz => try w.writeAll("DateTime"),
        .date => try w.writeAll("Date"),
        .boolean => try w.writeAll("Boolean"),
        .uuid => try w.writeAll("String(36)"),
        .inet => try w.writeAll("String(45)"),
        .enum_values => |vals| {
            try w.writeAll("Enum(");
            for (vals, 0..) |val, vi| {
                if (vi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{val});
            }
            try w.writeAll(")");
        },
        .raw_sql, .passthrough => try w.writeAll("String"),
    }
}

fn writeDefault(w: *Writer, col: typed_ast.TypedColumn, dflt: []const u8) !void {
    _ = col;

    if (std.mem.eql(u8, dflt, "true") or std.mem.eql(u8, dflt, "TRUE")) {
        try w.writeAll("'true'");
        return;
    }
    if (std.mem.eql(u8, dflt, "false") or std.mem.eql(u8, dflt, "FALSE")) {
        try w.writeAll("'false'");
        return;
    }
    if (std.mem.eql(u8, dflt, "null") or std.mem.eql(u8, dflt, "NULL")) {
        try w.writeAll("None");
        return;
    }
    if (std.mem.eql(u8, dflt, "NOW()") or std.mem.eql(u8, dflt, "now()") or
        std.mem.eql(u8, dflt, "CURRENT_TIMESTAMP"))
    {
        try w.writeAll("'now()'");
        return;
    }

    if (std.fmt.parseInt(i64, dflt, 10)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}

    if (std.fmt.parseFloat(f64, dflt)) |num| {
        try w.print("{d}", .{num});
        return;
    } else |_| {}

    const trimmed = std.mem.trim(u8, dflt, "'");
    try w.print("'{s}'", .{trimmed});
}
