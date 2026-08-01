const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const TypeInfo = ast_mod.TypeInfo;
const dialect_enum = @import("../dialect/enum.zig");
const sql_type_mod = @import("../types/sql_type.zig");

// ─── Unified Type Mapping ────────────────────────────────────
//
// Helper functions for type classification and custom type lookup.
// SqlType → SQL rendering is self-contained in sql_type.zig:SqlType.toSql().

pub const Dialect = dialect_enum.Dialect;

// ─── Helper: classify SS type symbols ───────────────────────

pub fn isNumericSymType(ti: TypeInfo) bool {
    return ti.isNumeric();
}

pub fn isDatetimeSymType(ti: TypeInfo) bool {
    return ti.isDatetime();
}

// ─── Custom Type Lookup ──────────────────────────────────────

/// Look up a custom type by name in the schema's custom_types list.
/// Returns the resolved TypeInfo for the given dialect, checking dialect-specific
/// overrides first, then falling back to the base type.
pub fn lookupCustomType(
    custom_types: []const ast_mod.CustomType,
    type_name: []const u8,
    dialect: Dialect,
) ?TypeInfo {
    for (custom_types) |ct| {
        if (std.mem.eql(u8, ct.name, type_name)) {
            // Check dialect-specific overrides first
            for (ct.dialect_overrides) |ov| {
                if (ov.dialect == dialect) {
                    return ov.type_info;
                }
            }
            // Fall back to base type
            return ct.base;
        }
    }
    return null;
}
