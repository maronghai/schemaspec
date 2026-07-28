const std = @import("std");
const dialect_enum = @import("../dialect/enum.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const Dialect = dialect_enum.Dialect;

// ─── Type Registry: Single source of truth for SS types ─────
//
// Production code uses lookupSqlTypeDirect() which returns SqlType variants.
// lookupSqlType() is a convenience wrapper that takes an allocator.
//
// The actual per-dialect mapping lives in each DialectBackend.lookupSym.
// This module is now a thin delegation layer — adding a new SS type only
// requires adding one entry to the relevant backend's lookupSym function.

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
    return aw.toOwnedSlice(alloc) catch null;
}

/// Check if a SS symbol is a known core type.
pub fn isCoreType(sym: []const u8) bool {
    return lookupSqlTypeDirect(sym, .mysql) != null;
}
