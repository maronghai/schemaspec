// Shared test helpers for lint rule tests.
// Extracted from rules_test.zig to eliminate duplication across test files.

const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;

// ─── Table Helpers ────────────────────────────────────────────

pub fn makeTestTable(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field, indexes: []const ast_mod.IndexDecl) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = &.{},
        .indexes = indexes,
        .line_no = 1,
    };
}

pub fn makeTestTableWithFkDecls(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field, fks: []const ast_mod.FkDecl) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = try alloc.dupe(ast_mod.FkDecl, fks),
        .indexes = &.{},
        .line_no = 1,
    };
}

pub fn makeTestTableWithFks(alloc: std.mem.Allocator, name: []const u8, fields: []const ast_mod.Field) !ResolvedTable {
    return .{
        .name = name,
        .comment = null,
        .engine = null,
        .fields = try alloc.dupe(ast_mod.Field, fields),
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
}

// ─── Field Helpers ────────────────────────────────────────────

pub fn makeField(name: []const u8, type_info: ast_mod.TypeInfo, modifiers: []const ast_mod.Modifier, fk: ?ast_mod.FkDecl) ast_mod.Field {
    return .{
        .name = name,
        .type_info = type_info,
        .modifiers = modifiers,
        .default_val = null,
        .check = null,
        .fk = fk,
        .comment = null,
        .line_no = 1,
    };
}

pub fn makePkField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{.{ .kind = .auto_inc_pk, .line_no = 1 }}, null);
}

pub fn makeFkField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = "other",
        .ref_fields = &.{"id"},
        .actions = &.{},
        .line_no = 1,
    });
}

pub fn makeFkFieldTo(name: []const u8, ref_table: []const u8, ref_field: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = ref_table,
        .ref_fields = &.{ref_field},
        .actions = &.{},
        .line_no = 1,
    });
}

pub fn makeFkFieldWithActions(name: []const u8, actions: []const ast_mod.FkAction) ast_mod.Field {
    return makeField(name, .{ .simple = "n" }, &.{}, .{
        .fields = &.{name},
        .ref_table = "other",
        .ref_fields = &.{"id"},
        .actions = actions,
        .line_no = 1,
    });
}

pub fn makeSimpleField(name: []const u8) ast_mod.Field {
    return makeField(name, .{ .simple = "s" }, &.{}, null);
}

// ─── Index Helpers ────────────────────────────────────────────

pub fn makeIndex(name: []const u8, kind: ast_mod.IndexType, fields: []const []const u8) ast_mod.IndexDecl {
    return .{
        .kind = kind,
        .name = name,
        .fields = fields,
        .descending = &.{},
        .line_no = 1,
    };
}

// ─── AST Helpers ──────────────────────────────────────────────

pub fn makeAst(tables: []const ResolvedTable) ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

pub fn makeAstWithCustomTypes(tables: []const ResolvedTable, custom_types: []const ast_mod.CustomType) ResolvedAst {
    return .{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = custom_types,
        .tables = tables,
        .views = &.{},
        .sql_comments = &.{},
    };
}

pub fn makeCustomType(name: []const u8) ast_mod.CustomType {
    return .{
        .name = name,
        .base = .{ .simple = name },
        .dialect_overrides = &.{},
        .line_no = 1,
    };
}

// ─── Lint Helpers ─────────────────────────────────────────────

pub fn findRule(results: anytype, rule_name: []const u8) bool {
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, rule_name)) return true;
    }
    return false;
}

pub fn countRule(results: anytype, rule_name: []const u8) usize {
    var count: usize = 0;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, rule_name)) count += 1;
    }
    return count;
}

pub fn findRuleWithSubstring(results: anytype, rule_name: []const u8, substring: []const u8) bool {
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, rule_name) and std.mem.indexOf(u8, r.message, substring) != null) return true;
    }
    return false;
}
