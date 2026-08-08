const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const ast_mod = @import("../types/ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const Writer = std.Io.Writer;
const common = @import("common.zig");

// ─── TypeORM Generator ─────────────────────────────────────────
// Maps Rune .ss schema to TypeORM entity classes (TypeScript).
// Output: TypeScript with @Entity, @Column, @PrimaryGeneratedColumn,
//         @ManyToOne, @JoinColumn, @Index decorators.
//
// Architecture: TypedAst → TypeScript string
//   Each table → @Entity class
//   Each column → @Column decorator with type options
//   FK → @ManyToOne + @JoinColumn
//   Index → @Index decorator
//   Enum → @Column({ type: 'enum', enum: [...] })

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, _: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Generate imports
    try writeImports(w, typed);

    // Generate entity classes
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try writeEntity(w, table);
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Import Generation ──────────────────────────────────────────

fn writeImports(w: *Writer, typed: typed_ast.TypedAst) !void {
    // Track which decorators are needed
    const need_entity = true; // always needed
    var need_primary_generated = false;
    var need_column = false;
    var need_many_to_one = false;
    var need_join_column = false;
    var need_index = false;
    var need_create_date_column = false;
    var need_update_date_column = false;

    for (typed.tables) |table| {
        for (table.columns) |col| {
            if (col.flags.primary_key and col.flags.auto_increment) {
                need_primary_generated = true;
            } else {
                need_column = true;
            }
            if (col.flags.has_timestamp_default and col.flags.is_datetime) {
                if (col.flags.on_update_current_timestamp) {
                    need_update_date_column = true;
                } else {
                    need_create_date_column = true;
                }
            }
        }
        for (table.fks) |fk| {
            _ = fk;
            need_many_to_one = true;
            need_join_column = true;
        }
        for (table.indexes) |idx| {
            if (idx.kind != .primary_key) {
                need_index = true;
            }
        }
    }

    try w.writeAll("import {");

    var first = true;
    if (need_entity) {
        try w.writeAll(" Entity");
        first = false;
    }
    if (need_primary_generated) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" PrimaryGeneratedColumn");
        first = false;
    }
    if (need_column) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" Column");
        first = false;
    }
    if (need_many_to_one) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" ManyToOne");
        first = false;
    }
    if (need_join_column) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" JoinColumn");
        first = false;
    }
    if (need_index) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" Index");
        first = false;
    }
    if (need_create_date_column) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" CreateDateColumn");
        first = false;
    }
    if (need_update_date_column) {
        if (!first) try w.writeAll(",");
        try w.writeAll(" UpdateDateColumn");
        first = false;
    }

    try w.writeAll(" } from 'typeorm';\n\n");
}

// ─── Entity Generation ──────────────────────────────────────────

fn writeEntity(w: *Writer, table: typed_ast.TypedTable) !void {
    // Index decorators on the class
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) continue;
        if (idx.fields.len == 1) {
            try w.print("@Index('{s}', {s})\n", .{ idx.name, idx.fields[0] });
        } else {
            try w.print("@Index('{s}', [", .{idx.name});
            for (idx.fields, 0..) |field, fi| {
                if (fi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{field});
            }
            try w.writeAll("])\n");
        }
    }

    try w.print("@Entity('{s}')\n", .{table.name});

    // Comment
    if (table.comment) |comment| {
        if (comment.len > 0) {
            try w.print("// {s}\n", .{comment});
        }
    }

    try w.print("export class {s} {{\n", .{table.name});

    // Columns
    for (table.columns) |col| {
        try writeColumn(w, col, table);
    }

    try w.writeAll("}\n");
}

// ─── Column Generation ──────────────────────────────────────────

fn writeColumn(w: *Writer, col: typed_ast.TypedColumn, table: typed_ast.TypedTable) !void {
    // Comment
    if (col.comment) |comment| {
        if (comment.len > 0) {
            try w.print("  // {s}\n", .{comment});
        }
    }

    // Check if this column is an FK — emit @ManyToOne + @JoinColumn
    for (table.fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col.name)) {
            try w.print("  @ManyToOne(() => {s})\n", .{fk.ref_table});
            try w.print("  @JoinColumn({{ name: '{s}' }})\n", .{col.name});
            try w.print("  {s}: {s};\n\n", .{ col.name, fk.ref_table });
            return;
        }
    }

    // PrimaryGeneratedColumn
    if (col.flags.primary_key and col.flags.auto_increment) {
        try w.writeAll("  @PrimaryGeneratedColumn()\n");
        try w.print("  {s}: number;\n\n", .{col.name});
        return;
    }

    // CreateDateColumn / UpdateDateColumn
    if (col.flags.has_timestamp_default and col.flags.is_datetime) {
        if (col.flags.on_update_current_timestamp) {
            try w.writeAll("  @UpdateDateColumn()\n");
            try w.print("  {s}: Date;\n\n", .{col.name});
            return;
        } else {
            try w.writeAll("  @CreateDateColumn()\n");
            try w.print("  {s}: Date;\n\n", .{col.name});
            return;
        }
    }

    // Regular @Column
    try w.writeAll("  @Column({ ");
    try writeColumnType(w, col);
    if (col.flags.nullable) {
        try w.writeAll(", nullable: true");
    }
    if (col.default) |dflt| {
        if (common.shouldEmitDefault(dflt)) {
            try w.writeAll(", default: ");
            try common.writeFormattedDefault(w, dflt, common.getOrmFormatter(.typeorm));
        }
    }
    try w.writeAll(" })\n");

    // TypeScript type
    try w.print("  {s}: {s};\n\n", .{ col.name, tsType(col) });
}

fn writeColumnType(w: *Writer, col: typed_ast.TypedColumn) !void {
    if (col.flags.is_enum) {
        try w.writeAll("type: 'enum', enum: [");
        for (col.enum_values, 0..) |val, vi| {
            if (vi > 0) try w.writeAll(", ");
            try w.print("'{s}'", .{val});
        }
        try w.writeAll("]");
        return;
    }
    switch (col.sql_type) {
        .int, .smallint, .serial => try w.writeAll("type: 'int'"),
        .bigint => try w.writeAll("type: 'bigint'"),
        .decimal => |ds| try w.print("type: 'decimal', precision: {d}, scale: {d}", .{ ds.precision, ds.scale }),
        .varchar => |n| {
            if (n > 0) {
                try w.print("type: 'varchar', length: {d}", .{n});
            } else {
                try w.writeAll("type: 'text'");
            }
        },
        .text => try w.writeAll("type: 'text'"),
        .blob => try w.writeAll("type: 'blob'"),
        .json, .jsonb => try w.writeAll("type: 'json'"),
        .datetime, .timestamptz => try w.writeAll("type: 'datetime'"),
        .date => try w.writeAll("type: 'date'"),
        .boolean => try w.writeAll("type: 'boolean'"),
        .uuid => try w.writeAll("type: 'uuid'"),
        .inet => try w.writeAll("type: 'varchar', length: 45"),
        .enum_values => |vals| {
            try w.writeAll("type: 'enum', enum: [");
            for (vals, 0..) |val, vi| {
                if (vi > 0) try w.writeAll(", ");
                try w.print("'{s}'", .{val});
            }
            try w.writeAll("]");
        },
        .raw_sql, .passthrough => try w.writeAll("type: 'varchar'"),
    }
}

fn tsType(col: typed_ast.TypedColumn) []const u8 {
    if (col.flags.is_enum) {
        return "string";
    }
    if (col.flags.nullable) {
        return switch (col.sql_type) {
            .int, .smallint, .serial, .bigint => "number | null",
            .decimal => "number | null",
            .varchar, .text, .inet, .enum_values, .raw_sql, .passthrough => "string | null",
            .boolean => "boolean | null",
            .datetime, .timestamptz, .date => "Date | null",
            .json, .jsonb => "object | null",
            .blob, .uuid => "string | null",
        };
    }
    return switch (col.sql_type) {
        .int, .smallint, .serial, .bigint => "number",
        .decimal => "number",
        .varchar, .text, .inet, .enum_values, .raw_sql, .passthrough => "string",
        .boolean => "boolean",
        .datetime, .timestamptz, .date => "Date",
        .json, .jsonb => "object",
        .blob, .uuid => "string",
    };
}

// ─── Helpers ────────────────────────────────────────────────────
