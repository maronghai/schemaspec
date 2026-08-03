const std = @import("std");
const Writer = std.Io.Writer;

// ─── Default Value Formatting ────────────────────────────────
// Shared by ORM generators (drizzle, knex, typeorm, sqlalchemy).
// Each generator provides language-specific formatting callbacks
// via a DefaultFormatter config struct.

/// Language-specific formatting callbacks for default values.
pub const DefaultFormatter = struct {
    /// Output for SQL `true` / `TRUE` (e.g. "true", "'true'")
    boolTrue: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `false` / `FALSE` (e.g. "false", "'false'")
    boolFalse: *const fn (w: *Writer) anyerror!void,
    /// Output for SQL `null` / `NULL` (e.g. "null", "None")
    nullValue: *const fn (w: *Writer) anyerror!void,
    /// Output for `NOW()` / `now()` / `CURRENT_TIMESTAMP`
    now: *const fn (w: *Writer) anyerror!void,
    /// Format a string default (e.g. "'foo'", `"foo"`)
    formatString: *const fn (w: *Writer, dflt: []const u8) anyerror!void,
};

/// Pre-defined ORM target languages for DefaultFormatter.
pub const OrmTarget = enum {
    drizzle,
    knex,
    sqlalchemy,
    typeorm,
};

/// Shared callback: format string as single-quoted (used by all ORMs).
fn formatStringSingleQuoted(w: *Writer, dflt: []const u8) !void {
    const trimmed = std.mem.trim(u8, dflt, "'");
    try w.print("'{s}'", .{trimmed});
}

// ─── Per-ORM Callbacks ────────────────────────────────────────

fn jsBoolTrue(w: *Writer) !void {
    try w.writeAll("true");
}
fn jsBoolFalse(w: *Writer) !void {
    try w.writeAll("false");
}
fn jsNull(w: *Writer) !void {
    try w.writeAll("null");
}

fn drizzleNow(w: *Writer) !void {
    try w.writeAll("new Date()");
}
fn knexNow(w: *Writer) !void {
    try w.writeAll("knex.fn.now()");
}
fn sqlalchemyBoolTrue(w: *Writer) !void {
    try w.writeAll("'true'");
}
fn sqlalchemyBoolFalse(w: *Writer) !void {
    try w.writeAll("'false'");
}
fn sqlalchemyNull(w: *Writer) !void {
    try w.writeAll("None");
}
fn sqlalchemyNow(w: *Writer) !void {
    try w.writeAll("'now()'");
}
fn typeormNow(w: *Writer) !void {
    try w.writeAll("() => new Date()");
}

/// Get a pre-configured DefaultFormatter for the given ORM target.
pub fn getOrmFormatter(target: OrmTarget) DefaultFormatter {
    return switch (target) {
        .drizzle => .{
            .boolTrue = jsBoolTrue,
            .boolFalse = jsBoolFalse,
            .nullValue = jsNull,
            .now = drizzleNow,
            .formatString = formatStringSingleQuoted,
        },
        .knex => .{
            .boolTrue = jsBoolTrue,
            .boolFalse = jsBoolFalse,
            .nullValue = jsNull,
            .now = knexNow,
            .formatString = formatStringSingleQuoted,
        },
        .sqlalchemy => .{
            .boolTrue = sqlalchemyBoolTrue,
            .boolFalse = sqlalchemyBoolFalse,
            .nullValue = sqlalchemyNull,
            .now = sqlalchemyNow,
            .formatString = formatStringSingleQuoted,
        },
        .typeorm => .{
            .boolTrue = jsBoolTrue,
            .boolFalse = jsBoolFalse,
            .nullValue = jsNull,
            .now = typeormNow,
            .formatString = formatStringSingleQuoted,
        },
    };
}

/// Shared default value writer. Parses the raw SQL default value and
/// delegates formatting to language-specific callbacks.
pub fn writeFormattedDefault(w: *Writer, dflt: []const u8, fmt: DefaultFormatter) !void {
    if (std.mem.eql(u8, dflt, "true") or std.mem.eql(u8, dflt, "TRUE")) {
        try fmt.boolTrue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "false") or std.mem.eql(u8, dflt, "FALSE")) {
        try fmt.boolFalse(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "null") or std.mem.eql(u8, dflt, "NULL")) {
        try fmt.nullValue(w);
        return;
    }
    if (std.mem.eql(u8, dflt, "NOW()") or std.mem.eql(u8, dflt, "now()") or
        std.mem.eql(u8, dflt, "CURRENT_TIMESTAMP"))
    {
        try fmt.now(w);
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
    try fmt.formatString(w, dflt);
}
