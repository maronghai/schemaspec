const std = @import("std");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");
const parse_field = @import("parse_field.zig");
const dialect_enum = @import("../dialect/enum.zig");
const TypeInfo = ast_mod.TypeInfo;

/// Parse a dialect name string into a Dialect enum. Returns null for unrecognized names.
fn parseDialect(s: []const u8) ?dialect_enum.Dialect {
    if (std.mem.eql(u8, s, "mysql")) return .mysql;
    if (std.mem.eql(u8, s, "pg") or std.mem.eql(u8, s, "postgres")) return .pg;
    if (std.mem.eql(u8, s, "sqlite") or std.mem.eql(u8, s, "sq")) return .sqlite;
    if (std.mem.eql(u8, s, "mssql") or std.mem.eql(u8, s, "sqlserver")) return .mssql;
    if (std.mem.eql(u8, s, "oracle")) return .oracle;
    if (std.mem.eql(u8, s, "db2")) return .db2;
    return null;
}

// ─── TypeDef Parsing ───────────────────────────────────────
// Extracted from parser.zig for single-responsibility.
// Handles: ~ name base_type  OR  ~ name dialect1=type1 dialect2=type2

pub fn parseTypeDef(alloc: std.mem.Allocator, line: tk.Line) !ast_mod.CustomType {
    // tokens: ["~", "name", ...]
    const name = try alloc.dupe(u8, line.tokens[1]);

    var base: TypeInfo = .none;
    var overrides = try std.ArrayList(ast_mod.DialectOverride).initCapacity(alloc, 4);

    var i: usize = 2;
    // Skip = if present
    if (i < line.tokens.len and std.mem.eql(u8, line.tokens[i], "=")) {
        i += 1;
    }
    // Parse base type (first non-dialect token after =)
    if (i < line.tokens.len) {
        const tok = line.tokens[i];
        if (std.mem.indexOfScalar(u8, tok, '=') != null) {
            // dialect=type format — no base type, only overrides
        } else {
            base = parse_field.tryParseType(tok) orelse .{ .simple = try alloc.dupe(u8, tok) };
            i += 1;
        }
    }
    // Parse dialect overrides: dialect=type pairs
    while (i < line.tokens.len) : (i += 1) {
        const tok = line.tokens[i];
        if (std.mem.indexOfScalar(u8, tok, '=')) |eq_pos| {
            const dialect_str = tok[0..eq_pos];
            const type_str = try alloc.dupe(u8, tok[eq_pos + 1 ..]);
            const type_info: TypeInfo = parse_field.tryParseType(type_str) orelse .{ .raw_sql = type_str };
            if (parseDialect(dialect_str)) |dialect| {
                try overrides.append(alloc, .{ .dialect = dialect, .type_info = type_info });
            }
        }
    }

    return .{
        .name = name,
        .base = base,
        .dialect_overrides = try overrides.toOwnedSlice(alloc),
        .line_no = line.line_no,
    };
}
