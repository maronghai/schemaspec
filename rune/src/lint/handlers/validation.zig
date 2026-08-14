const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../../types/ast.zig");
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── Re-exports ──────────────────────────────────────────────
// Domain-specific validation rules are now in focused modules.
pub const fk = @import("fk.zig");
pub const index = @import("index.zig");
pub const view = @import("view.zig");
pub const enum_ = @import("enum.zig");

// ─── Shared Field Helpers ──────────────────────────────────────

/// Check if a field has a primary key modifier (auto_inc_pk or primary_key).
pub fn isPrimaryKey(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .auto_inc_pk or mod.kind == .primary_key) return true;
    }
    return false;
}

/// Check if a field has the nullable modifier.
pub fn isNullable(field: ast_mod.Field) bool {
    for (field.modifiers) |mod| {
        if (mod.kind == .nullable) return true;
    }
    return false;
}

/// Check if a field has an explicit default value.
pub fn hasExplicitDefault(field: ast_mod.Field) bool {
    return field.default_val != null;
}

// ─── General Validation Rules ──────────────────────────────────
// Rules that don't fit into FK, index, view, or enum categories.

pub fn checkNullablePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field) and isNullable(field)) {
                const msg = try std.fmt.allocPrint(alloc, "primary key column '{s}' should not be nullable", .{field.name});
                try results.append(alloc, .{
                    .rule = "nullable-pk",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

pub fn checkBoolDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (!field.type_info.isBoolean()) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "boolean column '{s}' has no explicit default value", .{field.name});
            try results.append(alloc, .{
                .rule = "bool-default",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkColumnDefaultRequired(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "column '{s}' has no explicit DEFAULT value", .{field.name});
            try results.append(alloc, .{
                .rule = "column-default-required",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkNullableColumnDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (isPrimaryKey(field)) continue;
            if (!isNullable(field)) continue;
            if (hasExplicitDefault(field)) continue;

            const msg = try std.fmt.allocPrint(alloc, "nullable column '{s}' has no explicit DEFAULT — consider adding `= null` for clarity", .{field.name});
            try results.append(alloc, .{
                .rule = "nullable-column-default",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkDuplicateColumn(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Track seen column names
        var seen = std.StringHashMap(void).init(alloc);
        defer seen.deinit();

        for (table.fields) |field| {
            if (seen.contains(field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "duplicate column name '{s}' in table", .{field.name});
                try results.append(alloc, .{
                    .rule = "duplicate-column",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            } else {
                try seen.put(field.name, {});
            }
        }
    }
}

/// Check if a table has a UNIQUE constraint on a column that is already the primary key.
/// A single-column UNIQUE on the PK is redundant since PRIMARY KEY implies UNIQUE.
pub fn checkUniqueConstraint(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Find the primary key column name(s)
        var pk_columns = std.ArrayList([]const u8).initCapacity(alloc, table.fields.len) catch return;
        defer pk_columns.deinit(alloc);

        for (table.fields) |field| {
            if (isPrimaryKey(field)) {
                pk_columns.append(alloc, field.name) catch return;
            }
        }

        // Check if any UNIQUE index targets a single PK column
        for (table.indexes) |idx| {
            if (idx.kind == .unique and idx.fields.len == 1) {
                for (pk_columns.items) |pk_col| {
                    if (std.mem.eql(u8, idx.fields[0], pk_col)) {
                        const msg = try std.fmt.allocPrint(alloc, "UNIQUE constraint on '{s}' is redundant (already primary key)", .{pk_col});
                        try results.append(alloc, .{
                            .rule = "unique-constraint",
                            .table = table.name,
                            .message = msg,
                            .severity = .warning,
                        });
                    }
                }
            }
        }
    }
}

/// Check if a table has multiple auto-increment primary keys (invalid).
/// Only one auto-increment PK is allowed per table.
pub fn checkCompositePk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        var auto_inc_count: usize = 0;
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk) {
                    auto_inc_count += 1;
                }
            }
        }
        if (auto_inc_count > 1) {
            const msg = try std.fmt.allocPrint(alloc, "table has {d} auto-increment primary keys (only 1 allowed)", .{auto_inc_count});
            try results.append(alloc, .{
                .rule = "composite-pk",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

/// Check if a nullable column has a UNIQUE constraint (inline_unique modifier).
/// Multiple NULLs are allowed in UNIQUE columns in most databases (SQL standard),
/// which is often unintended and leads to data integrity issues.
pub fn checkColumnUniqueNullable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_unique = false;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .inline_unique) has_unique = true;
                if (mod.kind == .nullable) has_nullable = true;
            }
            if (has_unique and has_nullable) {
                const msg = try std.fmt.allocPrint(alloc, "UNIQUE constraint on nullable column '{s}' — multiple NULLs are allowed", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-unique-nullable",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if auto-increment modifier (@ or @++) is used on a non-integer type.
/// Auto-increment only works with integer types (n, N, i, I, m, M, p).
pub fn checkColumnAutoIncrementType(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_auto_inc = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .auto_inc) {
                    has_auto_inc = true;
                    break;
                }
            }
            if (!has_auto_inc) continue;
            // Check if the type is non-integer
            if (field.type_info.isString() or field.type_info.isBoolean() or field.type_info.isDatetime() or field.type_info.isBlob()) {
                const type_name = switch (field.type_info) {
                    .simple => |s| s,
                    .varchar_explicit => "varchar",
                    .enum_type => "enum",
                    .raw_sql => "raw",
                    else => "unknown",
                };
                const msg = try std.fmt.allocPrint(alloc, "auto-increment on column '{s}' with non-integer type '{s}'", .{ field.name, type_name });
                try results.append(alloc, .{
                    .rule = "column-auto-increment-type",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if columns in the same table have names that differ only by case.
/// This can cause confusion and bugs in case-insensitive databases.
pub fn checkColumnUniqueNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        // Compare each pair of columns (O(n²) but n is typically small)
        for (table.fields, 0..) |field_a, i| {
            for (table.fields[i + 1 ..]) |field_b| {
                if (std.mem.eql(u8, field_a.name, field_b.name)) continue; // exact duplicates handled by duplicate-column
                // Case-insensitive comparison
                var buf_a: [256]u8 = undefined;
                var buf_b: [256]u8 = undefined;
                if (field_a.name.len > 256 or field_b.name.len > 256) continue;
                const lower_a = std.ascii.lowerString(&buf_a, field_a.name);
                const lower_b = std.ascii.lowerString(&buf_b, field_b.name);
                if (std.mem.eql(u8, lower_a, lower_b)) {
                    const msg = try std.fmt.allocPrint(alloc, "columns '{s}' and '{s}' differ only by case", .{ field_a.name, field_b.name });
                    try results.append(alloc, .{
                        .rule = "column-unique-naming",
                        .table = table.name,
                        .message = msg,
                        .severity = .warning,
                    });
                }
            }
        }
    }
}

/// Check if auto-increment modifier (@/++) is used on a nullable column.
/// Auto-increment columns should always be NOT NULL — nullable auto-increment
/// is contradictory and indicates a schema design error.
pub fn checkColumnAutoIncrementNullable(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_auto_inc = false;
            var has_nullable = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc_pk or mod.kind == .auto_inc) has_auto_inc = true;
                if (mod.kind == .nullable) has_nullable = true;
            }
            if (has_auto_inc and has_nullable) {
                const msg = try std.fmt.allocPrint(alloc, "auto-increment on nullable column '{s}' — should be NOT NULL", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-auto-increment-nullable",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}

/// Check if a column's default value matches its type category.
/// Warns when a default literal is incompatible with the column's type category
/// (e.g. a quoted string on a numeric column, a bare number on a string/datetime/
/// blob column, a non-datetime quoted string on a datetime column, or a boolean
/// literal on a non-boolean column). Catches copy-paste / wrong-type schema bugs
/// early. Covers all six type categories (numeric, string, datetime, boolean, blob,
/// other) — `column-bad-default` was expanded in v0.290.0 beyond its original
/// numeric/boolean-only scope.
pub fn checkColumnBadDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            const dv = field.default_val orelse continue;
            const val = dv.value;
            if (val.len == 0) continue;

            const cat = field.type_info.category();

            // Quoted string default ('...')
            if (val[0] == '\'' and val.len >= 2 and val[val.len - 1] == '\'') {
                const inner = val[1 .. val.len - 1];
                // A quoted default that looks like a SQL function call is owned by
                // `column-default-function-check` (it would be stored verbatim, not
                // evaluated) — don't also flag it as a wrong-type string default.
                if (looksLikeSqlFunctionCall(inner)) continue;
                switch (cat) {
                    .numeric => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has string default {s} but is a numeric type", .{ field.name, val })),
                    .boolean => if (!isBoolToken(inner)) try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has string default {s} but is a boolean type", .{ field.name, val })),
                    .datetime => if (!looksLikeDatetime(inner)) try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has string default {s} but is a datetime type", .{ field.name, val })),
                    else => {},
                }
                continue;
            }

            // Bare (unquoted) numeric literal default
            if (isNumericLiteral(val)) {
                switch (cat) {
                    .boolean => if (!std.mem.eql(u8, val, "0") and !std.mem.eql(u8, val, "1")) try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has numeric default {s} but is a boolean type (use true/false or 0/1)", .{ field.name, val })),
                    .string => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has numeric default {s} but is a string type", .{ field.name, val })),
                    .datetime => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has numeric default {s} but is a datetime type", .{ field.name, val })),
                    .blob => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has numeric default {s} but is a blob type", .{ field.name, val })),
                    else => {},
                }
                continue;
            }

            // Bare boolean literal default (true/false)
            if (isBoolToken(val)) {
                switch (cat) {
                    .numeric, .string, .datetime, .blob => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has boolean default {s} but is a {s} type", .{ field.name, val, catName(cat) })),
                    else => {},
                }
                continue;
            }

            // Bare token that is neither numeric nor boolean literal (a function name,
            // an unquoted word, etc.). Flag only on numeric/boolean columns, which can
            // never accept an arbitrary bare token as a sensible default.
            switch (cat) {
                .numeric => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has non-numeric default {s} on a numeric type", .{ field.name, val })),
                .boolean => try appendBadDefault(alloc, results, table, try std.fmt.allocPrint(alloc, "column '{s}' has non-boolean default {s} on a boolean type", .{ field.name, val })),
                else => {},
            }
        }
    }
}

/// Append a `column-bad-default` warning for a column in `table`.
fn appendBadDefault(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), table: ResolvedTable, msg: []const u8) !void {
    try results.append(alloc, .{
        .rule = "column-bad-default",
        .table = table.name,
        .message = msg,
        .severity = .warning,
    });
}

/// True if `s` is a bare numeric literal (digits, optional sign, optional decimal point).
fn isNumericLiteral(s: []const u8) bool {
    if (s.len == 0) return false;
    var has_digit = false;
    for (s) |ch| {
        if (ch == '-' or ch == '+' or ch == '.') continue;
        if (ch < '0' or ch > '9') return false;
        has_digit = true;
    }
    return has_digit;
}

/// True if `s` is a bare boolean literal token (`true` or `false`).
fn isBoolToken(s: []const u8) bool {
    return std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "false");
}

/// True if `s` looks like a datetime literal: a date/time string (digits plus
/// `- / : . space T Z` separators) or a function-like token (`now`,
/// `current_timestamp`, `epoch`, case-insensitive).
fn looksLikeDatetime(s: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(s, "now")) return true;
    if (std.ascii.eqlIgnoreCase(s, "current_timestamp")) return true;
    if (std.ascii.eqlIgnoreCase(s, "epoch")) return true;
    var has_digit = false;
    for (s) |ch| {
        const ok = (ch >= '0' and ch <= '9') or ch == '-' or ch == '/' or ch == ':' or ch == '.' or ch == ' ' or ch == 'T' or ch == 'Z';
        if (!ok) return false;
        if (ch >= '0' and ch <= '9') has_digit = true;
    }
    return has_digit;
}

/// Human-readable name of a type category for warning messages.
fn catName(cat: ast_mod.TypeCategory) []const u8 {
    return switch (cat) {
        .numeric => "numeric",
        .string => "string",
        .datetime => "datetime",
        .boolean => "boolean",
        .blob => "blob",
        .other => "other",
    };
}
/// Check for SQL function-call defaults written as quoted string literals.
/// A default like `created_at t = 'now()'` (or `'CURRENT_TIMESTAMP'`) is stored
/// verbatim as the literal string instead of being evaluated by the database, so
/// the column ends up holding the text "now()" rather than the current timestamp.
/// This completes the default-value correctness family alongside `column-bad-default`
/// and `column-default-required`. Non-fixable: the author must decide whether to
/// remove the quotes (evaluate the function) or keep a genuine string literal.
pub fn checkColumnDefaultFunctionCheck(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            const dv = field.default_val orelse continue;
            const val = dv.value;
            if (val.len < 2) continue;
            // Only a quoted string default can accidentally store a function verbatim.
            if (val[0] != '\'' or val[val.len - 1] != '\'') continue;
            const inner = val[1 .. val.len - 1];
            if (inner.len == 0) continue;
            if (!looksLikeSqlFunctionCall(inner)) continue;

            const msg = try std.fmt.allocPrint(alloc, "column '{s}' default {s} is a SQL function call written as a quoted string literal — it will be stored verbatim instead of evaluated (remove the quotes: {s})", .{ field.name, val, inner });
            try results.append(alloc, .{
                .rule = "column-default-function-check",
                .table = table.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

/// True if `s` (the inner text of a quoted default) looks like a SQL function call
/// that should be evaluated by the database rather than stored as a literal string.
/// Uses a known allowlist of SQL default functions to keep false positives low:
/// the text must start with a known function name followed by `(` ... `)` (e.g.
/// `now()`, `uuid_generate_v4()`, `getdate()`), or be exactly one of the
/// no-paren token forms (e.g. `current_timestamp`, `sysdate`, `epoch`).
fn looksLikeSqlFunctionCall(inner: []const u8) bool {
    const trimmed = std.mem.trim(u8, inner, " \t");
    if (trimmed.len == 0) return false;

    // No-paren token forms — exactly these SQL expressions.
    const tokens = [_][]const u8{
        "now", "epoch", "sysdate", "today",
        "current_timestamp", "current_date", "current_time",
        "utc_timestamp", "utc_date", "utc_time",
        "localtimestamp", "localtime",
        "curdate", "curtime",
    };
    for (tokens) |t| {
        if (std.ascii.eqlIgnoreCase(trimmed, t)) return true;
    }

    // Parenthesized function-call forms: <name>(<args>) where <name> is known.
    const funcs = [_][]const u8{
        "now", "epoch", "sysdate", "today", "uuid",
        "uuid_generate_v4", "gen_random_uuid", "rand", "getdate", "getutcdate",
        "current_timestamp", "current_date", "current_time",
        "utc_timestamp", "utc_date", "utc_time",
        "localtimestamp", "localtime", "curdate", "curtime",
    };
    for (funcs) |f| {
        if (trimmed.len < f.len + 2) continue;
        if (!std.ascii.startsWithIgnoreCase(trimmed, f)) continue;
        var i: usize = f.len;
        if (trimmed[i] != '(') continue;
        i += 1;
        while (i < trimmed.len and trimmed[i] != ')') i += 1;
        if (i < trimmed.len and trimmed[i] == ')') return true;
    }
    return false;
}



/// Check for auto-increment columns that are not part of the primary key.
/// An `auto_inc` column that is not a key is meaningless on MySQL (where
/// AUTO_INCREMENT must be a key) and a design smell everywhere else — the value
/// has no stable identity anchor. Completes the auto-increment rule family
/// alongside `column-auto-increment-type` and `column-auto-increment-nullable`.
pub fn checkAutoIncrementWithoutPk(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            var has_auto_inc = false;
            for (field.modifiers) |mod| {
                if (mod.kind == .auto_inc) has_auto_inc = true;
            }
            if (has_auto_inc and !isPrimaryKey(field)) {
                const msg = try std.fmt.allocPrint(alloc, "auto-increment column '{s}' is not part of the primary key", .{field.name});
                try results.append(alloc, .{
                    .rule = "auto-increment-without-pk",
                    .table = table.name,
                    .message = msg,
                    .severity = .warning,
                });
            }
        }
    }
}
