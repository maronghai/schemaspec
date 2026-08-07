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

// ─── Table-Driven Parameterized Type Patterns ──────────────
// Each entry maps a SQL type prefix to an SS symbol prefix.
// Matched types return `sym_prefix ++ inner` where inner has spaces stripped.
// Example: "varchar(" → "s" means "varchar(255)" → "s255".
// The "s" prefix case is handled separately since varchar(255) → "s" (no length suffix).

const ParamPattern = struct {
    prefix: []const u8,
    sym_prefix: []const u8,
};

/// Types that map to `sym_prefix ++ inner` for single-param, or `inner` (stripped) for multi-param.
const PARAM_PATTERNS = [_]ParamPattern{
    .{ .prefix = "varchar(", .sym_prefix = "s" },
    .{ .prefix = "character varying(", .sym_prefix = "s" },
    .{ .prefix = "varchar2(", .sym_prefix = "s" },
    .{ .prefix = "nvarchar2(", .sym_prefix = "s" },
    .{ .prefix = "decimal(", .sym_prefix = "" },
    .{ .prefix = "numeric(", .sym_prefix = "" },
    .{ .prefix = "int(", .sym_prefix = "" },
};

/// Match a parameterized type pattern. Returns sym_prefix ++ inner (single-param) or stripped inner (multi-param).
/// Confidence is 85 for standard parameterized types (e.g. varchar(128) → s128).
fn matchParam(t: []const u8, prefix: []const u8, sym_prefix: []const u8) ?ReverseResult {
    const rest = matchPrefix(t, prefix) orelse return null;
    if (!std.mem.endsWith(u8, rest, ")")) return null;

    const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");

    // varchar(255) → "s" (no length suffix)
    if (std.mem.eql(u8, sym_prefix, "s") and std.mem.eql(u8, inner, "255"))
        return .{ .sym = "s", .omit = true, .score = 100 };

    // Multi-param: strip spaces entirely
    const buf = struct {
        var b: [32]u8 = undefined;
    };
    var j: usize = 0;
    for (inner) |ch| {
        if (ch != ' ') {
            if (j >= 32) return .{ .sym = t, .omit = false, .score = 50 };
            buf.b[j] = ch;
            j += 1;
        }
    }

    // If result has a comma (decimal/number with P,S), return stripped inner directly
    var has_comma = false;
    for (buf.b[0..j]) |ch| {
        if (ch == ',') {
            has_comma = true;
            break;
        }
    }
    if (has_comma) return .{ .sym = buf.b[0..j], .omit = false, .score = 85 };

    // Single param: prepend sym_prefix
    const total_len = sym_prefix.len + j;
    if (total_len > 15) return .{ .sym = t, .omit = false, .score = 50 };

    const result = struct {
        var b: [16]u8 = undefined;
    };
    var k: usize = 0;
    for (sym_prefix) |ch| {
        result.b[k] = ch;
        k += 1;
    }
    for (buf.b[0..j]) |ch| {
        result.b[k] = ch;
        k += 1;
    }
    return .{ .sym = result.b[0..k], .omit = false, .score = 85 };
}

/// Match NUMBER(P) or NUMBER(P,S). NUMBER(P) → "N" ++ P, NUMBER(P,S) → "P,S" stripped.
/// Confidence is 85 for standard parameterized number types.
fn matchNumber(t: []const u8) ?ReverseResult {
    const rest = matchPrefix(t, "number(") orelse return null;
    if (!std.mem.endsWith(u8, rest, ")")) return null;

    const inner = std.mem.trim(u8, rest[0 .. rest.len - 1], " ");

    // Multi-param: strip spaces
    const buf = struct {
        var b: [32]u8 = undefined;
    };
    var j: usize = 0;
    for (inner) |ch| {
        if (ch != ' ') {
            if (j >= 32) return .{ .sym = t, .omit = false, .score = 50 };
            buf.b[j] = ch;
            j += 1;
        }
    }

    // If result has a comma (P,S), return stripped inner directly
    var has_comma = false;
    for (buf.b[0..j]) |ch| {
        if (ch == ',') {
            has_comma = true;
            break;
        }
    }
    if (has_comma) return .{ .sym = buf.b[0..j], .omit = false, .score = 85 };

    // Single param: "N" ++ P
    const total_len = 1 + j;
    if (total_len > 15) return .{ .sym = t, .omit = false, .score = 50 };

    const result = struct {
        var b: [16]u8 = undefined;
    };
    result.b[0] = 'N';
    for (buf.b[0..j], 0..) |ch, i| {
        result.b[i + 1] = ch;
    }
    return .{ .sym = result.b[0..total_len], .omit = false, .score = 85 };
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

    // ─── Table-driven parameterized type matching ───
    inline for (PARAM_PATTERNS) |p| {
        if (matchParam(t, p.prefix, p.sym_prefix)) |result| return result;
    }

    // NUMBER(P) → "N" ++ P, NUMBER(P,S) → "P,S" (special handling: "N" prefix)
    if (matchNumber(t)) |result| return result;

    // ENUM(...) → pass through (low confidence: custom types are uncertain)
    if (std.mem.startsWith(u8, t, "ENUM(") or std.mem.startsWith(u8, t, "enum("))
        return .{ .sym = t, .omit = false, .score = 60 };

    // Unknown type → passthrough with low confidence
    return .{ .sym = t, .omit = false, .score = 50 };
}

// ─── Helper: classify SQL type strings (re-exports from sqlite_hints) ──

pub const isDatetimeSqlType = sqlite_hints.isDatetimeSqlType;
pub const isCurrentTimestamp = sqlite_hints.isCurrentTimestamp;
