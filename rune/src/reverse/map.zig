const std = @import("std");
const data = @import("../reverse/map_data.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const dialect_enum = @import("../dialect/enum.zig");
const sqlite_hints = @import("../dialect/sqlite_hints.zig");
const reverse_map_mod = @import("../types/reverse_map.zig");

pub const Dialect = dialect_enum.Dialect;
pub const ReverseMapping = data.ReverseMapping;
pub const REVERSE_MAP = data.REVERSE_MAP;
pub const ReverseResult = dialect_mod.ReverseResult;
pub const canOmitType = dialect_mod.canOmitType;

/// Case-insensitive check if `s` starts with `prefix`. Returns the remaining slice after the prefix.
fn matchPrefix(s: []const u8, prefix: []const u8) ?[]const u8 {
    if (s.len < prefix.len) return null;
    for (prefix, 0..) |pc, i| {
        const sc = s[i];
        const lower = if (sc >= 'A' and sc <= 'Z') sc + 32 else sc;
        if (lower != pc) return null;
    }
    return s[prefix.len..];
}

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

    // General path: exact match from REVERSE_MAP for all dialects + parameterized types
    // Matches against mysql, pg, mssql, oracle, and db2 type columns.
    var best_match: ?ReverseResult = null;
    var best_priority: u32 = std.math.maxInt(u32);
    for (REVERSE_MAP) |m| {
        // Comptime iteration over all dialects — no hardcoded `or` chain.
        inline for (reverse_map_mod.DIALECT_NAMES) |d| {
            if (std.mem.eql(u8, t, reverse_map_mod.getDialectType(m.types, d))) {
                if (m.rev_priority < best_priority) {
                    best_priority = m.rev_priority;
                    best_match = .{ .sym = m.sym, .omit = canOmitType(col_name, m.sym, is_auto_inc, is_default_ts), .score = m.confidence_base };
                }
            }
        }
    }
    if (best_match) |bm| return bm;

    // ─── Parameterized type patterns (case-insensitive for Oracle/Db2 uppercase) ───

    // int(N) → N
    if (matchPrefix(t, "int(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")"))
            return .{ .sym = rest[0 .. rest.len - 1], .omit = false };
    }

    // decimal(P,S) or decimal(P, S) → P,S
    if (matchPrefix(t, "decimal(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = rest[0 .. rest.len - 1];
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
    }

    // numeric(P,S) → P,S
    if (matchPrefix(t, "numeric(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = rest[0 .. rest.len - 1];
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
    }

    // varchar(255) → s (with omit check)
    if (std.mem.eql(u8, t, "varchar(255)") or std.mem.eql(u8, t, "VARCHAR(255)"))
        return .{ .sym = "s", .omit = canOmitType(col_name, "s", is_auto_inc, is_default_ts) };

    // character varying(N) → sN (guard: inner must fit in 16-byte buffer)
    if (matchPrefix(t, "character varying(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");
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
    }

    // varchar(N) → sN (guard: inner must fit in 16-byte buffer)
    if (matchPrefix(t, "varchar(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");
            if (inner.len > 15) return .{ .sym = t, .omit = false };
            const sbuf = struct {
                var buf: [16]u8 = undefined;
            };
            sbuf.buf[0] = 's';
            for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
            return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
        }
    }

    // VARCHAR2(N) → sN (Oracle, guard: inner must fit in 16-byte buffer)
    if (matchPrefix(t, "varchar2(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");
            if (inner.len > 15) return .{ .sym = t, .omit = false };
            const sbuf = struct {
                var buf: [16]u8 = undefined;
            };
            sbuf.buf[0] = 's';
            for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
            return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
        }
    }

    // NVARCHAR2(N) → sN (Oracle, guard: inner must fit in 16-byte buffer)
    if (matchPrefix(t, "nvarchar2(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");
            if (inner.len > 15) return .{ .sym = t, .omit = false };
            const sbuf = struct {
                var buf: [16]u8 = undefined;
            };
            sbuf.buf[0] = 's';
            for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
            return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
        }
    }

    // NUMBER(P,S) → P,S or NUMBER(P) → N (Oracle, guard: inner must fit in 32-byte buffer)
    if (matchPrefix(t, "number(")) |rest| {
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");
            // If there's a comma, it's NUMBER(P,S) → P,S
            if (std.mem.indexOf(u8, inner, ",")) |comma_pos| {
                const p = std.mem.trim(u8, inner[0..comma_pos], " ");
                const s = std.mem.trim(u8, inner[comma_pos + 1 ..], " ");
                const sbuf = struct {
                    var buf: [32]u8 = undefined;
                };
                var j: usize = 0;
                for (p) |ch| {
                    if (ch != ' ') {
                        if (j >= 32) return .{ .sym = t, .omit = false };
                        sbuf.buf[j] = ch;
                        j += 1;
                    }
                }
                if (j < 32) { sbuf.buf[j] = ','; j += 1; }
                for (s) |ch| {
                    if (ch != ' ') {
                        if (j >= 32) return .{ .sym = t, .omit = false };
                        sbuf.buf[j] = ch;
                        j += 1;
                    }
                }
                return .{ .sym = sbuf.buf[0..j], .omit = false };
            }
            // No comma — single number means integer → N
            if (inner.len > 15) return .{ .sym = t, .omit = false };
            const sbuf = struct {
                var buf: [16]u8 = undefined;
            };
            sbuf.buf[0] = 'N';
            for (inner, 0..) |ch, i| sbuf.buf[i + 1] = ch;
            return .{ .sym = sbuf.buf[0 .. 1 + inner.len], .omit = false };
        }
    }

    // ENUM(...) → pass through
    if (std.mem.startsWith(u8, t, "ENUM(") or std.mem.startsWith(u8, t, "enum("))
        return .{ .sym = t, .omit = false };

    return .{ .sym = t, .omit = false };
}

// ─── Helper: classify SQL type strings (re-exports from sqlite_hints) ──

pub const isDatetimeSqlType = sqlite_hints.isDatetimeSqlType;
pub const isCurrentTimestamp = sqlite_hints.isCurrentTimestamp;
