const std = @import("std");
const data = @import("../reverse/map_data.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const dialect_enum = @import("../dialect/enum.zig");
const sqlite_hints = @import("../dialect/sqlite_hints.zig");

pub const Dialect = dialect_enum.Dialect;
pub const ReverseMapping = data.ReverseMapping;
pub const REVERSE_MAP = data.REVERSE_MAP;
pub const ReverseResult = dialect_mod.ReverseResult;
pub const canOmitType = dialect_mod.canOmitType;

/// Reverse-lookup a SQL type string to its SS symbol.
/// Handles exact match from REVERSE_MAP + parameterized types (int(N), decimal(P,S), varchar(N)).
/// For dialects with a vtable reverseLookup (e.g. SQLite), delegates to the backend.
pub fn reverseLookup(sql_type: []const u8, col_name: []const u8, is_auto_inc: bool, is_default_ts: bool, dialect: Dialect) ReverseResult {
    const t = std.mem.trim(u8, sql_type, " \t");

    // Check if dialect has a custom reverse lookup (e.g. SQLite)
    const backend = dialect_mod.getBackend(dialect);
    if (backend.reverseLookup(t, col_name, is_auto_inc, is_default_ts)) |result| {
        return result;
    }

    // General path: MySQL/PG exact match from REVERSE_MAP + parameterized types
    var best_match: ?ReverseResult = null;
    var best_priority: u32 = std.math.maxInt(u32);
    for (REVERSE_MAP) |m| {
        if (std.mem.eql(u8, t, m.mysql) or std.mem.eql(u8, t, m.pg)) {
            if (m.rev_priority < best_priority) {
                best_priority = m.rev_priority;
                best_match = .{ .sym = m.sym, .omit = canOmitType(col_name, m.sym, is_auto_inc, is_default_ts), .score = m.confidence_base };
            }
        }
    }
    if (best_match) |bm| return bm;

    // ─── Parameterized type patterns ───

    // int(N) → N
    if (std.mem.startsWith(u8, t, "int(") and std.mem.endsWith(u8, t, ")"))
        return .{ .sym = t[4 .. t.len - 1], .omit = false };

    // decimal(P,S) or decimal(P, S) → P,S
    if (std.mem.startsWith(u8, t, "decimal(") and std.mem.endsWith(u8, t, ")")) {
        const inner = t[8 .. t.len - 1];
        const sbuf = struct {
            var buf: [16]u8 = undefined;
        };
        var j: usize = 0;
        for (inner) |ch| {
            if (ch != ' ') {
                if (j >= 16) return .{ .sym = t, .omit = false };
                sbuf.buf[j] = ch;
                j += 1;
            }
        }
        return .{ .sym = sbuf.buf[0..j], .omit = false };
    }

    // numeric(P,S) → P,S
    if (std.mem.startsWith(u8, t, "numeric(") and std.mem.endsWith(u8, t, ")")) {
        const inner = t[8 .. t.len - 1];
        const sbuf = struct {
            var buf: [16]u8 = undefined;
        };
        var j: usize = 0;
        for (inner) |ch| {
            if (ch != ' ') {
                if (j >= 16) return .{ .sym = t, .omit = false };
                sbuf.buf[j] = ch;
                j += 1;
            }
        }
        return .{ .sym = sbuf.buf[0..j], .omit = false };
    }

    // varchar(255) → s (with omit check)
    if (std.mem.eql(u8, t, "varchar(255)"))
        return .{ .sym = "s", .omit = canOmitType(col_name, "s", is_auto_inc, is_default_ts) };

    // character varying(N) → sN (guard: inner must fit in 16-byte buffer)
    if (std.mem.startsWith(u8, t, "character varying(") and std.mem.endsWith(u8, t, ")")) {
        const inner = std.mem.trim(u8, t[17 .. t.len - 1], " ");
        if (std.mem.eql(u8, inner, "255"))
            return .{ .sym = "s", .omit = canOmitType(col_name, "s", is_auto_inc, is_default_ts) };
        if (inner.len > 15) return .{ .sym = t, .omit = false };
        const sbuf = struct {
            var buf: [16]u8 = undefined;
        };
        sbuf.buf[0] = 's';
        for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
        return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
    }

    // varchar(N) → sN (guard: inner must fit in 16-byte buffer)
    if (std.mem.startsWith(u8, t, "varchar(") and std.mem.endsWith(u8, t, ")")) {
        const inner = std.mem.trim(u8, t[8 .. t.len - 1], " ");
        if (inner.len > 15) return .{ .sym = t, .omit = false };
        const sbuf = struct {
            var buf: [16]u8 = undefined;
        };
        sbuf.buf[0] = 's';
        for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
        return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
    }

    // ENUM(...) → pass through
    if (std.mem.startsWith(u8, t, "ENUM(") or std.mem.startsWith(u8, t, "enum("))
        return .{ .sym = t, .omit = false };

    return .{ .sym = t, .omit = false };
}

// ─── Helper: classify SQL type strings (re-exports from sqlite_hints) ──

pub const isDatetimeSqlType = sqlite_hints.isDatetimeSqlType;
pub const isCurrentTimestamp = sqlite_hints.isCurrentTimestamp;
