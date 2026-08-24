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

// ─── Drizzle ORM Generator ─────────────────────────────────────
// Maps Rune .ss schema to Drizzle ORM TypeScript schema.
// Output: TypeScript with pgTable/mysqlTable/sqliteTable definitions.
//
// Architecture: TypedAst → TypeScript string
//   Each table → export const table = <dialect>Table(...)
//   Each column → column constructor with modifiers
//   Single-column FK → .references(() => table.column)
//   Multi-column FK → foreignKey() in table callback

fn drizzleTableFn(dialect: Dialect) []const u8 {
    return switch (dialect) {
        .mysql => "mysqlTable",
        .pg => "pgTable",
        .sqlite => "sqliteTable",
        .mssql => "mssqlTable",
        .oracle => "pgTable", // Drizzle Oracle uses pg-core driver
        .db2 => "pgTable", // Drizzle Db2 uses pg-core driver
    };
}

fn drizzleModuleName(dialect: Dialect) []const u8 {
    return switch (dialect) {
        .mysql => "mysql-core",
        .pg => "pg-core",
        .sqlite => "sqlite-core",
        .mssql => "mssql-core",
        .oracle => "pg-core", // Drizzle Oracle uses pg-core driver
        .db2 => "pg-core", // Drizzle Db2 uses pg-core driver
    };
}
//   Index → index()/uniqueIndex() in table callback
//   Enum → pgEnum() (PG) or const array (MySQL/SQLite)

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, dialect: Dialect) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    // Generate import statement
    const has_enums = common.hasAnyEnums(typed);
    try writeImports(w, typed, dialect, has_enums);

    // Generate enum definitions
    if (has_enums) {
        for (typed.tables) |table| {
            for (table.columns) |col| {
                if (col.flags.is_enum) {
                    try writeEnumDef(w, col, dialect);
                }
            }
        }
        try w.writeAll("\n");
    }

    // Generate table definitions
    for (typed.tables, 0..) |table, ti| {
        if (ti > 0) try w.writeAll("\n");
        try writeTable(w, table, dialect);
    }

    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Import Generation ──────────────────────────────────────────

fn writeImports(w: *Writer, typed: typed_ast.TypedAst, dialect: Dialect, has_enums: bool) !void {
    // Determine which column constructors are needed
    var need_serial = false;
    var need_integer = false;
    var need_smallint = false;
    var need_bigint = false;
    var need_varchar = false;
    var need_text = false;
    var need_boolean = false;
    var need_timestamp = false;
    var need_date = false;
    var need_json = false;
    var need_jsonb = false;
    var need_uuid = false;
    var need_decimal = false;
    var need_blob = false;

    for (typed.tables) |table| {
        for (table.columns) |col| {
            switch (col.sql_type) {
                .int => need_integer = true,
                .smallint => need_smallint = true,
                .bigint => need_bigint = true,
                .serial => need_serial = true,
                .decimal => need_decimal = true,
                .varchar => need_varchar = true,
                .text => need_text = true,
                .blob => need_blob = true,
                .json => need_json = true,
                .jsonb => need_jsonb = true,
                .datetime, .timestamptz => need_timestamp = true,
                .date => need_date = true,
                .boolean => need_boolean = true,
                .uuid => need_uuid = true,
                .inet => {}, // no direct Drizzle inet — use text
                .enum_values => {}, // handled by enum definitions
                .raw_sql, .passthrough => need_text = true,
            }
        }
    }

    const table_fn = drizzleTableFn(dialect);

    const mod_name = drizzleModuleName(dialect);

    try w.print("import {{ {s}", .{table_fn});

    const column_imports = [_]struct { flag: bool, name: []const u8 }{
        .{ .flag = need_serial, .name = "serial" },
        .{ .flag = need_integer, .name = "integer" },
        .{ .flag = need_smallint, .name = "smallint" },
        .{ .flag = need_bigint, .name = "bigint" },
        .{ .flag = need_varchar, .name = "varchar" },
        .{ .flag = need_text, .name = "text" },
        .{ .flag = need_boolean, .name = "boolean" },
        .{ .flag = need_timestamp, .name = "timestamp" },
        .{ .flag = need_date, .name = "date" },
        .{ .flag = need_json, .name = "json" },
        .{ .flag = need_jsonb, .name = "jsonb" },
        .{ .flag = need_uuid, .name = "uuid" },
        .{ .flag = need_decimal, .name = "decimal" },
        .{ .flag = need_blob, .name = "blob" },
    };

    for (column_imports) |ci| {
        if (ci.flag) {
            try w.print(", {s}", .{ci.name});
        }
    }

    // Add index imports if needed
    var need_index = false;
    var need_unique_index = false;
    for (typed.tables) |table| {
        for (table.indexes) |idx| {
            if (idx.kind == .unique) {
                need_unique_index = true;
            } else if (idx.kind == .regular) {
                need_index = true;
            }
        }
    }

    if (need_index) try w.writeAll(", index");
    if (need_unique_index) try w.writeAll(", uniqueIndex");

    // Add pgEnum import for PG enums
    if (has_enums and dialect == .pg) {
        try w.writeAll(", pgEnum");
    }

    try w.print(" }} from 'drizzle-orm/{s}';\n", .{mod_name});

    // Add foreignKey import if any table has composite FKs
    if (common.hasAnyCompositeFks(typed)) {
        try w.print("import {{ foreignKey }} from 'drizzle-orm/{s}';\n", .{mod_name});
    }

    try w.writeAll("\n");
}

// ─── Enum Generation ────────────────────────────────────────────

fn writeEnumDef(w: *Writer, col: typed_ast.TypedColumn, dialect: Dialect) !void {
    if (dialect == .pg) {
        try w.print("export const {s}Enum = pgEnum('{s}_type', [", .{ col.name, col.name });
        try common.writeEnumValues(w, col.enum_values);
        try w.writeAll("]);\n");
    } else {
        try w.print("export const {s}Values = [", .{col.name});
        try common.writeEnumValues(w, col.enum_values);
        try w.writeAll("] as const;\n");
        try w.print("export type {s}Type = (typeof {s}Values)[number];\n", .{ col.name, col.name });
    }
}

// ─── Table Generation ───────────────────────────────────────────

fn writeTable(w: *Writer, table: typed_ast.TypedTable, dialect: Dialect) !void {
    const table_fn = drizzleTableFn(dialect);

    // Comment BEFORE the table declaration — inside the object literal only
    // `//`-style comments are legal, and a comment belongs above its target.
    try common.writeComment(w, table.comment, "//", "");

    try w.print("export const {s} = {s}('{s}', {{\n", .{ table.name, table_fn, table.name });

    // Columns
    for (table.columns, 0..) |col, ci| {
        try writeColumn(w, col, table, dialect);
        if (ci < table.columns.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }

    try w.writeAll("}");

    // Table callback for indexes and composite FK constraints
    const has_indexes = common.tableHasNonPkIndexes(table);
    const has_composite_fks = common.tableHasCompositeFks(table);
    var has_fulltext = false;
    for (table.indexes) |idx| {
        if (idx.kind == .fulltext) has_fulltext = true;
    }

    if (has_indexes or has_composite_fks) {
        try w.writeAll(", (");
        try w.print("{s}", .{table.name});
        try w.writeAll(") => [");

        var first = true;

        // Composite FK constraints
        for (table.fks) |fk| {
            if (fk.fields.len <= 1) continue; // single-column handled by .references()
            if (!first) try w.writeAll(", ");
            first = false;
            try writeFkConstraint(w, fk, table.name);
        }

        // Indexes — fulltext is skipped here (no drizzle equivalent); it is
        // noted in a comment AFTER the statement, where `//` is legal.
        for (table.indexes) |idx| {
            if (idx.kind == .primary_key or idx.kind == .fulltext) continue;
            if (!first) try w.writeAll(", ");
            first = false;
            try writeIndexDef(w, idx);
        }

        try w.writeAll("]");
    }

    try w.writeAll(");\n");

    if (has_fulltext) {
        for (table.indexes) |idx| {
            if (idx.kind != .fulltext) continue;
            try w.print("// fulltext index '{s}' on ({s}): not supported by drizzle\n", .{ idx.name, idx.fields[0] });
        }
    }
}

// ─── Column Generation ──────────────────────────────────────────

fn writeColumn(w: *Writer, col: typed_ast.TypedColumn, table: typed_ast.TypedTable, dialect: Dialect) !void {
    try w.print("  {s}: ", .{col.name});

    // Enum columns use the dialect's enum constructor — the old code emitted
    // text() everywhere while also declaring pgEnum/mysqlEnum values that no
    // column ever referenced (dead enum + lost CHECK/enum typing).
    if (col.flags.is_enum and col.enum_values.len > 0) {
        switch (dialect) {
            .pg => {
                // pgEnum reference: the enum was declared as <col>Enum above.
                try w.print("{s}Enum('{s}')", .{ col.name, col.name });
            },
            else => {
                try w.print("{s}Enum('{s}', {s}Values)", .{ drizzleDialectPrefix(dialect), col.name, col.name });
            },
        }
    } else {
        try w.print("{s}('{s}'", .{ columnConstructor(col, dialect), col.name });
        // varchar length: without it the column degrades to the driver default.
        if (col.sql_type == .varchar) {
            const len = col.sql_type.varchar;
            if (len > 0) try w.print(", {{ length: {d} }}", .{len});
        }
        // Drizzle's decimal accepts { precision, scale }.
        if (col.sql_type == .decimal) {
            const ds = col.sql_type.decimal;
            try w.print(", {{ precision: {d}, scale: {d} }}", .{ ds.precision, ds.scale });
        }
        try w.writeAll(")");
    }

    // Primary key. pg-core has no `.autoincrement()` on integer — PG identity
    // comes from serial() or identity columns; emitting the mysql-only chain
    // method was a TS type error on every pg build.
    if (col.flags.primary_key) {
        try w.writeAll(".primaryKey()");
        if (col.flags.auto_increment and dialect != .pg) {
            try w.writeAll(".autoincrement()");
        }
    }

    // Unsigned modifier (mysql-core supports .unsigned(); pg/sqlite have no
    // unsigned concept).
    if (col.flags.unsigned and dialect == .mysql) {
        try w.writeAll(".unsigned()");
    }

    // Not null (non-nullable, non-primary-key)
    if (!col.flags.nullable and !col.flags.primary_key) {
        try w.writeAll(".notNull()");
    }

    // Unique
    if (col.flags.inline_unique and !col.flags.primary_key) {
        try w.writeAll(".unique()");
    }

    // Default value — exactly ONE .default(): the user's explicit default if
    // present, otherwise the first enum value for enums. The old code chained
    // both for enums with an explicit default; the second call silently won.
    var wrote_default = false;
    if (col.default) |dflt| {
        try common.writeOrmDefault(w, dflt, ".default(", ")", .drizzle);
        wrote_default = true;
    }
    if (!wrote_default and col.flags.is_enum and col.enum_values.len > 0) {
        try w.print(".default('{s}')", .{col.enum_values[0]});
    }

    // datetime `+` / `++` means DEFAULT CURRENT_TIMESTAMP (v0.326.0 invariant:
    // NOT auto-increment). typeorm already honored this; drizzle dropped it.
    if (!wrote_default and col.flags.has_timestamp_default) {
        try w.print(".defaultNow()", .{});
    }

    // Inline FK reference (single-column only)
    for (table.fks) |fk| {
        if (fk.fields.len == 1 and std.mem.eql(u8, fk.fields[0], col.name)) {
            try w.print(".references(() => {s}.{s})", .{ fk.ref_table, fk.ref_fields[0] });
            break;
        }
    }
}

fn drizzleDialectPrefix(dialect: Dialect) []const u8 {
    return switch (dialect) {
        .mysql => "mysql",
        .pg => "pg",
        .sqlite => "sqlite",
        .mssql => "mssql",
        .oracle => "pg",
        .db2 => "pg",
    };
}

fn columnConstructor(col: typed_ast.TypedColumn, dialect: Dialect) []const u8 {
    if (col.flags.is_enum) {
        return switch (dialect) {
            .pg => "text", // PG uses pgEnum separately
            else => "text",
        };
    }
    return switch (col.sql_type) {
        .int => "integer",
        .smallint => "smallint",
        .bigint => "bigint",
        .serial => "serial",
        .decimal => "decimal",
        .varchar => "varchar",
        .text => "text",
        .blob => "blob",
        .json => "json",
        .jsonb => "jsonb",
        .datetime, .timestamptz => "timestamp",
        .date => "date",
        .boolean => "boolean",
        .uuid => "uuid",
        .inet => "text",
        .enum_values => "text",
        .raw_sql, .passthrough => "text",
    };
}

// ─── FK Constraint Generation (composite) ──────────────────────

/// Composite FK in drizzle's third-generation callback API: the columns/
/// references arrays must be `table.<col>` member accesses — bare identifiers
/// are undefined variables and the generated module fails to compile.
fn writeFkConstraint(w: *Writer, fk: FkDecl, table_name: []const u8) !void {
    try w.writeAll("foreignKey({");
    try w.print("columns: [{s}.{s}", .{ table_name, fk.fields[0] });
    for (fk.fields[1..]) |field| {
        try w.print(", {s}.{s}", .{ table_name, field });
    }
    try w.writeAll("], ");
    try w.print("references: [{s}.{s}", .{ fk.ref_table, fk.ref_fields[0] });
    for (fk.ref_fields[1..]) |field| {
        try w.print(", {s}.{s}", .{ fk.ref_table, field });
    }
    try w.writeAll("]");
    try common.writeJsFkActions(w, fk.actions);
    try w.writeAll("})");
}

// ─── Index Generation ──────────────────────────────────────────

fn writeIndexDef(w: *Writer, idx: IndexDecl) !void {
    switch (idx.kind) {
        .unique => {
            try w.print("uniqueIndex('{s}').on({s}", .{ idx.name, idx.fields[0] });
            for (idx.fields[1..]) |field| {
                try w.print(", {s}", .{field});
            }
            try w.writeAll(")");
        },
        .regular => {
            try w.print("index('{s}').on({s}", .{ idx.name, idx.fields[0] });
            for (idx.fields[1..]) |field| {
                try w.print(", {s}", .{field});
            }
            try w.writeAll(")");
        },
        .fulltext => {
            try w.print("// fulltext index '{s}' on ({s})", .{ idx.name, idx.fields[0] });
            for (idx.fields[1..]) |field| {
                try w.print(", {s}", .{field});
            }
        },
        .primary_key => {},
    }
}

// ─── Helpers ────────────────────────────────────────────────────
// tableHasNonPkIndexes and tableHasCompositeFks are in generators/common.zig
