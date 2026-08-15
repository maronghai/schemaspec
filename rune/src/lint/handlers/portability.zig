const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── Portability & Quality Rules ──────────────────────────────
// Rules that check for SQL reserved words, non-portable types,
// and missing FK indexes.

/// Common SQL reserved words that should not be used as table/column names.
const SQL_RESERVED_WORDS = [_][]const u8{
    "select",    "insert",      "update",     "delete",    "from",    "where",     "join",
    "inner",     "left",        "right",      "outer",     "on",      "and",       "or",
    "not",       "in",          "between",    "like",      "order",   "group",     "by",
    "having",    "limit",       "offset",     "union",     "all",     "distinct",  "as",
    "create",    "alter",       "drop",       "table",     "index",   "view",      "database",
    "schema",    "column",      "constraint", "primary",   "key",     "foreign",   "references",
    "unique",    "check",       "default",    "null",      "not",     "is",        "true",
    "false",     "exists",      "case",       "when",      "then",    "else",      "end",
    "into",      "values",      "set",        "grant",     "revoke",  "commit",    "rollback",
    "begin",     "transaction", "savepoint",  "if",        "else",    "while",     "for",
    "loop",      "return",      "function",   "procedure", "trigger", "event",     "temp",
    "temporary", "replace",     "recursive",  "cube",      "rollup",  "grouping",  "window",
    "over",      "partition",   "rows",       "range",     "current", "preceding", "following",
    "unbounded", "row",         "rows",       "fetch",     "first",   "next",      "only",
    "with",      "lateral",     "cross",      "natural",   "using",   "asc",       "desc",
    "nulls",     "first",       "last",       "limit",     "offset",  "top",       "percent",
    "ties",      "no",          "skip",       "locked",    "for",     "share",     "update",
};

/// Check if a name is a SQL reserved word (case-insensitive).
fn isReservedWord(name: []const u8) bool {
    for (SQL_RESERVED_WORDS) |word| {
        if (std.ascii.eqlIgnoreCase(name, word)) return true;
    }
    return false;
}

/// Check for table/column names that use SQL reserved words.
pub fn checkReservedWord(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Check table name
        if (isReservedWord(table.name)) {
            const msg = try std.fmt.allocPrint(alloc, "table name '{s}' is a SQL reserved word — consider renaming to avoid conflicts", .{table.name});
            try results.append(alloc, .{
                .rule = "reserved-word",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
        // Check column names
        for (table.fields) |field| {
            if (isReservedWord(field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "column name '{s}' is a SQL reserved word — consider renaming to avoid conflicts", .{field.name});
                try results.append(alloc, .{
                    .rule = "reserved-word",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check for non-portable column types.
pub fn checkColumnTypePortability(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            switch (field.type_info) {
                .simple => |s| {
                    // MySQL-specific types
                    if (std.mem.eql(u8, s, "tinyint")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific TINYINT — use 'i' (smallint) for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "mediumint")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific MEDIUMINT — use 'n' (int) for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "mediumtext")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific MEDIUMTEXT — use 'S' (text) for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "longtext")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses MySQL-specific LONGTEXT — use 'S' (text) for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "serial")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses PostgreSQL-specific SERIAL — use 'n++' for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "bigserial")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses PostgreSQL-specific BIGSERIAL — use 'N++' for portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "boolean")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses BOOLEAN type — use 'b' for Rune portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "datetime")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses DATETIME type — use 't' for Rune portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    } else if (std.mem.eql(u8, s, "double")) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' uses DOUBLE type — use 'f' (float) for Rune portability", .{field.name});
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                .varchar_explicit => |len| {
                    if (len > 8000) {
                        const msg = try std.fmt.allocPrint(alloc, "column '{s}' has varchar({d}) — very large varchar may not be portable to all dialects", .{ field.name, len });
                        try results.append(alloc, .{
                            .rule = "column-type-portability",
                            .table = table.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                },
                else => {},
            }
        }
    }
}

/// Check for tables with foreign keys but no index on FK columns.
pub fn checkIndexMissingFkColumns(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Collect FK column names
        var fk_columns = try std.ArrayList([]const u8).initCapacity(alloc, table.fks.len * 4);
        defer fk_columns.deinit(alloc);

        for (table.fks) |fk| {
            for (fk.fields) |col| {
                try fk_columns.append(alloc, col);
            }
        }

        // If no FKs, skip
        if (fk_columns.items.len == 0) continue;

        // Collect indexed column names
        var indexed_columns = std.StringHashMap(void).init(alloc);
        defer indexed_columns.deinit();

        // Check inline indexes (on field declarations)
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_index) {
                    try indexed_columns.put(field.name, {});
                    break;
                }
            }
        }

        // Check standalone indexes
        for (table.indexes) |idx| {
            for (idx.fields) |col| {
                try indexed_columns.put(col, {});
            }
        }

        // Check if PK columns are indexed (they always are)
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) {
                    try indexed_columns.put(field.name, {});
                    break;
                }
            }
        }

        // Check which FK columns are missing indexes
        for (fk_columns.items) |col| {
            if (!indexed_columns.contains(col)) {
                const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' has no index — add an index for query performance", .{col});
                try results.append(alloc, .{
                    .rule = "index-missing-fk-columns",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// `unsigned-overflow-risk` — warns when an `unsigned` numeric column backs an auto-increment
/// whose values can exceed the signed range in dialects that lack unsigned integer types
/// (e.g. PostgreSQL, where `unsigned` is silently dropped and the column becomes signed). An
/// `AUTO_INCREMENT`/`SERIAL` on a `BIGINT UNSIGNED` can reach ~1.8e19 while a signed 64-bit column
/// tops out at ~9.2e18; the extra half of the range wraps/overflows on a dialect that maps it to a
/// signed type. Non-fixable: the author must pick a dialect-agnostic type (e.g. `N++`/`n++` bigint
/// with headroom) or drop `unsigned` where portability matters.
pub fn checkUnsignedOverflowRisk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            // Only numeric columns can carry this risk.
            if (!field.type_info.isNumeric()) continue;

            var is_unsigned = false;
            var is_auto_inc = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .unsigned) is_unsigned = true;
                if (mod.kind == .auto_inc or mod.kind == .auto_inc_pk) is_auto_inc = true;
            }
            if (!is_unsigned or !is_auto_inc) continue;

            const msg = try std.fmt.allocPrint(
                alloc,
                "column '{s}' is unsigned and auto-increment — in dialects without unsigned types (e.g. PostgreSQL) it becomes signed, so values above the signed range silently overflow",
                .{field.name},
            );
            try results.append(alloc, .{
                .rule = "unsigned-overflow-risk",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

/// `charset-collation-portability` — warns when the schema pins a dialect-specific
/// character set (or collation) at the `$ name charset` header. The `.ss` language exposes
/// a single `charset` token there (e.g. `$ myapp utf8mb4`). Pinning a MySQL-specific charset
/// such as `utf8mb4` (or any collation-style value containing `_`, e.g. `utf8mb4_0900_ai_ci`)
/// constrains portability: PostgreSQL has no `utf8mb4`, Oracle/DB2 use different charset names,
/// and SQLite ignores it. Non-fixable: the author should omit the charset (let the target dialect
/// default) or use a neutral `utf8`.
pub fn checkCharsetCollationPortability(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    const charset = ast.schema_charset orelse return;
    const schema = ast.schema_name orelse "";
    // Collation-style values (contain an underscore, e.g. utf8mb4_0900_ai_ci) are always
    // dialect-specific and have no portable equivalent across all six dialects.
    if (std.mem.indexOf(u8, charset, "_") != null) {
        const msg = try std.fmt.allocPrint(
            alloc,
            "schema character set '{s}' is a dialect-specific collation — it has no equivalent in all six dialects (PostgreSQL, Oracle, DB2, SQLite differ); prefer a neutral charset or omit it",
            .{charset},
        );
        try results.append(alloc, .{
            .rule = "charset-collation-portability",
            .table = schema,
            .message = msg,
            .severity = .warning,
        });
        return;
    }
    // Curated list of MySQL-specific charset names that don't port across all six dialects.
    const non_portable = [_][]const u8{ "utf8mb4", "latin1", "ucs2", "utf16", "utf16le", "utf16be", "utf32", "binary" };
    for (non_portable) |cs| {
        if (std.ascii.eqlIgnoreCase(charset, cs)) {
            const msg = try std.fmt.allocPrint(
                alloc,
                "schema character set '{s}' is MySQL-specific — it has no equivalent in all six dialects (PostgreSQL, Oracle, DB2, SQLite differ); prefer a neutral utf8 or omit the charset",
                .{charset},
            );
            try results.append(alloc, .{
                .rule = "charset-collation-portability",
                .table = schema,
                .message = msg,
                .severity = .warning,
            });
            return;
        }
    }
}
