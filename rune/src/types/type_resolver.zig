const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const type_map = @import("../types/type_map.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Field = ast_mod.Field;
const Dialect = dialect_enum.Dialect;
const TypedAst = typed_ast_mod.TypedAst;
const TypedTable = typed_ast_mod.TypedTable;
const TypedView = typed_ast_mod.TypedView;
const TypedColumn = typed_ast_mod.TypedColumn;
const SqlType = sql_type_mod.SqlType;
const FkDecl = ast_mod.FkDecl;

// ─── TypeResolver: ResolvedAst → TypedAst ──────────────────────
//
// Extracted from typed_ast.zig in v0.4.54 Phase 3 for single-responsibility.
// typed_ast.zig retains IR type definitions and re-exports this module
// for backward compatibility.

pub const TypeResolver = struct {
    pub fn resolve(alloc: std.mem.Allocator, resolved: resolved_ast.ResolvedAst, dialect: Dialect) !TypedAst {
        var tables = try std.ArrayList(TypedTable).initCapacity(alloc, resolved.tables.len);
        for (resolved.tables) |table| {
            var columns = try std.ArrayList(TypedColumn).initCapacity(alloc, table.fields.len);
            // Collect inline FKs from fields + standalone FKs from table
            var all_fks = try std.ArrayList(FkDecl).initCapacity(alloc, table.fks.len + 4);
            for (table.fks) |fk| try all_fks.append(alloc, fk);
            for (table.fields) |field| {
                if (std.mem.eql(u8, field.name, "...")) continue;
                const col = try resolveColumn(alloc, field, dialect, resolved.custom_types);
                try columns.append(alloc, col);
                if (field.fk) |fk| try all_fks.append(alloc, fk);
            }
            try tables.append(alloc, .{
                .name = table.name,
                .comment = table.comment,
                .engine = table.engine,
                .columns = try columns.toOwnedSlice(alloc),
                .fks = try all_fks.toOwnedSlice(alloc),
                .indexes = table.indexes,
                .line_no = table.line_no,
            });
        }
        return .{
            .schema_name = resolved.schema_name,
            .schema_charset = resolved.schema_charset,
            .tables = try tables.toOwnedSlice(alloc),
            .views = try resolveViews(alloc, resolved.views),
            .sql_comments = resolved.sql_comments,
        };
    }

    fn resolveViews(alloc: std.mem.Allocator, views: []const ast_mod.View) ![]const TypedView {
        var result = try std.ArrayList(TypedView).initCapacity(alloc, views.len);
        for (views) |v| {
            try result.append(alloc, .{
                .name = v.name,
                .query = v.query,
                .comment = v.comment,
                .line_no = v.line_no,
            });
        }
        return try result.toOwnedSlice(alloc);
    }

    pub fn resolveColumn(alloc: std.mem.Allocator, field: Field, dialect: Dialect, custom_types: []const ast_mod.CustomType) !TypedColumn {
        return resolveColumnInner(alloc, field, dialect, custom_types, 0);
    }

    fn resolveColumnInner(alloc: std.mem.Allocator, field: Field, dialect: Dialect, custom_types: []const ast_mod.CustomType, depth: u8) !TypedColumn {
        // Check custom types first (multi-char names)
        if (field.type_info == .simple and field.type_info.simple.len > 1) {
            if (type_map.lookupCustomType(custom_types, field.type_info.simple, dialect)) |ct_info| {
                // Detect circular custom type references (e.g., ~A B + ~B A).
                // Max depth of 32 is generous — real schemas rarely exceed 3 levels.
                if (depth >= 32) {
                    return error.CircularCustomType;
                }
                // Recursively resolve the custom type's base info
                return resolveColumnInner(alloc, ast_mod.Field{
                    .name = field.name,
                    .type_info = ct_info,
                    .modifiers = field.modifiers,
                    .default_val = field.default_val,
                    .check = field.check,
                    .fk = field.fk,
                    .comment = field.comment,
                    .line_no = field.line_no,
                }, dialect, custom_types, depth + 1);
            }
        }
        // Resolve to structured SqlType (dialect-agnostic)
        const sql_type = SqlType.fromTypeInfo(field.type_info, dialect);

        // Classify modifiers into boolean flags
        const flags = classifyModifiers(field);

        const is_dt = type_map.isDatetimeSymType(field.type_info);
        const is_enum = field.type_info == .enum_type;
        const enum_vals = if (is_enum) field.type_info.enum_type else &[_][]const u8{};

        // Compute original SS type string for roundtrip preservation (SQLite only)
        const ss_symbol = try buildSymType(alloc, field.type_info, flags.unsigned);

        return .{
            .name = field.name,
            .sql_type = sql_type,
            .ss_symbol = ss_symbol,
            .flags = .{
                .nullable = !flags.nn,
                .primary_key = flags.pk,
                .auto_increment = flags.ai,
                .unsigned = flags.unsigned,
                .inline_unique = flags.inline_unique,
                .inline_index = flags.inline_index,
                .is_enum = is_enum,
                .is_datetime = is_dt,
                .has_timestamp_default = flags.has_timestamp_mod,
                .on_update_current_timestamp = flags.on_update_ts,
                .is_virtual = flags.is_virtual,
                .is_stored = flags.is_stored,
            },
            .default = if (field.default_val) |dv| dv.value else null,
            .check = field.check,
            .comment = field.comment,
            .enum_values = enum_vals,
            .generated_expr = field.generated_expr,
            .line_no = field.line_no,
        };
    }
};

// ─── Modifier Classification ────────────────────────────────────

const ModifierFlags = struct {
    pk: bool = false,
    ai: bool = false,
    nn: bool = false,
    unsigned: bool = false,
    inline_unique: bool = false,
    inline_index: bool = false,
    on_update_ts: bool = false,
    has_timestamp_mod: bool = false,
    is_virtual: bool = false,
    is_stored: bool = false,
};

/// Classifies a field's modifier list into boolean flags.
pub fn classifyModifiers(field: Field) ModifierFlags {
    var flags = ModifierFlags{};
    for (field.modifiers) |mod| {
        switch (mod.kind) {
            .auto_inc_pk => {
                if (type_map.isDatetimeSymType(field.type_info)) {
                    flags.on_update_ts = true;
                    flags.has_timestamp_mod = true;
                } else {
                    flags.pk = true;
                    flags.ai = true;
                }
            },
            .auto_inc => {
                if (type_map.isDatetimeSymType(field.type_info)) {
                    flags.has_timestamp_mod = true;
                } else {
                    flags.ai = true;
                }
            },
            .primary_key => flags.pk = true,
            .not_null => flags.nn = true,
            .unsigned => flags.unsigned = true,
            .inline_unique => flags.inline_unique = true,
            .inline_index => flags.inline_index = true,
            .virtual => flags.is_virtual = true,
            .stored => flags.is_stored = true,
        }
    }
    return flags;
}

// ─── Sym Type Computation ───────────────────────────────────────

/// Compute the original SS type string for roundtrip preservation (SQLite only).
/// Returns null for multi-char types (custom types are resolved before this).
pub fn buildSymType(alloc: std.mem.Allocator, type_info: ast_mod.TypeInfo, unsigned: bool) !?[]const u8 {
    var sym: ?[]const u8 = switch (type_info) {
        .simple => |s| if (s.len == 1) s else null,
        .varchar_explicit => |n| if (n > 0) blk: {
            var tbuf: [16]u8 = undefined;
            const result = try std.fmt.bufPrint(&tbuf, "s{d}", .{n});
            break :blk try alloc.dupe(u8, result);
        } else null,
        .decimal_explicit => |ds| blk: {
            var tbuf: [16]u8 = undefined;
            const result = try std.fmt.bufPrint(&tbuf, "{d},{d}", .{ ds.precision, ds.scale });
            break :blk try alloc.dupe(u8, result);
        },
        .none => "s",
        else => null,
    };
    // Unsigned → prepend + prefix for roundtrip (+n, +N, +i)
    if (unsigned) {
        if (sym) |tt| {
            if (tt.len == 1 and (tt[0] == 'n' or tt[0] == 'N' or tt[0] == 'i')) {
                sym = try std.fmt.allocPrint(alloc, "+{s}", .{tt});
            }
        }
    }
    return sym;
}
