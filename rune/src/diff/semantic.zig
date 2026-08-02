const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const reverse_map = @import("../reverse/map.zig");
const TypeInfo = ast_mod.TypeInfo;
const Dialect = dialect_enum.Dialect;

// ─── Dialect-Aware Type Equivalence ──────────────────────────
//
// Determines if two TypeInfo values are semantically equivalent
// within a given SQL dialect. Different SS symbols that resolve
// to the same SQL type are considered equivalent.
//
// Example: MySQL "n" and "N" both resolve to int → equivalent.

/// Check if two TypeInfo values are semantically equivalent.
pub fn typeInfoEquiv(a: TypeInfo, b: TypeInfo) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .none => true,
        .simple => |s| simpleEquiv(s, b.simple),
        .raw_sql => |s| std.mem.eql(u8, s, b.raw_sql),
        .int_explicit => |n| n == b.int_explicit,
        .decimal_explicit => |ds| ds.precision == b.decimal_explicit.precision and ds.scale == b.decimal_explicit.scale,
        .varchar_explicit => |n| n == b.varchar_explicit,
        .enum_type => |vals| {
            if (vals.len != b.enum_type.len) return false;
            for (vals, 0..) |v, i| {
                if (!std.mem.eql(u8, v, b.enum_type[i])) return false;
            }
            return true;
        },
    };
}

/// Canonical form of a SS type symbol.
/// Equivalent symbols map to the same canonical form.
/// NOTE: n and N are NOT equivalent — they map to int vs bigint.
pub fn canonicalSimple(sym: []const u8) ?[]const u8 {
    if (sym.len == 0) return null;
    return switch (sym[0]) {
        'n', 'N' => if (sym.len == 1) sym else switch (sym[1]) {
            '4' => "4",
            '8' => "8",
            else => null,
        },
        '4' => "4",
        '8' => "8",
        'd' => "d",
        's' => if (sym.len == 1) "s" else sym,
        't' => "t",
        'b', 'B' => sym, // b (boolean) and B (blob) are different
        'j' => "j",
        'm' => "m",
        'e' => "e",
        else => null,
    };
}

/// Check if two simple SS type symbols are equivalent.
pub fn simpleEquiv(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return true;
    const ca = canonicalSimple(a) orelse return false;
    const cb = canonicalSimple(b) orelse return false;
    return std.mem.eql(u8, ca, cb);
}

// ─── SQL-Level Semantic Equivalence ──────────────────────────
//
// Compares two SQL type strings by reverse-looking-up each to its
// SS symbol and checking if the symbols are identical. This is the
// SQL-string-level counterpart to typeInfoEquiv (which works on AST
// TypeInfo values).

/// Check if two SQL type strings are semantically equivalent via reverse lookup.
pub fn semanticEquiv(a_sql_type: []const u8, a_col_name: []const u8, a_dialect: Dialect, b_sql_type: []const u8, b_col_name: []const u8, b_dialect: Dialect) bool {
    const a_sym = reverse_map.reverseLookup(a_sql_type, a_col_name, false, false, a_dialect).sym;
    const b_sym = reverse_map.reverseLookup(b_sql_type, b_col_name, false, false, b_dialect).sym;
    return std.mem.eql(u8, a_sym, b_sym);
}
