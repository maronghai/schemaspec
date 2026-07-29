const std = @import("std");
const parse_field = @import("parse_field.zig");
const parse_template = @import("parse_template.zig");
const tk = @import("tokenizer.zig");
const ast_mod = @import("../types/ast.zig");

const testing = std.testing;

// ─── tryParseType tests ──────────────────────────────────────

test "tryParseType: single-char symbols" {
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "n" }), parse_field.tryParseType("n"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "N" }), parse_field.tryParseType("N"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "i" }), parse_field.tryParseType("i"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "m" }), parse_field.tryParseType("m"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "M" }), parse_field.tryParseType("M"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "S" }), parse_field.tryParseType("S"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "b" }), parse_field.tryParseType("b"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "B" }), parse_field.tryParseType("B"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "j" }), parse_field.tryParseType("j"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "J" }), parse_field.tryParseType("J"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "I" }), parse_field.tryParseType("I"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "d" }), parse_field.tryParseType("d"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "t" }), parse_field.tryParseType("t"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "T" }), parse_field.tryParseType("T"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "U" }), parse_field.tryParseType("U"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .simple = "p" }), parse_field.tryParseType("p"));
}

test "tryParseType: varchar s with explicit length" {
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .varchar_explicit = 0 }), parse_field.tryParseType("s"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .varchar_explicit = 128 }), parse_field.tryParseType("s128"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .varchar_explicit = 255 }), parse_field.tryParseType("s255"));
}

test "tryParseType: explicit integer" {
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .int_explicit = 16 }), parse_field.tryParseType("16"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .int_explicit = 64 }), parse_field.tryParseType("64"));
}

test "tryParseType: decimal with precision,scale" {
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .decimal_explicit = .{ .precision = 10, .scale = 2 } }), parse_field.tryParseType("10,2"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, .{ .decimal_explicit = .{ .precision = 16, .scale = 4 } }), parse_field.tryParseType("16,4"));
}

test "tryParseType: invalid inputs return null" {
    try testing.expectEqual(@as(?ast_mod.TypeInfo, null), parse_field.tryParseType(""));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, null), parse_field.tryParseType("x"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, null), parse_field.tryParseType("abc"));
    try testing.expectEqual(@as(?ast_mod.TypeInfo, null), parse_field.tryParseType("sxyz"));
}

// ─── parseFusedTypeModifier tests ────────────────────────────

test "parseFusedTypeModifier: auto-inc pk (n++)" {
    const result = parse_field.parseFusedTypeModifier("n++", 1) orelse return error.UnexpectedNull;
    try testing.expect(result.type_info != null);
    try testing.expect(result.modifier != null);
    try testing.expectEqual(@as(?ast_mod.ModifierType, .auto_inc_pk), result.modifier.?.kind);
}

test "parseFusedTypeModifier: not-null (s*)" {
    const result = parse_field.parseFusedTypeModifier("s*", 1) orelse return error.UnexpectedNull;
    try testing.expect(result.type_info != null);
    try testing.expect(result.modifier != null);
    try testing.expectEqual(@as(?ast_mod.ModifierType, .not_null), result.modifier.?.kind);
}

test "parseFusedTypeModifier: primary key (n!)" {
    const result = parse_field.parseFusedTypeModifier("n!", 1) orelse return error.UnexpectedNull;
    try testing.expect(result.type_info != null);
    try testing.expect(result.modifier != null);
    try testing.expectEqual(@as(?ast_mod.ModifierType, .primary_key), result.modifier.?.kind);
}

test "parseFusedTypeModifier: not-null + default (*=0)" {
    const result = parse_field.parseFusedTypeModifier("*=0", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(?ast_mod.TypeInfo, null), result.type_info);
    try testing.expect(result.modifier != null);
    try testing.expectEqual(@as(?ast_mod.ModifierType, .not_null), result.modifier.?.kind);
    try testing.expect(result.default_val != null);
}

test "parseFusedTypeModifier: plain type returns null" {
    try testing.expectEqual(@as(?parse_field.FusedTypeResult, null), parse_field.parseFusedTypeModifier("n", 1));
    try testing.expectEqual(@as(?parse_field.FusedTypeResult, null), parse_field.parseFusedTypeModifier("s128", 1));
}

// ─── parseStandaloneModifier tests ───────────────────────────

test "parseStandaloneModifier: auto_inc_pk (++)" {
    const tokens = [_][]const u8{"++"};
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "++", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .auto_inc_pk), result.modifier.kind);
    try testing.expectEqual(@as(usize, 1), result.end_idx);
}

test "parseStandaloneModifier: auto_inc (+)" {
    const tokens = [_][]const u8{"+"};
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "+", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .auto_inc), result.modifier.kind);
}

test "parseStandaloneModifier: not_null (*)" {
    const tokens = [_][]const u8{"*"};
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "*", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .not_null), result.modifier.kind);
}

test "parseStandaloneModifier: primary_key (!)" {
    const tokens = [_][]const u8{"!"};
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "!", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .primary_key), result.modifier.kind);
}

test "parseStandaloneModifier: inline_unique (@u)" {
    const tokens = [_][]const u8{ "@", "u" };
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "@ u", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .inline_unique), result.modifier.kind);
    try testing.expectEqual(@as(usize, 2), result.end_idx);
}

test "parseStandaloneModifier: inline_index (@)" {
    const tokens = [_][]const u8{"@"};
    const result = parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "@", 1) orelse return error.UnexpectedNull;
    try testing.expectEqual(@as(ast_mod.ModifierType, .inline_index), result.modifier.kind);
}

test "parseStandaloneModifier: unknown token returns null" {
    const tokens = [_][]const u8{"hello"};
    try testing.expectEqual(@as(?parse_field.ModifierResult, null), parse_field.parseStandaloneModifier(testing.allocator, &tokens, 0, "hello", 1));
}

// ─── parseTemplateHeader tests ───────────────────────────────

test "parseTemplateHeader: simple template" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "base" },
        .raw = "% base",
        .line_no = 1,
        .offset = 0,
        .trimmed = "% base",
    };

    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("base", header.name.?);
    try testing.expectEqual(@as(usize, 0), header.parents.len);
}

test "parseTemplateHeader: template with parent via >" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "child", ">", "parent" },
        .raw = "% child > parent",
        .line_no = 1,
        .offset = 0,
        .trimmed = "% child > parent",
    };

    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("child", header.name.?);
    try testing.expectEqual(@as(usize, 1), header.parents.len);
    try testing.expectEqualStrings("parent", header.parents[0]);
}

test "parseTemplateHeader: template with multiple parents via +" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const line = tk.Line{
        .line_type = .Template,
        .tokens = &.{ "%", "child", ">", "p1", "+", "p2" },
        .raw = "% child > p1 + p2",
        .line_no = 1,
        .offset = 0,
        .trimmed = "% child > p1 + p2",
    };

    const header = try parse_template.parseTemplateHeader(alloc, line);
    try testing.expect(header.name != null);
    try testing.expectEqualStrings("child", header.name.?);
    try testing.expectEqual(@as(usize, 2), header.parents.len);
    try testing.expectEqualStrings("p1", header.parents[0]);
    try testing.expectEqualStrings("p2", header.parents[1]);
}

test "findSlot: detects slot marker" {
    const fields = [_]ast_mod.Field{
        .{ .name = "id", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
        .{ .name = "...", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 2 },
        .{ .name = "created_at", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 3 },
    };
    try testing.expectEqual(@as(?usize, 1), parse_template.findSlot(&fields));
}

test "findSlot: no slot returns null" {
    const fields = [_]ast_mod.Field{
        .{ .name = "id", .type_info = .none, .modifiers = &.{}, .default_val = null, .check = null, .fk = null, .comment = null, .line_no = 1 },
    };
    try testing.expectEqual(@as(?usize, null), parse_template.findSlot(&fields));
}

// ─── classifyCheck tests (extracted from parser.zig) ──────────

const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;

test "classifyCheck: range" {
    try testing.expectEqual(ast_mod.CheckKind.range, Parser.classifyCheck("1, 100", '[', ']'));
    try testing.expectEqual(ast_mod.CheckKind.range_upper_exclusive, Parser.classifyCheck("1, 100", '[', ')'));
    try testing.expectEqual(ast_mod.CheckKind.range_lower_exclusive, Parser.classifyCheck("1, 100", '(', ']'));
    try testing.expectEqual(ast_mod.CheckKind.range_both_exclusive, Parser.classifyCheck("1, 100", '(', ')'));
}

test "classifyCheck: in_list" {
    try testing.expectEqual(ast_mod.CheckKind.in_list, Parser.classifyCheck("active inactive", '{', '}'));
}

test "classifyCheck: comparison" {
    try testing.expectEqual(ast_mod.CheckKind.comparison, Parser.classifyCheck("price > 0", '{', '}'));
    try testing.expectEqual(ast_mod.CheckKind.comparison, Parser.classifyCheck("price > 0 AND price < 10000", '[', ']'));
}
