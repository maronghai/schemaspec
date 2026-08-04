const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const dialect_enum = @import("../dialect/enum.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const Dialect = dialect_enum.Dialect;

// ─── Type Registry: Single source of truth for SS types ─────
//
// Production code uses lookupSqlTypeDirect() which returns SqlType variants.
// lookupSqlType() is a convenience wrapper that takes an allocator.
// lookupCustomType() resolves custom type definitions with dialect overrides.
//
// The actual per-dialect mapping lives in each DialectBackend.lookupSym.
// This module is the single entry point for all SS symbol → type resolution.

/// Look up SqlType variant directly for a SS symbol in a given dialect.
/// Delegates to DialectBackend.lookupSym (the vtable).
pub fn lookupSqlTypeDirect(sym: []const u8, dialect: Dialect) ?sql_type_mod.SqlType {
    const backend = dialect_mod.getBackend(dialect);
    return backend.lookupSym(sym);
}

/// Look up SQL type name for a SS symbol in a given dialect.
/// Convenience wrapper — delegates to lookupSqlTypeDirect + SqlType.toSql.
pub fn lookupSqlType(sym: []const u8, dialect: Dialect, alloc: std.mem.Allocator) ?[]const u8 {
    const sql_type = lookupSqlTypeDirect(sym, dialect) orelse return null;
    var aw = std.Io.Writer.Allocating.init(alloc);
    sql_type.toSql(dialect, &aw.writer) catch return null;
    return aw.toOwnedSlice() catch null;
}

/// Check if a SS symbol is a known core type.
pub fn isCoreType(sym: []const u8) bool {
    return lookupSqlTypeDirect(sym, .mysql) != null;
}

// ─── Custom Type Lookup ──────────────────────────────────────

/// Look up a custom type by name in the schema's custom_types list.
/// Returns the resolved TypeInfo for the given dialect, checking dialect-specific
/// overrides first, then falling back to the base type.
pub fn lookupCustomType(
    custom_types: []const ast_mod.CustomType,
    type_name: []const u8,
    dialect: Dialect,
) ?ast_mod.TypeInfo {
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
